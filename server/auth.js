// Sign-in and request security for the action board.
//  - Google sign-in (OpenID Connect, authorization code flow with PKCE), limited to
//    ALLOWED_EMAILS and/or Google Workspace ALLOWED_DOMAINS. Sessions are HMAC-signed,
//    HttpOnly cookies, so the server keeps no session table.
//  - A bearer token (BOARD_INGEST_TOKEN) for machine writes, limited to PUT/PATCH on tasks.
//  - Shared password (HTTP basic auth), kept only for boards that haven't moved to Google yet.
//  - Security headers, a same-origin check on writes, and a failed-auth rate limit.
// No dependencies: node:crypto and the global fetch in Node 22.
'use strict';
const crypto = require('node:crypto');

const env = process.env;
const list = v => String(v || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);

const GOOGLE_CLIENT_ID = env.GOOGLE_CLIENT_ID || '';
const GOOGLE_CLIENT_SECRET = env.GOOGLE_CLIENT_SECRET || '';
const ALLOWED_EMAILS = new Set(list(env.ALLOWED_EMAILS));
const ALLOWED_DOMAINS = new Set(list(env.ALLOWED_DOMAINS));
const PUBLIC_URL = (env.PUBLIC_URL || '').replace(/\/+$/, '');
const SESSION_SECRET = env.SESSION_SECRET || '';
const SESSION_HOURS = Math.min(Math.max(Number(env.SESSION_HOURS) || 12, 1), 24 * 30);
const INGEST_TOKEN = env.BOARD_INGEST_TOKEN || '';
const BOARD_USER = env.BOARD_USER || 'coral';
const BOARD_PASSWORD = env.BOARD_PASSWORD || '';

const GOOGLE = !!GOOGLE_CLIENT_ID;
const MODE = GOOGLE ? 'google' : BOARD_PASSWORD ? 'password' : 'none';
const ORIGIN = PUBLIC_URL ? new URL(PUBLIC_URL).origin : '';
const SECURE = !PUBLIC_URL.startsWith('http://');           // plain http only for local runs
const SESSION_COOKIE = SECURE ? '__Host-board_session' : 'board_session';
const FLOW_COOKIE = SECURE ? '__Host-board_oauth' : 'board_oauth';

// Refuse to start with a configuration that would leave the board open or half-configured.
function checkConfig() {
  const errors = [];
  if (GOOGLE) {
    if (!GOOGLE_CLIENT_SECRET) errors.push('GOOGLE_CLIENT_SECRET is not set');
    if (!PUBLIC_URL) errors.push('PUBLIC_URL is not set (for example https://my-board.fly.dev)');
    if (SESSION_SECRET.length < 32) errors.push('SESSION_SECRET must be at least 32 characters (openssl rand -hex 32)');
    if (!ALLOWED_EMAILS.size && !ALLOWED_DOMAINS.size) errors.push('Set ALLOWED_EMAILS and/or ALLOWED_DOMAINS, or nobody can sign in');
  } else if (MODE === 'none' && env.ALLOW_NO_AUTH !== '1') {
    errors.push('No sign-in is configured. Set GOOGLE_CLIENT_ID (see README), or BOARD_PASSWORD, or ALLOW_NO_AUTH=1 for a local test');
  }
  if (INGEST_TOKEN && INGEST_TOKEN.length < 32) errors.push('BOARD_INGEST_TOKEN must be at least 32 characters (openssl rand -hex 32)');
  if (errors.length) { console.error('Configuration error:\n  ' + errors.join('\n  ')); process.exit(1); }
}

