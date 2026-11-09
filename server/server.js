// Coral MSP action board server for Fly.io (or any Docker host).
// Serves app/index.html and a small document API that matches the claude.ai
// Artifact db the page was written against, so the page runs unchanged.
// No dependencies: node:http + node:sqlite (Node 22, --experimental-sqlite).
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');
const auth = require('./auth');
auth.checkConfig();

const PORT = Number(process.env.PORT || 8080);
const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'data', 'board.db');
const APP_HTML = process.env.APP_HTML || path.join(__dirname, '..', 'app', 'index.html');
// SEED: unset loads the Coral test data, 'personal' starts an empty personal board, 'off' loads nothing.
const SEED = process.env.SEED || 'coral';
const SEED_DIR = path.join(__dirname, SEED === 'personal' ? 'seed-personal' : 'seed');
const COLLECTIONS = new Set(['tasks', 'people', 'views', 'config', 'sla']);
const SEGMENT = /^[A-Za-z0-9_\-.~:@+]{1,200}$/;
const MAX_BODY = 256 * 1024;

// ---------- storage ----------
fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
const db = new DatabaseSync(DB_PATH);
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS docs (
    coll       TEXT NOT NULL,
    id         TEXT NOT NULL,
    data       TEXT NOT NULL,
    version    INTEGER NOT NULL DEFAULT 1,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (coll, id)
  );
