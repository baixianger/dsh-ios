// Tiny reverse proxy: exposes DSH (127.0.0.1:3080) on the Tailscale interface.
// Rewrites Host to loopback so DSH's browser-trust fence accepts the request.
const http = require('http');
const net = require('net');

const TARGET_HOST = '127.0.0.1';
const TARGET_PORT = 3080;
const LISTEN_PORT = Number(process.env.PORT || 8080);
const LISTEN_HOST = process.env.HOST || '0.0.0.0';

const server = http.createServer((req, res) => {
  const headers = Object.assign({}, req.headers, { host: TARGET_HOST + ':' + TARGET_PORT });
  const upstream = http.request({
    hostname: TARGET_HOST,
    port: TARGET_PORT,
    path: req.url,
    method: req.method,
    headers: headers,
  }, (pres) => {
    res.writeHead(pres.statusCode, pres.headers);
    pres.pipe(res);
  });
  upstream.on('error', () => { res.writeHead(502); res.end('proxy error'); });
  req.pipe(upstream);
});

server.on('upgrade', (req, socket, head) => {
  let headerStr = req.method + ' ' + req.url + ' HTTP/' + req.httpVersion + '\r\n';
  headerStr += 'Host: ' + TARGET_HOST + ':' + TARGET_PORT + '\r\n';
  for (let i = 0; i < req.rawHeaders.length; i += 2) {
    const name = req.rawHeaders[i];
    if (name.toLowerCase() === 'host') continue;
    headerStr += name + ': ' + req.rawHeaders[i + 1] + '\r\n';
  }
  headerStr += '\r\n';

  const upstream = net.connect(TARGET_PORT, TARGET_HOST, () => {
    upstream.write(headerStr);
    if (head && head.length) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  upstream.on('error', () => socket.destroy());
  socket.on('error', () => upstream.destroy());
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log('dsh-proxy: ' + LISTEN_HOST + ':' + LISTEN_PORT + ' -> ' + TARGET_HOST + ':' + TARGET_PORT);
});
