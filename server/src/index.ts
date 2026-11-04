import { Hono, type Context } from 'hono';
import { HTTPException } from 'hono/http-exception';
import {
  ApiError,
  EXTEND_SQL,
  IMAGE_TYPES,
  LIMIT_COMMENTS,
  LIMIT_GLOBAL,
  LIMIT_USER,
  MAX_IMAGES,
  MAX_IMAGE_BYTES,
  POST_TTL,
  REPORT_HIDE_THRESHOLD,
  SIGNUP_PER_IP_PER_DAY,
  excerpt,
  hmacHex,
  newId,
  randomNickname,
  signSession,
  str,
  tagList,
  utcDay,
  verifyAccessJwt,
  verifyGoogleIdToken,
  verifySession,
} from './lib';
import { ADMIN_HTML } from './admin_page';

type Vars = { uid: string | null };
type AppEnv = { Bindings: Env; Variables: Vars };
type C = Context<AppEnv>;

interface PostRow {
  id: string;
  user_id: string;
  title: string;
  body_md: string;
  tags_json: string;
  images_json: string;
  created_at: number;
  updated_at: number;
  edited: number;
  expires_at: number;
  like_count: number;
  comment_count: number;
  report_count: number;
  status: string;
  nickname?: string | null;
  liked?: number | null;
}

interface UserRow {
  id: string;
  sub_hash: string;
  nickname: string;
  created_at: number;
  banned: string | null;
}

const app = new Hono<AppEnv>();

// ---------------------------------------------------------------- 共通

app.onError((err, c) => {
  if (err instanceof ApiError) {
    return c.json({ error: { code: err.code, message: err.message, ...err.extra } }, err.status);
  }
  if (err instanceof HTTPException) {
    return c.json({ error: { code: 'VALIDATION', message: err.message } }, err.status);
  }
  console.error(JSON.stringify({ level: 'error', path: c.req.path, message: String(err) }));
  return c.json({ error: { code: 'INTERNAL', message: 'サーバーエラーが発生しました' } }, 500);
});

app.notFound((c) => c.json({ error: { code: 'NOT_FOUND', message: 'Not Found' } }, 404));

/** Authorization: Bearer <session> を読み、uid をセットする（任意認証） */
app.use('*', async (c, next) => {
  const h = c.req.header('Authorization');
  const token = h?.startsWith('Bearer ') ? h.slice(7) : null;
  c.set('uid', token ? await verifySession(c.env.SESSION_SECRET, token) : null);
  await next();
});

async function loadUser(c: C, uid: string): Promise<UserRow | null> {
  return c.env.DB.prepare(
    `SELECT u.*, b.sub_hash AS banned FROM users u LEFT JOIN bans b ON b.sub_hash = u.sub_hash WHERE u.id = ?1`,
  )
    .bind(uid)
    .first<UserRow>();
}

/** ログイン必須。書き込み系では毎回 users の存在と bans を確認する（7.3） */
async function requireUser(c: C, { allowBanned = false } = {}): Promise<UserRow> {
  const uid = c.get('uid');
  if (!uid) throw new ApiError(401, 'UNAUTHORIZED', 'ログインが必要です');
  const user = await loadUser(c, uid);
  if (!user) throw new ApiError(401, 'UNAUTHORIZED', 'ログインし直してください');
  if (user.banned && !allowBanned) throw new ApiError(403, 'BANNED', 'このアカウントは利用停止されています');
  return user;
}

async function readJson(c: C): Promise<Record<string, unknown>> {
  try {
    const v = await c.req.json();
    return v && typeof v === 'object' ? (v as Record<string, unknown>) : {};
  } catch {
    throw new ApiError(400, 'VALIDATION', 'JSON が不正です');
  }
}

function postJson(p: PostRow, uid: string | null, withBody: boolean) {
  return {
    id: p.id,
    title: p.title,
    excerpt: excerpt(p.body_md),
    ...(withBody ? { body: p.body_md } : {}),
    tags: JSON.parse(p.tags_json) as string[],
    images: JSON.parse(p.images_json) as string[],
    author: { nickname: p.nickname ?? '退会したユーザー' },
    isMine: uid !== null && p.user_id === uid,
    likedByMe: p.liked === 1,
    likeCount: p.like_count,
    commentCount: p.comment_count,
    createdAt: p.created_at,
    updatedAt: p.updated_at,
    edited: p.edited === 1,
    expiresAt: p.expires_at,
    hidden: p.status !== 'active',
  };
}