// ---------- small helpers ----------
const b64u = buf => Buffer.from(buf).toString('base64url');
const hmac = s => crypto.createHmac('sha256', SESSION_SECRET).update(s).digest('base64url');
function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}
function seal(obj) { const body = b64u(JSON.stringify(obj)); return `${body}.${hmac(body)}`; }
function unseal(token) {
  const [body, sig, extra] = String(token || '').split('.');
  if (!body || !sig || extra !== undefined || !safeEqual(sig, hmac(body))) return null;
  try { const v = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')); return v && v.exp > Date.now() ? v : null; }
  catch { return null; }
}
function cookies(req) {
  const out = {};
  for (const part of String(req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}
function cookie(name, value, maxAgeSec) {
  return `${name}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAgeSec}${SECURE ? '; Secure' : ''}`;
}
const clientIp = req => String(req.headers['fly-client-ip'] || req.socket.remoteAddress || '');

// ---------- failed-auth rate limit (per IP, in memory) ----------
const FAIL_WINDOW = 10 * 60 * 1000, FAIL_MAX = 30;
const fails = new Map();
function limited(req) {
  const f = fails.get(clientIp(req));
  return !!f && f.until > Date.now() && f.n >= FAIL_MAX;
}
function noteFail(req) {
  const ip = clientIp(req), now = Date.now();
  const f = fails.get(ip);
  if (!f || f.until <= now) fails.set(ip, { n: 1, until: now + FAIL_WINDOW }); else f.n++;
  if (fails.size > 10000) for (const [k, v] of fails) if (v.until <= now) fails.delete(k);
}

// ---------- security headers ----------
function securityHeaders(res, nonce) {
  res.setHeader('Content-Security-Policy', [
    "default-src 'none'",
    `script-src 'self'${nonce ? ` 'nonce-${nonce}'` : ''}`,
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    'font-src https://fonts.gstatic.com',
    "img-src 'self' data:",
    "connect-src 'self'",
    "form-action 'self'",
    "base-uri 'none'",
    "frame-ancestors 'none'",
  ].join('; '));
  if (SECURE) res.setHeader('Strict-Transport-Security', 'max-age=63072000; includeSubDomains');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=()');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
}

// Browsers send Origin on cross-site writes; reject any write that didn't come from this site.
function sameOrigin(req) {
  const origin = req.headers.origin;
  if (origin) {
    if (ORIGIN) return origin === ORIGIN;
    try { return new URL(origin).host === req.headers.host; } catch { return false; }
  }
  const site = req.headers['sec-fetch-site'];
  return !site || site === 'same-origin' || site === 'none';
}

// ---------- who is calling ----------
function allowedAccount(email, hd) {
  email = String(email || '').toLowerCase();
  if (ALLOWED_EMAILS.has(email)) return true;
  // Domains only match Google Workspace accounts (the hd claim), not any Google account
  // that happens to use an address at that domain.
  return !!hd && ALLOWED_DOMAINS.has(String(hd).toLowerCase()) && email.endsWith('@' + String(hd).toLowerCase());
}

// Returns { kind: 'user', email, name } | { kind: 'ingest' } | { kind: 'anonymous' } | null (not signed in)
function identify(req) {
  const authz = String(req.headers.authorization || '');
  const bearer = /^Bearer\s+(\S+)$/i.exec(authz);
  if (bearer) return INGEST_TOKEN && safeEqual(bearer[1], INGEST_TOKEN) ? { kind: 'ingest' } : null;
  if (MODE === 'google') {
    const s = unseal(cookies(req)[SESSION_COOKIE]);
    return s && s.typ === 'session' && allowedAccount(s.email, s.hd) ? { kind: 'user', email: s.email, name: s.name || s.email } : null;
  }
  if (MODE === 'password') {
    const m = /^Basic (.+)$/.exec(authz);
    if (!m) return null;
    const [user, ...rest] = Buffer.from(m[1], 'base64').toString('utf8').split(':');
    return safeEqual(`${user}:${rest.join(':')}`, `${BOARD_USER}:${BOARD_PASSWORD}`) ? { kind: 'user', email: null, name: user } : null;
  }
  return { kind: 'anonymous' };
}

// ---------- Google sign-in ----------
function page(res, status, title, body) {
  securityHeaders(res);
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>:root{color-scheme:light dark}body{font:15px system-ui,-apple-system,"Segoe UI",sans-serif;display:grid;place-items:center;min-height:100vh;margin:0;padding:0 16px;background:Canvas;color:CanvasText}main{max-width:360px;text-align:center}a.btn,button{display:inline-block;padding:10px 18px;border-radius:8px;border:1px solid #8886;background:#4285f4;color:#fff;text-decoration:none;font:inherit;cursor:pointer}p{opacity:.8}</style></head>
<body><main>${body}</main></body></html>`);
}
const redirect = (res, to, extra = {}) => { securityHeaders(res); res.writeHead(302, { Location: to, 'Cache-Control': 'no-store', ...extra }); res.end(); };

function startLogin(req, res) {
  const verifier = b64u(crypto.randomBytes(32));
  const flow = { typ: 'flow', state: b64u(crypto.randomBytes(16)), nonce: b64u(crypto.randomBytes(16)), verifier, exp: Date.now() + 10 * 60 * 1000 };
  const q = new URLSearchParams({
    client_id: GOOGLE_CLIENT_ID,
    redirect_uri: `${PUBLIC_URL}/auth/callback`,
    response_type: 'code',
    scope: 'openid email profile',
    state: flow.state,
    nonce: flow.nonce,
    code_challenge: b64u(crypto.createHash('sha256').update(verifier).digest()),
    code_challenge_method: 'S256',
    prompt: 'select_account',
  });
  if (ALLOWED_DOMAINS.size === 1 && !ALLOWED_EMAILS.size) q.set('hd', [...ALLOWED_DOMAINS][0]);
  redirect(res, `https://accounts.google.com/o/oauth2/v2/auth?${q}`, { 'Set-Cookie': cookie(FLOW_COOKIE, seal(flow), 600) });
}

async function finishLogin(req, res, url) {
  const clearFlow = cookie(FLOW_COOKIE, '', 0);
  const denied = msg => { noteFail(req); res.setHeader('Set-Cookie', clearFlow); page(res, 403, 'Sign-in failed', `<h1>Sign-in failed</h1><p>${msg}</p><p><a class="btn" href="/auth/login">Try again</a></p>`); };
  const flow = unseal(cookies(req)[FLOW_COOKIE]);
  const code = url.searchParams.get('code');
  if (!flow || flow.typ !== 'flow' || !code || !safeEqual(url.searchParams.get('state') || '', flow.state)) return denied('The sign-in link expired or was already used.');
  let tok;
  try {
    const r = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ code, client_id: GOOGLE_CLIENT_ID, client_secret: GOOGLE_CLIENT_SECRET, redirect_uri: `${PUBLIC_URL}/auth/callback`, grant_type: 'authorization_code', code_verifier: flow.verifier }),
      signal: AbortSignal.timeout(10000),
    });
    tok = await r.json();
    if (!r.ok || !tok.id_token) throw new Error(tok.error || r.status);
  } catch (e) { console.error('Google token exchange failed:', e.message); return denied('Google did not confirm the sign-in.'); }
  // The ID token came straight from Google's token endpoint over TLS, so its signature
  // doesn't need checking (OpenID Connect Core 3.1.3.7); the claims still do.
  let c;
  try { c = JSON.parse(Buffer.from(tok.id_token.split('.')[1], 'base64url').toString('utf8')); } catch { return denied('Google sent an unreadable sign-in.'); }
  const now = Date.now() / 1000;
  if (!['https://accounts.google.com', 'accounts.google.com'].includes(c.iss) || c.aud !== GOOGLE_CLIENT_ID || !(c.exp > now) || c.nonce !== flow.nonce) return denied('Google sent a sign-in for a different app.');
  if (c.email_verified !== true || !allowedAccount(c.email, c.hd)) {
    console.warn(`Refused sign-in for ${c.email}`);
    return denied('This Google account is not allowed on this board.');
  }
  const session = { typ: 'session', email: String(c.email).toLowerCase(), hd: c.hd || null, name: c.name || '', iat: Date.now(), exp: Date.now() + SESSION_HOURS * 3600 * 1000 };
  console.log(`Signed in: ${session.email}`);
  redirect(res, '/', { 'Set-Cookie': [clearFlow, cookie(SESSION_COOKIE, seal(session), SESSION_HOURS * 3600)] });
}

