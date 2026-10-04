const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { once } = require('node:events');
const { webConfigArgs, checkWeb, WEB_TOOLS } = require('../install/lib/web-mcp');
const { convertTools } = require('../install/lib/lmstudio-responses-gateway');

test('web enabled by default, secrets stay out of arguments, explicit offline switch', () => {
  const config = webConfigArgs({ EXA_API_KEY: 'secret-test' }).join(' ');
  assert.match(config, /required=true/);
  assert.match(config, /EXA_API_KEY/);
  assert.doesNotMatch(config, /secret-test/);
  assert.deepEqual(webConfigArgs({ LMSTUDIO_CODEX_WEB: '0' }), ['-c', 'mcp_servers.lmstudio_web.enabled=false']);
});

test('namespace aliases are unique, stable and reject unsupported members', () => {
  const tools = ['one', 'two'].map(name => ({ type: 'namespace', name, tools: [{ type: 'function', name: 'search' }] }));
  const mapped = convertTools(tools);
  assert.notEqual(mapped[0].function.name, mapped[1].function.name);
  assert.deepEqual(mapped, convertTools(tools));
  assert.throws(() => convertTools([...tools, tools[0]]), /Duplicate/);
  assert.throws(() => convertTools([{ type: 'namespace', name: 'bad', tools: [{ type: 'custom', name: 'patch' }] }]), /Unsupported/);
});

test('MCP diagnostic verifies handshake, sessions, catalog and reports failures', async () => {
  let mode = 'ok';
  const server = http.createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    const message = JSON.parse(body);
    if (mode === 'limit') { res.writeHead(429); res.end(); return; }
    if (message.method === 'initialize') {
      res.setHeader('mcp-session-id', 'test-session');
      res.end(JSON.stringify({ jsonrpc: '2.0', id: message.id, result: { protocolVersion: '2025-03-26', capabilities: {}, serverInfo: { name: 'test', version: '1' } } }));
      return;
    }
    assert.equal(req.headers['mcp-session-id'], 'test-session');
    if (message.method === 'notifications/initialized') { res.writeHead(202); res.end(); return; }
    res.setHeader('content-type', 'text/event-stream');
    res.end(`data: ${JSON.stringify({ jsonrpc: '2.0', id: message.id, result: { tools: mode === 'missing' ? [] : WEB_TOOLS.map(name => ({ name })) } })}\n\n`);
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const options = { url: `http://127.0.0.1:${server.address().port}`, env: {} };
  try {
    assert.equal((await checkWeb(options)).tools.length, 2);
    mode = 'missing'; await assert.rejects(checkWeb(options), /missing web_search_exa/);
    mode = 'limit'; await assert.rejects(checkWeb(options), /429.*EXA_API_KEY/);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