const POST_SELECT = `SELECT p.*, u.nickname,
  (SELECT l.active FROM likes l WHERE l.post_id = p.id AND l.user_id = ?2) AS liked
  FROM posts p LEFT JOIN users u ON u.id = p.user_id`;

/** 公開中の投稿を取得。なければ POST_GONE */
async function getLivePost(c: C, id: string, now: number): Promise<PostRow> {
  const p = await c.env.DB.prepare(`SELECT * FROM posts WHERE id = ?1 AND expires_at > ?2 AND status = 'active'`)
    .bind(id, now)
    .first<PostRow>();
  if (!p) throw new ApiError(404, 'POST_GONE', 'この投稿は公開終了しました');
  return p;
}

async function nextFreeAt(db: D1Database, now: number, userId?: string): Promise<number | null> {
  const r = userId
    ? await db.prepare(`SELECT MIN(expires_at) AS t FROM posts WHERE user_id = ?1 AND expires_at > ?2`).bind(userId, now).first<{ t: number | null }>()
    : await db.prepare(`SELECT MIN(expires_at) AS t FROM posts WHERE expires_at > ?1`).bind(now).first<{ t: number | null }>();
  return r?.t ?? null;
}

/** 投稿と関連データ・画像を物理削除する */
async function purgePosts(env: Env, posts: { id: string; images_json: string }[]): Promise<void> {
  if (posts.length === 0) return;
  const keys = posts.flatMap((p) => JSON.parse(p.images_json) as string[]);
  for (let i = 0; i < keys.length; i += 1000) await env.IMAGES.delete(keys.slice(i, i + 1000));
  const stmts = posts.flatMap((p) => [
    env.DB.prepare(`DELETE FROM likes WHERE post_id = ?1`).bind(p.id),
    env.DB.prepare(`DELETE FROM comments WHERE post_id = ?1`).bind(p.id),
    env.DB.prepare(`DELETE FROM comment_extends WHERE post_id = ?1`).bind(p.id),
    env.DB.prepare(`DELETE FROM reports WHERE post_id = ?1`).bind(p.id),
    env.DB.prepare(`DELETE FROM posts WHERE id = ?1`).bind(p.id),
  ]);
  for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
}

async function deleteComment(env: Env, commentId: string, postId: string): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(`DELETE FROM comments WHERE id = ?1`).bind(commentId),
    env.DB.prepare(`DELETE FROM reports WHERE target_type = 'comment' AND target_id = ?1`).bind(commentId),
    env.DB.prepare(`UPDATE posts SET comment_count = MAX(comment_count - 1, 0) WHERE id = ?1`).bind(postId),
  ]);
}

/** multipart の画像を検証して返す */
async function readImages(form: FormData): Promise<{ bytes: ArrayBuffer; type: string }[]> {
  const files = form.getAll('images').filter((f): f is File => typeof f !== 'string');
  const out: { bytes: ArrayBuffer; type: string }[] = [];
  for (const f of files) {
    if (!IMAGE_TYPES[f.type]) throw new ApiError(400, 'VALIDATION', '画像は JPEG か WebP にしてください', { field: 'images' });
    if (f.size > MAX_IMAGE_BYTES) throw new ApiError(400, 'VALIDATION', '画像は 1 枚 500KB 以下にしてください', { field: 'images' });
    out.push({ bytes: await f.arrayBuffer(), type: f.type });
  }
  return out;
}

async function readPostForm(c: C) {
  let form: FormData;
  try {
    form = await c.req.formData();
  } catch {
    throw new ApiError(400, 'VALIDATION', 'multipart/form-data で送信してください');
  }
  const raw = form.get('data');
  let data: Record<string, unknown> = {};
  try {
    data = typeof raw === 'string' ? JSON.parse(raw) : {};
  } catch {
    throw new ApiError(400, 'VALIDATION', 'data が不正です');
  }
  return {
    title: str(data.title, 'title', 1, 100),
    body: str(data.body, 'body', 1, 10000),
    tags: tagList(data.tags),
    keepImages: Array.isArray(data.keepImages) ? data.keepImages.filter((k): k is string => typeof k === 'string') : [],
    images: await readImages(form),
  };
}