`);
const q = {
  list: db.prepare('SELECT id, data, version FROM docs WHERE coll = ? ORDER BY id'),
  get: db.prepare('SELECT data, version FROM docs WHERE coll = ? AND id = ?'),
  upsert: db.prepare(`INSERT INTO docs (coll, id, data, version, updated_at) VALUES (?, ?, ?, 1, ?)
                      ON CONFLICT (coll, id) DO UPDATE SET data = excluded.data, version = docs.version + 1, updated_at = excluded.updated_at`),
  del: db.prepare('DELETE FROM docs WHERE coll = ? AND id = ?'),
  count: db.prepare('SELECT COUNT(*) AS n FROM docs'),
};
const nowIso = () => new Date().toISOString();
function readDoc(coll, id) {
  const r = q.get.get(coll, id);
  return r ? { data: JSON.parse(r.data), version: r.version } : null;
}
function writeDoc(coll, id, data) {
  q.upsert.run(coll, id, JSON.stringify(data), nowIso());
  const r = readDoc(coll, id);
  broadcast({ coll, id, data: r.data, version: r.version });
  return r;
}

// ---------- first-start test data ----------
// Seed files were generated at one moment (config.settings.seededAt); shift every
// timestamp forward so the SLA clocks look the same as when they were generated.
function seedIfEmpty() {
  if (SEED === 'off' || q.count.get().n > 0 || !fs.existsSync(SEED_DIR)) return;
  const files = fs.readdirSync(SEED_DIR).filter(f => /^[a-z]+__[^/]+\.json$/.test(f));
  const settings = files.includes('config__settings.json')
    ? JSON.parse(fs.readFileSync(path.join(SEED_DIR, 'config__settings.json'), 'utf8')) : {};
  const shift = settings.seededAt ? Date.now() - Date.parse(settings.seededAt) : 0;
  const shiftDays = Math.round(shift / 86400000);
  const t = v => (typeof v === 'string' && /^\d{4}-\d\d-\d\dT/.test(v)) ? new Date(Date.parse(v) + shift).toISOString().replace(/\.\d+Z$/, 'Z') : v;
  const d = v => (typeof v === 'string' && /^\d{4}-\d\d-\d\d$/.test(v))
    ? new Date(Date.parse(v + 'T00:00:00Z') + shiftDays * 86400000).toISOString().slice(0, 10) : v;
  db.exec('BEGIN');
  try {
    for (const f of files) {
      const [coll, id] = f.slice(0, -5).split('__');
      if (!COLLECTIONS.has(coll)) continue;
      const doc = JSON.parse(fs.readFileSync(path.join(SEED_DIR, f), 'utf8'));
      if (coll === 'tasks') {
        for (const k of ['createdAt', 'firstResponseAt', 'pausedSince', 'resolvedAt', 'updatedAt']) doc[k] = t(doc[k]);
        doc.due = d(doc.due);
        doc.history = (doc.history || []).map(h => ({ ...h, at: t(h.at) }));
      }
      if (coll === 'config') doc.seededAt = nowIso();
      q.upsert.run(coll, id, JSON.stringify(doc), nowIso());
    }
    db.exec('COMMIT');
    console.log(`Loaded ${files.length} test documents`);
  } catch (e) { db.exec('ROLLBACK'); throw e; }
}
seedIfEmpty();

// Workflow v2 added "Ready to publish" before Done, so Done moved from step 5 to 6.
// Move tasks saved under the old workflow, once.
function migrateStages() {
  const cfg = readDoc('config', 'settings');
  if (!cfg || cfg.data.stageModel >= 2) return;
  db.exec('BEGIN');
  try {
    let n = 0;
    for (const r of q.list.all('tasks')) {
      const doc = JSON.parse(r.data);
      if (doc.stage === 5) { doc.stage = 6; q.upsert.run('tasks', r.id, JSON.stringify(doc), nowIso()); n++; }
    }
    q.upsert.run('config', 'settings', JSON.stringify({ ...cfg.data, stageModel: 2 }), nowIso());
    db.exec('COMMIT');
    console.log(`Moved ${n} done tasks to the new workflow`);
  } catch (e) { db.exec('ROLLBACK'); throw e; }
}
migrateStages();

// Client SLA terms (sla collection) and the business calendar were added after the first
// deploys. Load them from the seed files once, and add any of their clients to the client list.
function addSlaTerms() {
  const cfg = readDoc('config', 'settings');
  if (SEED !== 'coral' || !cfg || q.list.all('sla').length || !fs.existsSync(SEED_DIR)) return;
  const files = fs.readdirSync(SEED_DIR).filter(f => /^sla__[^/]+\.json$/.test(f));
  const seedCfg = JSON.parse(fs.readFileSync(path.join(SEED_DIR, 'config__settings.json'), 'utf8'));
  db.exec('BEGIN');
  try {
    const clients = [...(cfg.data.clients || [])];
    for (const f of files) {
      const doc = JSON.parse(fs.readFileSync(path.join(SEED_DIR, f), 'utf8'));
      q.upsert.run('sla', f.slice(5, -5), JSON.stringify(doc), nowIso());
      if (doc.client !== '*' && !clients.includes(doc.client)) clients.splice(Math.max(0, clients.indexOf('Coral Technology')), 0, doc.client);
    }
    const next = { ...cfg.data, clients, calendar: cfg.data.calendar || seedCfg.calendar };
    delete next.sla;
    q.upsert.run('config', 'settings', JSON.stringify(next), nowIso());
    db.exec('COMMIT');
    console.log(`Loaded SLA terms for ${files.length - 1} clients and the standard`);
  } catch (e) { db.exec('ROLLBACK'); throw e; }
}
addSlaTerms();

// ---------- live updates (server-sent events) ----------
const clients = new Set();
function broadcast(change) {
  const msg = `event: change\ndata: ${JSON.stringify(change)}\n\n`;
  for (const res of clients) res.write(msg);
}
setInterval(() => { for (const res of clients) res.write(': ping\n\n'); }, 25000).unref();

// ---------- http ----------
const isPlainObject = v => v !== null && typeof v === 'object' && !Array.isArray(v);
function merge(base, patch) {
  const out = { ...base };
  for (const [k, v] of Object.entries(patch)) out[k] = isPlainObject(v) && isPlainObject(base[k]) ? merge(base[k], v) : v;
  return out;
}
function send(res, status, body, type = 'application/json') {
  if (!res.hasHeader('Content-Security-Policy')) auth.securityHeaders(res);
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(type === 'application/json' ? JSON.stringify(body) : body);
}
const fail = (res, status, code, message) => send(res, status, { code, message });
function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', c => { size += c.length; if (size > MAX_BODY) { reject(Object.assign(new Error('Document is larger than 256 KiB'), { status: 413 })); req.destroy(); } else chunks.push(c); });
    req.on('end', () => {
      try { const v = JSON.parse(Buffer.concat(chunks).toString('utf8') || 'null'); isPlainObject(v) ? resolve(v) : reject(Object.assign(new Error('Body must be a JSON object'), { status: 400 })); }
      catch { reject(Object.assign(new Error('Body is not valid JSON'), { status: 400 })); }
    });
    req.on('error', reject);
  });
}

const RESET_CSS = ':root{color-scheme:dark;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,-apple-system,"Segoe UI",sans-serif}img{max-width:100%}[hidden]{display:none!important}';
const SIGN_OUT = auth.MODE === 'google'
  ? '<form method="post" action="/auth/logout" style="position:fixed;right:10px;bottom:10px;z-index:50;margin:0"><button type="submit" style="font:12px system-ui,sans-serif;padding:4px 10px;border-radius:6px;border:1px solid #8886;background:transparent;color:inherit;opacity:.7;cursor:pointer">Sign out</button></form>'
  : '';
function pageHtml(nonce) {
  const app = fs.readFileSync(APP_HTML, 'utf8').replace('<script>', `<script nonce="${nonce}" src="/runtime.js"></script>\n<script nonce="${nonce}">`);
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="robots" content="noindex"><title>Action Board</title><style>${RESET_CSS}</style></head><body>${app}${SIGN_OUT}</body></html>`;
}