// Handles /auth/* routes. Returns true if it answered the request.
async function handleAuthRoute(req, res, url, who) {
  const p = url.pathname;
  if (!p.startsWith('/auth/')) return false;
  if (p === '/auth/me' && req.method === 'GET') {
    securityHeaders(res);
    res.writeHead(who ? 200 : 401, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(who && who.kind === 'user' ? { email: who.email, name: who.name, mode: MODE } : { mode: MODE }));
    return true;
  }
  if (MODE !== 'google') { page(res, 404, 'Not found', '<p>Not found</p>'); return true; }
  if (p === '/auth/login' && req.method === 'GET') { startLogin(req, res); return true; }
  if (p === '/auth/callback' && req.method === 'GET') { await finishLogin(req, res, url); return true; }
  if (p === '/auth/logout' && req.method === 'POST') {
    if (!sameOrigin(req)) { page(res, 403, 'Forbidden', '<p>Forbidden</p>'); return true; }
    redirect(res, '/auth/signed-out', { 'Set-Cookie': cookie(SESSION_COOKIE, '', 0) });
    return true;
  }
  if (p === '/auth/signed-out') { page(res, 200, 'Signed out', '<h1>Signed out</h1><p><a class="btn" href="/auth/login">Sign in with Google</a></p>'); return true; }
  page(res, 404, 'Not found', '<p>Not found</p>');
  return true;
}

// What to send someone who isn't signed in.
function challenge(req, res, url) {
  securityHeaders(res);
  const wantsHtml = req.method === 'GET' && !url.pathname.startsWith('/api/') && url.pathname !== '/runtime.js';
  if (MODE === 'google' && wantsHtml) return redirect(res, '/auth/login');
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
  if (MODE === 'password') headers['WWW-Authenticate'] = 'Basic realm="Action Board", charset="UTF-8"';
  res.writeHead(401, headers);
  res.end(JSON.stringify({ code: 'unauthenticated', message: 'Sign in required' }));
}

module.exports = { MODE, INGEST_TOKEN, checkConfig, securityHeaders, sameOrigin, identify, handleAuthRoute, challenge, limited, noteFail, clientIp };