async function putImages(env: Env, postId: string, images: { bytes: ArrayBuffer; type: string }[]): Promise<string[]> {
  const keys: string[] = [];
  for (const img of images) {
    const key = `posts/${postId}/${newId()}.${IMAGE_TYPES[img.type]}`;
    await env.IMAGES.put(key, img.bytes, { httpMetadata: { contentType: img.type } });
    keys.push(key);
  }
  return keys;
}

// ---------------------------------------------------------------- 認証・アカウント

app.get('/', (c) => c.json({ name: 'techmeku-api', ok: true }));

app.post('/auth/google', async (c) => {
  const body = await readJson(c);
  const idToken = str(body.idToken, 'idToken', 1, 8192);
  const sub = await verifyGoogleIdToken(idToken, c.env.GOOGLE_CLIENT_ID);
  const subHash = await hmacHex(c.env.SERVER_SECRET, sub);
  const db = c.env.DB;

  if (await db.prepare(`SELECT 1 FROM bans WHERE sub_hash = ?1`).bind(subHash).first()) {
    throw new ApiError(403, 'BANNED', 'このアカウントは利用停止されています');
  }
  let user = await db.prepare(`SELECT * FROM users WHERE sub_hash = ?1`).bind(subHash).first<UserRow>();
  if (!user) {
    const now = Date.now();
    const day = utcDay(now);
    const ip = c.req.header('CF-Connecting-IP') ?? 'unknown';
    const ipHash = await hmacHex(c.env.IP_SALT_SECRET, `${day}:${ip}`);
    const cnt = await db.prepare(`SELECT count FROM signup_ip_counts WHERE ip_hash = ?1 AND day = ?2`).bind(ipHash, day).first<{ count: number }>();
    if ((cnt?.count ?? 0) >= SIGNUP_PER_IP_PER_DAY) {
      throw new ApiError(429, 'SIGNUP_LIMIT', '本日はこれ以上アカウントを作成できません');
    }
    const id = newId();
    await db.batch([
      db.prepare(`INSERT INTO users (id, sub_hash, nickname, created_at) VALUES (?1, ?2, ?3, ?4)`).bind(id, subHash, randomNickname(), now),
      db.prepare(
        `INSERT INTO signup_ip_counts (ip_hash, day, count) VALUES (?1, ?2, 1)
         ON CONFLICT (ip_hash, day) DO UPDATE SET count = count + 1`,
      ).bind(ipHash, day),
    ]);
    user = await db.prepare(`SELECT * FROM users WHERE id = ?1`).bind(id).first<UserRow>();
  }
  const token = await signSession(c.env.SESSION_SECRET, user!.id);
  return c.json({ token, user: { id: user!.id, nickname: user!.nickname } });
});

app.get('/me', async (c) => {
  const user = await requireUser(c, { allowBanned: true });
  const now = Date.now();
  const r = await c.env.DB.prepare(`SELECT COUNT(*) AS n FROM posts WHERE user_id = ?1 AND expires_at > ?2`).bind(user.id, now).first<{ n: number }>();
  return c.json({ id: user.id, nickname: user.nickname, activePostCount: r?.n ?? 0, banned: !!user.banned });
});

app.patch('/me', async (c) => {
  const user = await requireUser(c);
  const body = await readJson(c);
  const nickname = str(body.nickname, 'nickname', 1, 20);
  await c.env.DB.prepare(`UPDATE users SET nickname = ?1 WHERE id = ?2`).bind(nickname, user.id).run();
  return c.json({ id: user.id, nickname });
});