// Tasks written with the ingest token come from outside (for example from email), so check
// their shape: the page renders some of these fields as HTML.
const ISO = /^\d{4}-\d\d-\d\dT\d\d:\d\d(:\d\d(\.\d+)?)?Z$/;
const DAY = /^\d{4}-\d\d-\d\d$/;
const TASK_FIELDS = {
  key: v => typeof v === 'string' && /^[A-Z][A-Z0-9]{0,9}-[A-Za-z0-9_-]{1,80}$/.test(v),
  type: v => ['incident', 'bug', 'request', 'question', 'internal', 'feature', 'change'].includes(v),
  source: v => typeof v === 'string' && /^[a-z]{1,20}$/.test(v),
  title: v => typeof v === 'string' && v.length >= 1 && v.length <= 300,
  client: v => typeof v === 'string' && v.length <= 80,
  project: v => v === null || (typeof v === 'string' && v.length <= 120),
  priority: v => Number.isInteger(v) && v >= 1 && v <= 4,
  owner: v => v === null || (typeof v === 'string' && /^[A-Za-z0-9_-]{1,20}$/.test(v)),
  queue: v => typeof v === 'string' && v.length <= 80,
  stage: v => Number.isInteger(v) && v >= 0 && v <= 6,
  createdAt: v => typeof v === 'string' && ISO.test(v),
  updatedAt: v => typeof v === 'string' && ISO.test(v),
  firstResponseAt: v => v === null || (typeof v === 'string' && ISO.test(v)),
  pausedSince: v => v === null || (typeof v === 'string' && ISO.test(v)),
  resolvedAt: v => v === null || (typeof v === 'string' && ISO.test(v)),
  pausedMins: v => Number.isInteger(v) && v >= 0,
  due: v => v === null || (typeof v === 'string' && DAY.test(v)),
  module: v => v === null || (typeof v === 'string' && v.length <= 60),
  release: v => v === null || (typeof v === 'string' && /^[A-Za-z0-9 ._-]{1,40}$/.test(v)),
  link: v => v === null || (typeof v === 'string' && v.length <= 500),
  tags: v => Array.isArray(v) && v.length <= 20 && v.every(t => typeof t === 'string' && t.length <= 40),
  notes: v => typeof v === 'string' && v.length <= 20000,
  history: v => Array.isArray(v) && v.length <= 200 && v.every(h => isPlainObject(h) && typeof h.text === 'string' && h.text.length <= 500 && typeof h.at === 'string' && ISO.test(h.at) && Object.keys(h).every(k => k === 'at' || k === 'text')),
};
const REQUIRED_TASK_FIELDS = ['key', 'type', 'title', 'client', 'priority', 'queue', 'stage', 'createdAt'];
function checkIngestTask(id, doc) {
  const bad = Object.keys(doc).filter(k => !TASK_FIELDS[k] || !TASK_FIELDS[k](doc[k]));
  const missing = REQUIRED_TASK_FIELDS.filter(k => !(k in doc));
  if (doc.key !== id) bad.push('key (must equal the document id)');
  if (bad.length || missing.length) {
    throw Object.assign(new Error(`Invalid task.${bad.length ? ' Bad fields: ' + bad.join(', ') + '.' : ''}${missing.length ? ' Missing: ' + missing.join(', ') + '.' : ''}`), { status: 400 });
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const p = url.pathname;
  if (p === '/healthz') return send(res, 200, 'ok', 'text/plain');
  if (auth.limited(req)) return fail(res, 429, 'resource_exhausted', 'Too many failed sign-ins. Try again later.');
  const who = auth.identify(req);
  try {
    if (await auth.handleAuthRoute(req, res, url, who)) return;
    if (!who) {
      if (req.headers.authorization) auth.noteFail(req);
      return auth.challenge(req, res, url);
    }
    const write = !['GET', 'HEAD'].includes(req.method);
    if (who.kind === 'ingest') {
      // The ingest token may only create or update tasks, one document at a time.
      if (!/^\/api\/tasks\/[^/]+$/.test(p) || !['PUT', 'PATCH'].includes(req.method)) return fail(res, 403, 'permission_denied', 'The ingest token can only PUT or PATCH /api/tasks/<id>');
    } else if (write) {
      if (!auth.sameOrigin(req)) return fail(res, 403, 'permission_denied', 'Cross-site request refused');
      if (['PUT', 'PATCH'].includes(req.method) && !/^application\/json\b/i.test(req.headers['content-type'] || '')) return fail(res, 415, 'invalid_argument', 'Content-Type must be application/json');
    }
    if (req.method === 'GET' && (p === '/' || p === '/index.html')) {
      const nonce = crypto.randomBytes(16).toString('base64');
      auth.securityHeaders(res, nonce);
      return send(res, 200, pageHtml(nonce), 'text/html; charset=utf-8');
    }
    if (req.method === 'GET' && p === '/runtime.js') return send(res, 200, fs.readFileSync(path.join(__dirname, 'runtime.js')), 'text/javascript; charset=utf-8');
    if (req.method === 'GET' && p === '/api/events') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
      res.write('retry: 3000\n\n');
      clients.add(res);
      req.on('close', () => clients.delete(res));
      return;
    }
    const m = /^\/api\/([^/]+)(?:\/([^/]+))?$/.exec(p);
    if (!m) return fail(res, 404, 'not_found', 'Not found');
    const coll = decodeURIComponent(m[1]); const id = m[2] && decodeURIComponent(m[2]);
    if (!COLLECTIONS.has(coll) || (id !== undefined && !SEGMENT.test(id))) return fail(res, 400, 'invalid_argument', 'Unknown collection or bad document id');
    if (!id) {
      if (req.method !== 'GET') return fail(res, 405, 'invalid_argument', 'Method not allowed');
      return send(res, 200, q.list.all(coll).map(r => ({ id: r.id, data: JSON.parse(r.data), version: r.version })));
    }
    if (req.method === 'GET') { const d = readDoc(coll, id); return d ? send(res, 200, { id, ...d }) : fail(res, 404, 'not_found', 'No such document'); }
    if (req.method === 'PUT') {
      const body = await readBody(req);
      // "If-None-Match: *" makes a PUT create-only, so a repeat delivery can't overwrite edits.
      if (req.headers['if-none-match'] === '*' && readDoc(coll, id)) return fail(res, 412, 'already_exists', 'Document already exists');
      if (who.kind === 'ingest') checkIngestTask(id, body);
      return send(res, 200, { id, ...writeDoc(coll, id, body) });
    }
    if (req.method === 'PATCH') {
      const cur = readDoc(coll, id);
      if (!cur) return fail(res, 400, 'invalid_argument', 'Document does not exist');
      const next = merge(cur.data, await readBody(req));
      if (who.kind === 'ingest') checkIngestTask(id, next);
      return send(res, 200, { id, ...writeDoc(coll, id, next) });
    }
    if (req.method === 'DELETE') { q.del.run(coll, id); broadcast({ coll, id, data: null }); return send(res, 200, { id, deleted: true }); }
    return fail(res, 405, 'invalid_argument', 'Method not allowed');
  } catch (e) {
    if (e.status) return fail(res, e.status, 'invalid_argument', e.message);
    console.error(e);
    return fail(res, 500, 'unavailable', 'Server error');
  }
});

server.listen(PORT, () => console.log(`Action board on :${PORT} (db ${DB_PATH}, sign-in: ${auth.MODE}${auth.INGEST_TOKEN ? ', ingest token on' : ''})`));
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => { server.close(); db.close(); process.exit(0); });
