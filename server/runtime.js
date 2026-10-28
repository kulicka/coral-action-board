// Browser adapter: provides window.claude.use("db" | "user") on top of the
// server's /api routes, with the same shapes the claude.ai Artifact runtime
// gives the page (collection/doc refs, onSnapshot, set/update/delete).
(() => {
  'use strict';
  const cache = {};            // coll -> Map(id -> data)
  const loaded = {};           // coll -> Promise
  const collSubs = {};         // coll -> Set(fn)
  const docSubs = {};          // "coll/id" -> Set(fn)
  const meta = { fromCache: false, hasPendingWrites: false };

  const freeze = v => (v && typeof v === 'object' ? Object.freeze(v) : v);
  const docSnap = (id, data) => ({ id, exists: data !== undefined, data: () => data, metadata: meta });
  function notify(coll, id) {
    const map = cache[coll] || new Map();
    const docs = [...map.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1)).map(([k, v]) => docSnap(k, v));
    const qs = { docs, size: docs.length, empty: !docs.length, docChanges: () => [], metadata: meta };
    (collSubs[coll] || []).forEach(fn => fn(qs));
    if (id !== undefined) (docSubs[coll + '/' + id] || []).forEach(fn => fn(docSnap(id, map.get(id))));
    else for (const key of Object.keys(docSubs)) if (key.startsWith(coll + '/')) { const k = key.slice(coll.length + 1); docSubs[key].forEach(fn => fn(docSnap(k, map.get(k)))); }
  }
  function apply(coll, id, data) {
    const map = cache[coll] || (cache[coll] = new Map());
    if (data === null) map.delete(id); else map.set(id, freeze(data));
    notify(coll, id);
  }
  async function api(method, url, body) {
    let r;
    try { r = await fetch(url, { method, headers: body ? { 'Content-Type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined, credentials: 'same-origin' }); }
    catch (e) { throw { code: 'unavailable', message: 'Network error' }; }
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw { code: j.code === 'not_found' ? 'invalid_argument' : (j.code || 'unavailable'), message: j.message || r.statusText };
    return j;
  }
  function load(coll) {
    return loaded[coll] || (loaded[coll] = api('GET', '/api/' + encodeURIComponent(coll)).then(rows => {
      cache[coll] = new Map(rows.map(r => [r.id, freeze(r.data)]));
      notify(coll);
    }).catch(e => { delete loaded[coll]; throw e; }));
  }
  function reloadAll() { for (const c of Object.keys(loaded)) { delete loaded[c]; load(c).catch(() => {}); } }

  let es = null, everOpen = false;
  function connect() {
    if (es) return;
    es = new EventSource('/api/events');
    es.addEventListener('change', ev => { const c = JSON.parse(ev.data); if (cache[c.coll]) apply(c.coll, c.id, c.data); });
    es.addEventListener('open', () => { if (everOpen) reloadAll(); everOpen = true; });
  }

  function subscribe(set, key, fn, start, onError) {
    const s = set[key] || (set[key] = new Set());
    s.add(fn); connect();
    start().catch(e => onError && onError(e));
    return () => s.delete(fn);
  }
  const docRef = (coll, id) => {
    const url = '/api/' + encodeURIComponent(coll) + '/' + encodeURIComponent(id);
    return {
      id, path: coll + '/' + id,
      async get() { await load(coll); return docSnap(id, cache[coll].get(id)); },
      async set(data) { const r = await api('PUT', url, data); apply(coll, id, r.data); },
      async update(data) { const r = await api('PATCH', url, data); apply(coll, id, r.data); },
      async delete() { await api('DELETE', url); apply(coll, id, null); },
      onSnapshot(next, error) {
        return subscribe(docSubs, coll + '/' + id, next, () => load(coll).then(() => next(docSnap(id, cache[coll].get(id)))), error);
      },
    };
  };
  const collRef = coll => ({
    path: coll,
    doc: id => docRef(coll, id || Math.random().toString(36).slice(2, 12)),
    async add(data) { const ref = docRef(coll, Math.random().toString(36).slice(2, 12)); await ref.set(data); return ref; },
    onSnapshot(next, error) { return subscribe(collSubs, coll, next, () => load(coll).then(() => notify(coll)), error); },
  });
  const split = p => { const parts = p.split('/'); return [parts.slice(0, -1).join('/'), parts[parts.length - 1]]; };
  const dbNs = Object.freeze({ collection: c => collRef(c), doc: p => docRef(...split(p)) });

  // Everyone past the server's sign-in can edit; real per-person sign-in comes later.
  const userNs = Object.freeze({
    isOwner: async () => false, canEdit: async () => true, can: async () => true,
    id: async () => null, name: async () => '', email: async () => null, avatarUrl: async () => null,
    me: async () => ({ id: null, name: '', avatarUrl: '', color: '#8c939d', email: null, isOwner: false, canEdit: true }),
    profiles: async ids => Object.fromEntries([].concat(ids).map(i => [i, { id: i, name: '', avatarUrl: '', color: '#8c939d', email: null, isMe: false, guest: false }])),
    search: async () => [],
  });
  window.claude = Object.freeze({ use: async name => (name === 'db' ? dbNs : name === 'user' ? userNs : null) });
})();