/** 退会：投稿・コメント・いいね・画像を即削除。停止記録（bans）だけ残す */
app.delete('/me', async (c) => {
  const user = await requireUser(c, { allowBanned: true });
  const env = c.env;
  const db = env.DB;
  const mine = await db.prepare(`SELECT id, images_json FROM posts WHERE user_id = ?1`).bind(user.id).all<{ id: string; images_json: string }>();
  await purgePosts(env, mine.results);
  await db.batch([
    db.prepare(
      `UPDATE posts SET comment_count = MAX(comment_count - (SELECT COUNT(*) FROM comments c WHERE c.post_id = posts.id AND c.user_id = ?1), 0)
       WHERE id IN (SELECT post_id FROM comments WHERE user_id = ?1)`,
    ).bind(user.id),
    db.prepare(`DELETE FROM reports WHERE target_type = 'comment' AND target_id IN (SELECT id FROM comments WHERE user_id = ?1)`).bind(user.id),
    db.prepare(`DELETE FROM comments WHERE user_id = ?1`).bind(user.id),
    db.prepare(`UPDATE posts SET like_count = MAX(like_count - 1, 0) WHERE id IN (SELECT post_id FROM likes WHERE user_id = ?1 AND active = 1)`).bind(user.id),
    db.prepare(`DELETE FROM likes WHERE user_id = ?1`).bind(user.id),
    db.prepare(`DELETE FROM comment_extends WHERE user_id = ?1`).bind(user.id),
    db.prepare(`DELETE FROM reports WHERE reporter_id = ?1`).bind(user.id),
    db.prepare(`DELETE FROM users WHERE id = ?1`).bind(user.id),
  ]);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- 投稿

app.get('/status', async (c) => {
  const now = Date.now();
  const r = await c.env.DB.prepare(`SELECT COUNT(*) AS n FROM posts WHERE expires_at > ?1`).bind(now).first<{ n: number }>();
  const activeCount = r?.n ?? 0;
  return c.json({
    activeCount,
    limit: LIMIT_GLOBAL,
    userLimit: LIMIT_USER,
    nextFreeAt: activeCount >= LIMIT_GLOBAL ? await nextFreeAt(c.env.DB, now) : null,
  });
});

app.get('/posts', async (c) => {
  const uid = c.get('uid');
  const now = Date.now();
  const rows = await c.env.DB.prepare(
    `${POST_SELECT}
     WHERE p.status = 'active' AND p.expires_at > ?1
       AND NOT EXISTS (SELECT 1 FROM reports r WHERE r.target_type = 'post' AND r.target_id = p.id AND r.reporter_id = ?2)
     ORDER BY p.created_at DESC LIMIT ${LIMIT_GLOBAL}`,
  )
    .bind(now, uid ?? '')
    .all<PostRow>();
  return c.json({ posts: rows.results.map((p) => postJson(p, uid, false)), serverTime: now });
});

app.get('/posts/mine', async (c) => {
  const user = await requireUser(c, { allowBanned: true });
  const now = Date.now();
  const rows = await c.env.DB.prepare(`${POST_SELECT} WHERE p.user_id = ?2 AND p.expires_at > ?1 ORDER BY p.created_at DESC`)
    .bind(now, user.id)
    .all<PostRow>();
  return c.json({ posts: rows.results.map((p) => postJson(p, user.id, true)), serverTime: now });
});

app.get('/posts/:id', async (c) => {
  const uid = c.get('uid');
  const now = Date.now();
  const p = await c.env.DB.prepare(`${POST_SELECT} WHERE p.id = ?3 AND p.expires_at > ?1`).bind(now, uid ?? '', c.req.param('id')).first<PostRow>();
  if (!p || (p.status !== 'active' && p.user_id !== uid)) throw new ApiError(404, 'POST_GONE', 'この投稿は公開終了しました');
  return c.json({ post: postJson(p, uid, true), serverTime: now });
});

app.post('/posts', async (c) => {
  const user = await requireUser(c);
  const input = await readPostForm(c);
  if (input.images.length > MAX_IMAGES) throw new ApiError(400, 'VALIDATION', '画像は 3 枚までです', { field: 'images' });
  const env = c.env;
  const now = Date.now();
  const id = newId();
  const keys = await putImages(env, id, input.images);

  // 件数チェックと INSERT を 1 文で行い、同時投稿でも上限を超えない（7.2）
  const res = await env.DB.prepare(
    `INSERT INTO posts (id, user_id, title, body_md, tags_json, images_json, created_at, updated_at, edited, expires_at)
     SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7, 0, ?8
     WHERE (SELECT COUNT(*) FROM posts WHERE expires_at > ?7) < ${LIMIT_GLOBAL}
       AND (SELECT COUNT(*) FROM posts WHERE user_id = ?2 AND expires_at > ?7) < ${LIMIT_USER}`,
  )
    .bind(id, user.id, input.title, input.body, JSON.stringify(input.tags), JSON.stringify(keys), now, now + POST_TTL)
    .run();

  if (!res.meta.changes) {
    if (keys.length) await env.IMAGES.delete(keys);
    const mine = await env.DB.prepare(`SELECT COUNT(*) AS n FROM posts WHERE user_id = ?1 AND expires_at > ?2`).bind(user.id, now).first<{ n: number }>();
    if ((mine?.n ?? 0) >= LIMIT_USER) {
      throw new ApiError(409, 'POST_LIMIT_USER', '公開中の投稿が5件あります', { nextFreeAt: await nextFreeAt(env.DB, now, user.id) });
    }
    throw new ApiError(409, 'POST_LIMIT_GLOBAL', '現在満員です', { nextFreeAt: await nextFreeAt(env.DB, now) });
  }
  const p = await env.DB.prepare(`${POST_SELECT} WHERE p.id = ?1`).bind(id, user.id).first<PostRow>();
  return c.json({ post: postJson(p!, user.id, true) }, 201);
});

app.patch('/posts/:id', async (c) => {
  const user = await requireUser(c);
  const env = c.env;
  const now = Date.now();
  const id = c.req.param('id');
  const p = await env.DB.prepare(`SELECT * FROM posts WHERE id = ?1 AND expires_at > ?2`).bind(id, now).first<PostRow>();
  if (!p) throw new ApiError(404, 'POST_GONE', 'この投稿は公開終了しました');
  if (p.user_id !== user.id) throw new ApiError(403, 'FORBIDDEN', '自分の投稿だけ編集できます');

  const input = await readPostForm(c);
  const existing = JSON.parse(p.images_json) as string[];
  const keep = input.keepImages.filter((k) => existing.includes(k));
  if (keep.length + input.images.length > MAX_IMAGES) throw new ApiError(400, 'VALIDATION', '画像は 3 枚までです', { field: 'images' });
  const added = await putImages(env, id, input.images);
  const removed = existing.filter((k) => !keep.includes(k));
  if (removed.length) await env.IMAGES.delete(removed);

  // 期限は変えない。edited=1
  await env.DB.prepare(
    `UPDATE posts SET title = ?1, body_md = ?2, tags_json = ?3, images_json = ?4, updated_at = ?5, edited = 1 WHERE id = ?6`,
  )
    .bind(input.title, input.body, JSON.stringify(input.tags), JSON.stringify([...keep, ...added]), now, id)
    .run();
  const updated = await env.DB.prepare(`${POST_SELECT} WHERE p.id = ?1`).bind(id, user.id).first<PostRow>();
  return c.json({ post: postJson(updated!, user.id, true) });
});

app.delete('/posts/:id', async (c) => {
  const user = await requireUser(c, { allowBanned: true });
  const p = await c.env.DB.prepare(`SELECT id, user_id, images_json FROM posts WHERE id = ?1`).bind(c.req.param('id')).first<PostRow>();
  if (!p) throw new ApiError(404, 'POST_GONE', 'この投稿は公開終了しました');
  if (p.user_id !== user.id) throw new ApiError(403, 'FORBIDDEN', '自分の投稿だけ削除できます');
  await purgePosts(c.env, [p]);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- いいね（7.5）

app.post('/posts/:id/like', async (c) => {
  const user = await requireUser(c);
  const db = c.env.DB;
  const now = Date.now();
  const p = await getLivePost(c, c.req.param('id'), now);
  if (p.user_id === user.id) throw new ApiError(400, 'SELF_LIKE', '自分の投稿にはいいねできません');

  const row = await db.prepare(`SELECT active FROM likes WHERE post_id = ?1 AND user_id = ?2`).bind(p.id, user.id).first<{ active: number }>();
  if (!row) {
    // 初回のみ延長（行を追加できたときだけ。同時押しで二重に数えない）
    const ins = await db.prepare(`INSERT OR IGNORE INTO likes (post_id, user_id, active, created_at) VALUES (?1, ?2, 1, ?3)`)
      .bind(p.id, user.id, now)
      .run();
    if (ins.meta.changes) {
      await db.prepare(`UPDATE posts SET like_count = like_count + 1, ${EXTEND_SQL} WHERE id = ?2`).bind(now, p.id).run();
    }
  } else if (row.active === 0) {
    // 再いいね：数は戻すが延長しない
    await db.batch([
      db.prepare(`UPDATE likes SET active = 1 WHERE post_id = ?1 AND user_id = ?2`).bind(p.id, user.id),
      db.prepare(`UPDATE posts SET like_count = like_count + 1 WHERE id = ?1`).bind(p.id),
    ]);
  }
  const after = await db.prepare(`SELECT like_count, expires_at FROM posts WHERE id = ?1`).bind(p.id).first<PostRow>();
  return c.json({ liked: true, likeCount: after!.like_count, expiresAt: after!.expires_at });
});

app.delete('/posts/:id/like', async (c) => {
  const user = await requireUser(c);
  const db = c.env.DB;
  const now = Date.now();
  const p = await getLivePost(c, c.req.param('id'), now);
  const res = await db.prepare(`UPDATE likes SET active = 0 WHERE post_id = ?1 AND user_id = ?2 AND active = 1`).bind(p.id, user.id).run();
  if (res.meta.changes) {
    await db.prepare(`UPDATE posts SET like_count = MAX(like_count - 1, 0) WHERE id = ?1`).bind(p.id).run();
  }
  const after = await db.prepare(`SELECT like_count, expires_at FROM posts WHERE id = ?1`).bind(p.id).first<PostRow>();
  return c.json({ liked: false, likeCount: after!.like_count, expiresAt: after!.expires_at });
});

// ---------------------------------------------------------------- コメント（2.14）

app.get('/posts/:id/comments', async (c) => {
  const uid = c.get('uid');
  const now = Date.now();
  const p = await getLivePost(c, c.req.param('id'), now);
  const rows = await c.env.DB.prepare(
    `SELECT c.*, u.nickname FROM comments c LEFT JOIN users u ON u.id = c.user_id
     WHERE c.post_id = ?1 AND c.status = 'active'
       AND NOT EXISTS (SELECT 1 FROM reports r WHERE r.target_type = 'comment' AND r.target_id = c.id AND r.reporter_id = ?2)
     ORDER BY c.created_at ASC`,
  )
    .bind(p.id, uid ?? '')
    .all<{ id: string; user_id: string; body: string; created_at: number; nickname: string | null }>();
  return c.json({
    comments: rows.results.map((r) => ({
      id: r.id,
      body: r.body,
      createdAt: r.created_at,
      author: { nickname: r.nickname ?? '退会したユーザー' },
      isMine: uid !== null && r.user_id === uid,
      canDelete: uid !== null && (r.user_id === uid || p.user_id === uid),
    })),
    commentCount: p.comment_count,
    limit: LIMIT_COMMENTS,
  });
});

app.post('/posts/:id/comments', async (c) => {
  const user = await requireUser(c);
  const db = c.env.DB;
  const now = Date.now();
  const p = await getLivePost(c, c.req.param('id'), now);
  const body = str((await readJson(c)).body, 'body', 1, 200);
  const id = newId();
  const res = await db.prepare(
    `INSERT INTO comments (id, post_id, user_id, body, created_at)
     SELECT ?1, ?2, ?3, ?4, ?5 WHERE (SELECT COUNT(*) FROM comments WHERE post_id = ?2) < ${LIMIT_COMMENTS}`,
  )
    .bind(id, p.id, user.id, body, now)
    .run();
  if (!res.meta.changes) throw new ApiError(409, 'COMMENT_LIMIT', 'この投稿はコメント上限に達しました');

  const stmts = [db.prepare(`UPDATE posts SET comment_count = comment_count + 1 WHERE id = ?1`).bind(p.id)];
  if (p.user_id !== user.id) {
    // 1人1投稿につき初回コメントのみ延長。自分の投稿へのコメントは延長しない
    const ext = await db.prepare(`INSERT OR IGNORE INTO comment_extends (post_id, user_id) VALUES (?1, ?2)`).bind(p.id, user.id).run();
    if (ext.meta.changes) stmts.push(db.prepare(`UPDATE posts SET ${EXTEND_SQL} WHERE id = ?2`).bind(now, p.id));
  }
  await db.batch(stmts);
  const after = await db.prepare(`SELECT comment_count, expires_at FROM posts WHERE id = ?1`).bind(p.id).first<PostRow>();
  return c.json(
    {
      comment: { id, body, createdAt: now, author: { nickname: user.nickname }, isMine: true, canDelete: true },
      commentCount: after!.comment_count,
      expiresAt: after!.expires_at,
    },
    201,
  );
});

app.delete('/comments/:id', async (c) => {
  const user = await requireUser(c, { allowBanned: true });
  const row = await c.env.DB.prepare(
    `SELECT c.id, c.post_id, c.user_id, p.user_id AS owner FROM comments c JOIN posts p ON p.id = c.post_id WHERE c.id = ?1`,
  )
    .bind(c.req.param('id'))
    .first<{ id: string; post_id: string; user_id: string; owner: string }>();
  if (!row) throw new ApiError(404, 'NOT_FOUND', 'コメントが見つかりません');
  if (row.user_id !== user.id && row.owner !== user.id) throw new ApiError(403, 'FORBIDDEN', 'このコメントは削除できません');
  await deleteComment(c.env, row.id, row.post_id);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- 通報（7.6）

const REPORT_REASONS = ['spam', 'abuse', 'sexual', 'illegal', 'other'];

app.post('/reports', async (c) => {
  const user = await requireUser(c);
  const db = c.env.DB;
  const body = await readJson(c);
  const targetType = body.targetType;
  const targetId = str(body.targetId, 'targetId', 1, 64);
  const reason = body.reason;
  if (targetType !== 'post' && targetType !== 'comment') throw new ApiError(400, 'VALIDATION', 'targetType が不正です');
  if (typeof reason !== 'string' || !REPORT_REASONS.includes(reason)) throw new ApiError(400, 'VALIDATION', 'reason が不正です');

  const table = targetType === 'post' ? 'posts' : 'comments';
  const target = await db.prepare(`SELECT id, ${targetType === 'post' ? 'id' : 'post_id'} AS post_id FROM ${table} WHERE id = ?1`)
    .bind(targetId)
    .first<{ id: string; post_id: string }>();
  if (!target) throw new ApiError(404, 'NOT_FOUND', '対象が見つかりません');

  const res = await db.prepare(
    `INSERT OR IGNORE INTO reports (id, target_type, target_id, post_id, reporter_id, reason, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
  )
    .bind(newId(), targetType, targetId, target.post_id, user.id, reason, Date.now())
    .run();
  if (res.meta.changes) {
    await db.prepare(
      `UPDATE ${table} SET report_count = report_count + 1,
         status = CASE WHEN report_count + 1 >= ${REPORT_HIDE_THRESHOLD} THEN 'hidden' ELSE status END
       WHERE id = ?1`,
    )
      .bind(targetId)
      .run();
  }
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- 画像（7.8）

app.get('/images/*', async (c) => {
  const key = decodeURIComponent(c.req.path.replace(/^\/images\//, ''));
  const m = /^posts\/([0-9a-f-]{36})\/[0-9a-f-]{36}\.(jpg|webp)$/.exec(key);
  if (!m) throw new ApiError(404, 'NOT_FOUND', 'Not Found');
  const live = await c.env.DB.prepare(`SELECT images_json FROM posts WHERE id = ?1 AND expires_at > ?2 AND status = 'active'`)
    .bind(m[1], Date.now())
    .first<{ images_json: string }>();
  if (!live || !(JSON.parse(live.images_json) as string[]).includes(key)) throw new ApiError(404, 'POST_GONE', '公開終了しました');
  const obj = await c.env.IMAGES.get(key);
  if (!obj) throw new ApiError(404, 'NOT_FOUND', 'Not Found');
  return new Response(obj.body, {
    headers: {
      'Content-Type': obj.httpMetadata?.contentType ?? 'application/octet-stream',
      'Cache-Control': 'private, max-age=3600',
      ETag: obj.httpEtag,
    },
  });
});

// ---------------------------------------------------------------- 管理（7.9）

/** Cloudflare Access の JWT を必ず検証する。未設定なら常に 403（fail closed） */
app.use('/admin/*', async (c, next) => {
  const ok = await verifyAccessJwt(c.req.header('Cf-Access-Jwt-Assertion'), c.env.ACCESS_TEAM_DOMAIN, c.env.ACCESS_AUD);
  if (!ok) return c.text('Forbidden', 403);
  await next();
});
app.use('/admin', async (c, next) => {
  const ok = await verifyAccessJwt(c.req.header('Cf-Access-Jwt-Assertion'), c.env.ACCESS_TEAM_DOMAIN, c.env.ACCESS_AUD);
  if (!ok) return c.text('Forbidden', 403);
  await next();
});

app.get('/admin', (c) => c.html(ADMIN_HTML));

app.get('/admin/api/reports', async (c) => {
  const db = c.env.DB;
  const posts = await db.prepare(
    `SELECT p.id, p.user_id, p.title, substr(p.body_md, 1, 300) AS body, p.status, p.report_count, p.expires_at, p.created_at,
       u.nickname, (b.sub_hash IS NOT NULL) AS banned,
       (SELECT group_concat(reason) FROM reports r WHERE r.target_type = 'post' AND r.target_id = p.id) AS reasons
     FROM posts p LEFT JOIN users u ON u.id = p.user_id LEFT JOIN bans b ON b.sub_hash = u.sub_hash
     WHERE p.report_count > 0 OR p.status <> 'active' ORDER BY p.report_count DESC, p.created_at DESC LIMIT 200`,
  ).all();
  const comments = await db.prepare(
    `SELECT c.id, c.post_id, c.user_id, c.body, c.status, c.report_count, c.created_at,
       u.nickname, (b.sub_hash IS NOT NULL) AS banned,
       (SELECT group_concat(reason) FROM reports r WHERE r.target_type = 'comment' AND r.target_id = c.id) AS reasons
     FROM comments c LEFT JOIN users u ON u.id = c.user_id LEFT JOIN bans b ON b.sub_hash = u.sub_hash
     WHERE c.report_count > 0 OR c.status <> 'active' ORDER BY c.report_count DESC, c.created_at DESC LIMIT 200`,
  ).all();
  const bans = await db.prepare(`SELECT sub_hash, reason, created_at FROM bans ORDER BY created_at DESC LIMIT 200`).all();
  return c.json({ posts: posts.results, comments: comments.results, bans: bans.results });
});

app.post('/admin/api/:type/:id/:action', async (c) => {
  const { type, id, action } = c.req.param();
  const env = c.env;
  const db = env.DB;
  if (type === 'posts' || type === 'comments') {
    const target = type === 'posts' ? 'post' : 'comment';
    if (action === 'hide') {
      await db.prepare(`UPDATE ${type} SET status = 'hidden' WHERE id = ?1`).bind(id).run();
    } else if (action === 'restore') {
      await db.batch([
        db.prepare(`UPDATE ${type} SET status = 'active', report_count = 0 WHERE id = ?1`).bind(id),
        db.prepare(`DELETE FROM reports WHERE target_type = ?1 AND target_id = ?2`).bind(target, id),
      ]);
    } else if (action === 'delete') {
      if (type === 'posts') {
        const p = await db.prepare(`SELECT id, images_json FROM posts WHERE id = ?1`).bind(id).first<{ id: string; images_json: string }>();
        if (p) await purgePosts(env, [p]);
      } else {
        const cm = await db.prepare(`SELECT id, post_id FROM comments WHERE id = ?1`).bind(id).first<{ id: string; post_id: string }>();
        if (cm) await deleteComment(env, cm.id, cm.post_id);
      }
    } else {
      throw new ApiError(400, 'VALIDATION', 'unknown action');
    }
    return c.json({ ok: true });
  }
  if (type === 'users' && (action === 'ban' || action === 'unban')) {
    const u = await db.prepare(`SELECT sub_hash FROM users WHERE id = ?1`).bind(id).first<{ sub_hash: string }>();
    if (!u) throw new ApiError(404, 'NOT_FOUND', 'ユーザーが見つかりません');
    if (action === 'ban') {
      const reason = (await readJson(c)).reason;
      await db.prepare(`INSERT OR REPLACE INTO bans (sub_hash, reason, created_at) VALUES (?1, ?2, ?3)`)
        .bind(u.sub_hash, typeof reason === 'string' ? reason.slice(0, 200) : null, Date.now())
        .run();
    } else {
      await db.prepare(`DELETE FROM bans WHERE sub_hash = ?1`).bind(u.sub_hash).run();
    }
    return c.json({ ok: true });
  }
  if (type === 'bans' && action === 'unban') {
    await db.prepare(`DELETE FROM bans WHERE sub_hash = ?1`).bind(id).run();
    return c.json({ ok: true });
  }
  throw new ApiError(400, 'VALIDATION', 'unknown action');
});

// ---------------------------------------------------------------- Cron（7.7）

async function hourly(env: Env): Promise<void> {
  const now = Date.now();
  const expired = await env.DB.prepare(`SELECT id, images_json FROM posts WHERE expires_at <= ?1 LIMIT 500`)
    .bind(now)
    .all<{ id: string; images_json: string }>();
  await purgePosts(env, expired.results);
  await env.DB.prepare(`DELETE FROM signup_ip_counts WHERE day < ?1`).bind(utcDay(now)).run();
  console.log(JSON.stringify({ level: 'info', event: 'cron.hourly', purgedPosts: expired.results.length }));
}

export default {
  fetch: app.fetch,
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(hourly(env));
  },
} satisfies ExportedHandler<Env>;

export { app };
