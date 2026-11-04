// ローカルの `wrangler dev --test-scheduled` に対して API の仕様を確認する E2E テスト。
// 使い方: (server/ で) wrangler d1 migrations apply techmeku-db --local && wrangler dev --test-scheduled
//         別ターミナルで node test/e2e.mjs
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { SignJWT } from 'jose';

const BASE = process.env.BASE ?? 'http://localhost:8787';
const DAY = 86400000;
const vars = Object.fromEntries(
  readFileSync(new URL('../.dev.vars', import.meta.url), 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((l) => l.split('=')),
);

function sql(command) {
  const out = execFileSync('wrangler', ['d1', 'execute', 'techmeku-db', '--local', '--json', '--command', command], {
    cwd: new URL('..', import.meta.url),
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  return JSON.parse(out)[0].results;
}

async function token(uid) {
  return new SignJWT({ uid }).setProtectedHeader({ alg: 'HS256' }).setIssuedAt().setExpirationTime('1d').sign(new TextEncoder().encode(vars.SESSION_SECRET));
}

async function call(method, path, { as, json, form } = {}) {
  const headers = {};
  if (as) headers.Authorization = `Bearer ${await token(as)}`;
  let body;
  if (json) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(json);
  } else if (form) body = form;
  const r = await fetch(BASE + path, { method, headers, body });
  const ct = r.headers.get('content-type') ?? '';
  return { status: r.status, body: ct.includes('json') ? await r.json() : await r.text(), headers: r.headers };
}

// 1x1 の JPEG
const JPEG = Buffer.from(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
  'base64',
);

function postForm(title, body, { images = 0, keep } = {}) {
  const f = new FormData();
  f.set('data', JSON.stringify({ title, body, tags: ['Flutter'], ...(keep ? { keepImages: keep } : {}) }));
  for (let i = 0; i < images; i++) f.append('images', new Blob([JPEG], { type: 'image/jpeg' }), `${i}.jpg`);
  return f;
}

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

// ---- 準備：DB を空にしてテストユーザーを作る
sql(`DELETE FROM posts; DELETE FROM likes; DELETE FROM comments; DELETE FROM comment_extends; DELETE FROM reports; DELETE FROM users; DELETE FROM bans; DELETE FROM signup_ip_counts;`);
const U = ['A', 'B', 'C', 'D', 'E'];
const now0 = Date.now();
sql(U.map((u) => `INSERT INTO users (id, sub_hash, nickname, created_at) VALUES ('u${u}', 'h${u}', 'user${u}', ${now0})`).join(';'));
const [A, B, C, D, E] = U.map((u) => `u${u}`);

console.log('TechMeku API E2E');

await test('ヘルスチェック・未認証の書き込みは 401', async () => {
  assert.equal((await call('GET', '/')).body.ok, true);
  assert.equal((await call('POST', '/posts', { form: postForm('t', 'b') })).status, 401);
});

let p1;
await test('投稿の作成（画像付き）と画像配信', async () => {
  const r = await call('POST', '/posts', { as: A, form: postForm('はじめての投稿', '本文です ![](attachment:1)', { images: 2 }) });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  p1 = r.body.post;
  assert.equal(p1.images.length, 2);
  assert.ok(Math.abs(p1.expiresAt - (p1.createdAt + DAY)) < 5);
  const img = await fetch(`${BASE}/images/${p1.images[0]}`);
  assert.equal(img.status, 200);
  assert.equal(img.headers.get('content-type'), 'image/jpeg');
});

await test('入力検証：タイトル 101 字・画像 4 枚・PNG は 400', async () => {
  assert.equal((await call('POST', '/posts', { as: A, form: postForm('x'.repeat(101), 'b') })).body.error.code, 'VALIDATION');
  assert.equal((await call('POST', '/posts', { as: A, form: postForm('t', 'b', { images: 4 }) })).body.error.code, 'VALIDATION');
  const f = postForm('t', 'b');
  f.append('images', new Blob([JPEG], { type: 'image/png' }), 'x.png');
  assert.equal((await call('POST', '/posts', { as: A, form: f })).status, 400);
});

await test('1人 5 件まで。6 件目は POST_LIMIT_USER と nextFreeAt', async () => {
  for (let i = 2; i <= 5; i++) assert.equal((await call('POST', '/posts', { as: A, form: postForm(`投稿${i}`, 'b') })).status, 201);
  const r = await call('POST', '/posts', { as: A, form: postForm('6件目', 'b') });
  assert.equal(r.status, 409);
  assert.equal(r.body.error.code, 'POST_LIMIT_USER');
  assert.ok(r.body.error.nextFreeAt > Date.now());
  assert.equal((await call('GET', '/me', { as: A })).body.activePostCount, 5);
});

await test('自分の投稿にはいいねできない（SELF_LIKE）', async () => {
  assert.equal((await call('POST', `/posts/${p1.id}/like`, { as: A })).body.error.code, 'SELF_LIKE');
});

await test('いいねで延長。上限は投稿から 7 日', async () => {
  const t = Date.now();
  sql(`UPDATE posts SET created_at = ${t - 6 * DAY - 23 * 3600000}, expires_at = ${t + 3600000} WHERE id = '${p1.id}'`);
  const r = await call('POST', `/posts/${p1.id}/like`, { as: B });
  assert.equal(r.body.likeCount, 1);
  assert.equal(r.body.expiresAt, t - 6 * DAY - 23 * 3600000 + 7 * DAY);
});

await test('取り消しで延長は戻らず、再いいねでは再延長しない', async () => {
  const t = Date.now();
  sql(`UPDATE posts SET created_at = ${t}, expires_at = ${t + 3600000} WHERE id = '${p1.id}'`);
  const un = await call('DELETE', `/posts/${p1.id}/like`, { as: B });
  assert.equal(un.body.likeCount, 0);
  assert.equal(un.body.expiresAt, t + 3600000);
  const re = await call('POST', `/posts/${p1.id}/like`, { as: B });
  assert.equal(re.body.likeCount, 1);
  assert.equal(re.body.expiresAt, t + 3600000);
  const c1 = await call('POST', `/posts/${p1.id}/like`, { as: C });
  assert.equal(c1.body.likeCount, 2);
  assert.ok(c1.body.expiresAt >= t + DAY - 5000);
});

await test('一覧に likedByMe・isMine が付く', async () => {
  const r = await call('GET', '/posts', { as: B });
  const p = r.body.posts.find((x) => x.id === p1.id);
  assert.equal(p.likedByMe, true);
  assert.equal(p.isMine, false);
  assert.equal(p.body, undefined);
  assert.equal((await call('GET', `/posts/${p1.id}`, { as: A })).body.post.isMine, true);
});

let cB;
await test('コメント：初回だけ延長。2 回目・自分の投稿へのコメントは延長しない', async () => {
  const t = Date.now();
  sql(`UPDATE posts SET expires_at = ${t + 3600000} WHERE id = '${p1.id}'`);
  const r1 = await call('POST', `/posts/${p1.id}/comments`, { as: B, json: { body: 'いい記事' } });
  assert.equal(r1.status, 201);
  cB = r1.body.comment.id;
  assert.ok(r1.body.expiresAt >= t + DAY - 5000);
  sql(`UPDATE posts SET expires_at = ${t + 3600000} WHERE id = '${p1.id}'`);
  const r2 = await call('POST', `/posts/${p1.id}/comments`, { as: B, json: { body: '2回目' } });
  assert.equal(r2.body.expiresAt, t + 3600000);
  const r3 = await call('POST', `/posts/${p1.id}/comments`, { as: A, json: { body: '投稿者です' } });
  assert.equal(r3.body.expiresAt, t + 3600000);
  assert.equal(r3.body.commentCount, 3);
  assert.equal((await call('POST', `/posts/${p1.id}/comments`, { as: B, json: { body: 'x'.repeat(201) } })).status, 400);
});

await test('コメント削除：投稿者は可、第三者は 403', async () => {
  assert.equal((await call('DELETE', `/comments/${cB}`, { as: C })).status, 403);
  assert.equal((await call('DELETE', `/comments/${cB}`, { as: A })).status, 200);
  const list = await call('GET', `/posts/${p1.id}/comments`, { as: A });
  assert.equal(list.body.comments.length, 2);
  assert.equal(list.body.commentCount, 2);
});

await test('コメントは 50 件まで（COMMENT_LIMIT）', async () => {
  const t = Date.now();
  sql(`INSERT INTO comments (id, post_id, user_id, body, created_at) SELECT 'bulk' || value, '${p1.id}', '${C}', 'x', ${t} FROM json_each('[${Array.from({ length: 48 }, (_, i) => i).join(',')}]')`);
  assert.equal((await call('POST', `/posts/${p1.id}/comments`, { as: D, json: { body: '51件目' } })).body.error.code, 'COMMENT_LIMIT');
  sql(`DELETE FROM comments WHERE id LIKE 'bulk%'`);
});

await test('通報：本人には即非表示、3 人で全体から非表示', async () => {
  const posts = (await call('GET', '/posts', { as: B })).body.posts;
  const target = posts.find((x) => x.id !== p1.id).id;
  for (const who of [B, C]) assert.equal((await call('POST', '/reports', { as: who, json: { targetType: 'post', targetId: target, reason: 'spam' } })).status, 200);
  // 同じ人の再通報は数えない
  await call('POST', '/reports', { as: B, json: { targetType: 'post', targetId: target, reason: 'spam' } });
  assert.ok(!(await call('GET', '/posts', { as: B })).body.posts.some((x) => x.id === target));
  assert.ok((await call('GET', '/posts', { as: E })).body.posts.some((x) => x.id === target));
  await call('POST', '/reports', { as: D, json: { targetType: 'post', targetId: target, reason: 'abuse' } });
  assert.ok(!(await call('GET', '/posts', { as: E })).body.posts.some((x) => x.id === target));
  assert.equal((await call('GET', `/posts/${target}`, { as: E })).body.error.code, 'POST_GONE');
  assert.equal((await call('GET', `/posts/${target}`, { as: A })).body.post.hidden, true);
  assert.equal((await call('POST', '/reports', { as: B, json: { targetType: 'post', targetId: target, reason: 'bad' } })).status, 400);
});

await test('全体 100 件で POST_LIMIT_GLOBAL', async () => {
  const t = Date.now();
  sql(`INSERT INTO posts (id, user_id, title, body_md, tags_json, images_json, created_at, updated_at, expires_at)
       SELECT 'fill' || value, 'other', 't', 'b', '[]', '[]', ${t}, ${t}, ${t + 7200000} FROM json_each('[${Array.from({ length: 95 }, (_, i) => i).join(',')}]')`);
  const r = await call('POST', '/posts', { as: B, form: postForm('満員', 'b') });
  assert.equal(r.body.error.code, 'POST_LIMIT_GLOBAL');
  assert.ok(r.body.error.nextFreeAt);
  const s = (await call('GET', '/status')).body;
  assert.equal(s.activeCount, 100);
  assert.ok(s.nextFreeAt);
  sql(`DELETE FROM posts WHERE id LIKE 'fill%'`);
});

await test('編集：期限は変わらず edited=1、画像の差し替え', async () => {
  const before = (await call('GET', `/posts/${p1.id}`, { as: A })).body.post;
  const r = await call('PATCH', `/posts/${p1.id}`, { as: A, form: postForm('編集後', '本文2', { images: 1, keep: [before.images[1]] }) });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.post.edited, true);
  assert.equal(r.body.post.expiresAt, before.expiresAt);
  assert.equal(r.body.post.images.length, 2);
  assert.equal(r.body.post.images[0], before.images[1]);
  assert.equal((await fetch(`${BASE}/images/${before.images[0]}`)).status, 404);
  assert.equal((await call('PATCH', `/posts/${p1.id}`, { as: B, form: postForm('x', 'y') })).status, 403);
});

await test('Cron：期限切れを物理削除し、画像も消える', async () => {
  const post = (await call('GET', `/posts/${p1.id}`, { as: A })).body.post;
  sql(`UPDATE posts SET expires_at = ${Date.now() - 1000} WHERE id = '${p1.id}'`);
  assert.equal((await call('GET', `/posts/${p1.id}`, { as: A })).body.error.code, 'POST_GONE');
  assert.equal((await fetch(`${BASE}/__scheduled?cron=0+*+*+*+*`)).status, 200);
  await new Promise((r) => setTimeout(r, 500));
  assert.equal(sql(`SELECT COUNT(*) AS n FROM posts WHERE id = '${p1.id}'`)[0].n, 0);
  assert.equal(sql(`SELECT COUNT(*) AS n FROM comments WHERE post_id = '${p1.id}'`)[0].n, 0);
  assert.equal((await fetch(`${BASE}/images/${post.images[0]}`)).status, 404);
});

await test('停止中のアカウントは書き込み不可（BANNED）', async () => {
  sql(`INSERT INTO bans (sub_hash, reason, created_at) VALUES ('hE', 'test', ${Date.now()})`);
  const r = await call('POST', '/posts', { as: E, form: postForm('t', 'b') });
  assert.equal(r.status, 403);
  assert.equal(r.body.error.code, 'BANNED');
  assert.equal((await call('GET', '/me', { as: E })).body.banned, true);
});

await test('退会：投稿・いいね・コメントを削除し、他人の投稿の数も戻す', async () => {
  const pB = (await call('POST', '/posts', { as: B, form: postForm('B の投稿', 'b') })).body.post;
  const pA = (await call('GET', '/posts/mine', { as: A })).body.posts[0];
  await call('POST', `/posts/${pA.id}/like`, { as: C });
  await call('POST', `/posts/${pA.id}/comments`, { as: C, json: { body: 'c' } });
  assert.equal((await call('DELETE', '/me', { as: C })).status, 200);
  const after = (await call('GET', `/posts/${pA.id}`, { as: A })).body.post;
  assert.equal(after.likeCount, pA.likeCount);
  assert.equal(after.commentCount, pA.commentCount);
  assert.equal((await call('GET', '/me', { as: C })).status, 401);
  assert.equal((await call('DELETE', '/me', { as: B })).status, 200);
  assert.equal((await call('GET', `/posts/${pB.id}`)).body.error.code, 'POST_GONE');
});

await test('/admin は Cloudflare Access なしでは 403', async () => {
  assert.equal((await call('GET', '/admin')).status, 403);
  assert.equal((await call('GET', '/admin/api/reports')).status, 403);
  assert.equal((await call('POST', `/admin/api/users/${A}/ban`)).status, 403);
});

await test('Google ID トークンが不正なら 401', async () => {
  assert.equal((await call('POST', '/auth/google', { json: { idToken: 'not-a-token' } })).status, 401);
});

console.log(`\n${passed} passed`);
