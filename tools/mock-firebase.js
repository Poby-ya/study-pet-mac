// A stand-in for the Firebase Realtime Database REST API, for testing sharing on one
// machine without a Firebase project: GET/PUT/PATCH/DELETE on <path>.json, streaming GET
// (server-sent events) and {".sv":"timestamp"}. No rules, no auth, memory only.
//
//   node tools/mock-firebase.js            # listens on http://127.0.0.1:8790
//   invite: http://127.0.0.1:8790/rooms/<16+ lowercase letters or digits>
const http = require('http');

const port = Number(process.env.PORT || 8790);
let root = null;
const listeners = new Set();
let failNext = "";

const valueAt = (keys) => keys.reduce((node, key) => (node && typeof node === 'object' ? node[key] ?? null : null), root);

function resolve(value) {
  if (value && typeof value === 'object') {
    if (value['.sv'] === 'timestamp') return Date.now();
    for (const key of Object.keys(value)) value[key] = resolve(value[key]);
  }
  return value;
}

function setAt(keys, value) {
  if (keys.length === 0) { root = value; return; }
  if (!root || typeof root !== 'object') root = {};
  let node = root;
  for (const key of keys.slice(0, -1)) {
    if (!node[key] || typeof node[key] !== 'object') node[key] = {};
    node = node[key];
  }
  const last = keys[keys.length - 1];
  if (value === null) delete node[last]; else node[last] = value;
}

function send(res, path, data) {
  res.write(`event: put\ndata: ${JSON.stringify({ path, data })}\n\n`);
}

// Tell every listener whose subtree the write touched, the way Firebase does.
function notify(keys) {
  for (const { keys: at, res } of listeners) {
    if (keys.length >= at.length && at.every((k, i) => keys[i] === k)) {
      send(res, '/' + keys.slice(at.length).join('/'), valueAt(keys));
    } else if (keys.every((k, i) => at[i] === k)) {
      send(res, '/', valueAt(at));
    }
  }
}

http.createServer((req, res) => {
  const keys = new URL(req.url, 'http://local').pathname.replace(/\.json$/, '').split('/').filter(Boolean);
  if (req.method === 'GET' && (req.headers.accept || '').includes('text/event-stream')) {
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    const listener = { keys, res };
    listeners.add(listener);
    send(res, '/', valueAt(keys));
    const keepAlive = setInterval(() => res.write('event: keep-alive\ndata: null\n\n'), 30000);
    req.on('close', () => { listeners.delete(listener); clearInterval(keepAlive); });
    return;
  }
  let body = '';
  req.on('data', (chunk) => (body += chunk));
  req.on('end', () => {
    res.setHeader('Content-Type', 'application/json');
    if (req.method === 'GET') return res.end(JSON.stringify(valueAt(keys)));
    if (req.headers['x-test-fail'] === 'true') { res.statusCode = 503; return res.end(JSON.stringify({ error: 'test failure' })); }
    if (keys.join('/') === '__test/fail-next') { failNext = body; return res.end('true'); }
    if (failNext === req.method) { failNext = ''; res.statusCode = 503; return res.end(JSON.stringify({ error: 'injected failure' })); }
    const value = req.method === 'DELETE' ? null : resolve(JSON.parse(body || 'null'));
    if (req.method === 'PATCH') {
      const changed = Object.entries(value || {}).map(([key, child]) => { const path = [...keys, ...key.split('/')]; setAt(path, child); return path; });
      for (const path of changed) notify(path);
    } else {
      setAt(keys, value);
      notify(keys);
    }
    console.log(req.method, '/' + keys.join('/'));
    res.end(JSON.stringify(value));
  });
}).listen(port, '127.0.0.1', () => console.log(`mock firebase on http://127.0.0.1:${port}`));
