import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';
import { HTTPException } from 'hono/http-exception';
import type { ContentfulStatusCode } from 'hono/utils/http-status';

export const HOUR = 60 * 60 * 1000;
export const DAY = 24 * HOUR;
export const POST_TTL = DAY;
export const POST_MAX_LIFE = 7 * DAY;
export const LIMIT_GLOBAL = 100;
export const LIMIT_USER = 5;
export const LIMIT_COMMENTS = 50;
export const REPORT_HIDE_THRESHOLD = 3;
export const SIGNUP_PER_IP_PER_DAY = 3;
export const SESSION_DAYS = 30;
export const MAX_IMAGES = 3;
export const MAX_IMAGE_BYTES = 500 * 1024;
export const IMAGE_TYPES: Record<string, string> = { 'image/jpeg': 'jpg', 'image/webp': 'webp' };

export type ErrorCode =
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'POST_LIMIT_USER'
  | 'POST_LIMIT_GLOBAL'
  | 'COMMENT_LIMIT'
  | 'SELF_LIKE'
  | 'POST_GONE'
  | 'BANNED'
  | 'SIGNUP_LIMIT'
  | 'VALIDATION';

/** API エラー。`{ error: { code, message, ...extra } }` の形で返す */
export class ApiError extends HTTPException {
  constructor(
    status: ContentfulStatusCode,
    readonly code: ErrorCode,
    message: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(status, { message });
  }
}

export const newId = () => crypto.randomUUID();

const enc = new TextEncoder();

export async function hmacHex(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(data));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** 公開期限の延長（doc/design.md 2.13）: max(current, min(now+24h, created+7d)) */
export function extendExpiry(createdAt: number, currentExpiresAt: number, now: number): number {
  return Math.max(currentExpiresAt, Math.min(now + DAY, createdAt + POST_MAX_LIFE));
}

/** SQL 版の延長式。?1 = now */
export const EXTEND_SQL = `expires_at = MAX(expires_at, MIN(?1 + ${DAY}, created_at + ${POST_MAX_LIFE}))`;

// ---- セッション JWT（HS256, 30日） ----

export async function signSession(secret: string, uid: string): Promise<string> {
  return new SignJWT({ uid })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${SESSION_DAYS}d`)
    .sign(enc.encode(secret));
}

export async function verifySession(secret: string, token: string): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, enc.encode(secret), { algorithms: ['HS256'] });
    return typeof payload.uid === 'string' ? payload.uid : null;
  } catch {
    return null;
  }
}

// ---- Google ID トークン ----

const googleJwks = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));

/**
 * Google の ID トークンを検証し、sub だけを返す。
 * email / name / picture は読まない・保存しない・ログに出さない（doc/design.md 7.3）。
 */
export async function verifyGoogleIdToken(idToken: string, clientId: string): Promise<string> {
  try {
    const { payload } = await jwtVerify(idToken, googleJwks, {
      issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: clientId,
    });
    if (typeof payload.sub !== 'string' || !payload.sub) throw new Error('no sub');
    return payload.sub;
  } catch {
    throw new ApiError(401, 'UNAUTHORIZED', 'Google の認証に失敗しました');
  }
}

// ---- Cloudflare Access（/admin） ----

const accessJwksCache = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

export async function verifyAccessJwt(token: string | undefined, teamDomain: string, aud: string): Promise<boolean> {
  if (!token || !teamDomain || !aud) return false;
  const issuer = `https://${teamDomain.replace(/^https?:\/\//, '').replace(/\/$/, '')}`;
  let jwks = accessJwksCache.get(issuer);
  if (!jwks) {
    jwks = createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`));
    accessJwksCache.set(issuer, jwks);
  }
  try {
    await jwtVerify(token, jwks, { issuer, audience: aud });
    return true;
  } catch {
    return false;
  }
}

// ---- 入力検証 ----

export function str(v: unknown, field: string, min: number, max: number): string {
  if (typeof v !== 'string') throw new ApiError(400, 'VALIDATION', `${field} が不正です`, { field });
  const s = v.trim();
  const len = [...s].length;
  if (len < min || len > max) {
    throw new ApiError(400, 'VALIDATION', `${field} は ${min}〜${max} 文字で入力してください`, { field });
  }
  return s;
}

export function tagList(v: unknown): string[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) throw new ApiError(400, 'VALIDATION', 'tags が不正です', { field: 'tags' });
  const tags = [...new Set(v.map((t) => str(t, 'tags', 1, 30)))];
  if (tags.length > 5) throw new ApiError(400, 'VALIDATION', 'タグは 5 個までです', { field: 'tags' });
  return tags;
}

export function excerpt(md: string, n = 200): string {
  const plain = md
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[#>*_`~-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return [...plain].slice(0, n).join('');
}

export function randomNickname(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 10000;
  return `ユーザー${String(n).padStart(4, '0')}`;
}

export function utcDay(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}
