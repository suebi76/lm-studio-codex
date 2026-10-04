const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const { resolveCodex, defaults } = require('../install/lib/run-codex');

test('installed Codex speaks to gateway and resumes an explicit session', { skip: process.env.LMSC_TEST_CODEX !== '1', timeout: 60000 }, async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'lmsc-integration-'));
  const requests = [];
  let webCalls = 0;
  const mcp = http.createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    const message = JSON.parse(body);
    if (message.id === undefined) { res.writeHead(202); res.end(); return; }
    let result;
    if (message.method === 'initialize') result = { protocolVersion: '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'test-web', version: '1' } };
    else if (message.method === 'tools/list') result = { tools: [{ name: 'web_search_exa', description: 'TEST_WEB_SEARCH', inputSchema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } }] };
    else if (message.method === 'tools/call') { webCalls++; result = { content: [{ type: 'text', text: 'LMSC_WEB_OK' }] }; }
    else result = {};
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ jsonrpc: '2.0', id: message.id, result }));
  });
  mcp.listen(0, '127.0.0.1'); await once(mcp, 'listening');
  const upstream = http.createServer(async (req, res) => {
    if (req.url === '/api/v1/models') { res.end(JSON.stringify({ models: [{ type: 'llm', loaded_instances: [{ id: 'test-model' }] }] })); return; }
    let text = ''; for await (const chunk of req) text += chunk;
    requests.push(JSON.parse(text));
    res.setHeader('content-type', 'text/event-stream');
    if (requests.length <= 2) {
      const web = requests.at(-1).tools?.find(tool => tool.function.description.includes('TEST_WEB_SEARCH'));
      const fn = requests.length === 1 ? { name: 'exec_command', arguments: JSON.stringify({ cmd: 'echo LMSC_TOOL_OK' }) } : { name: web?.function.name, arguments: JSON.stringify({ query: 'test' }) };
      const delta = { tool_calls: [{ index: 0, id: `integration-call-${requests.length}`, type: 'function', function: fn }] };
      res.end(`data: ${JSON.stringify({ choices: [{ delta, finish_reason: null }] })}\n\ndata: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\ndata: [DONE]\n\n`);
      return;
    }
    res.end('data: {"choices":[{"delta":{"content":"INTEGRATION_OK"},"finish_reason":null}]}\n\ndata: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n');
  });
  upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
  const gatewayPath = path.resolve(__dirname, '../install/lib/lmstudio-responses-gateway.js');
  const gateway = spawn(process.execPath, ['-e', 'const {server}=require(process.argv[1]);server.listen(0,"127.0.0.1",()=>console.log(server.address().port));', gatewayPath], {
    env: { ...process.env, LMSTUDIO_BASE_URL: `http://127.0.0.1:${upstream.address().port}`, LMSTUDIO_CODEX_TRANSPORT: 'chat' }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let gatewayErrors = ''; gateway.stderr.on('data', chunk => { gatewayErrors += chunk; });
  const [chunk] = await once(gateway.stdout, 'data'); gateway.stdout.resume();
  const port = Number(chunk.toString().trim());
  const runtime = resolveCodex();
  async function run(session) {
    const args = [...runtime.prefix, ...defaults(), '-c', `mcp_servers.lmstudio_web={url="http://127.0.0.1:${mcp.address().port}",enabled=true,required=true,default_tools_approval_mode="approve"}`, '-c', 'model_provider="test_local"',
      '-c', 'model_providers.test_local.name="test"', '-c', `model_providers.test_local.base_url="http://127.0.0.1:${port}/v1"`,
      '-c', 'model_providers.test_local.wire_api="responses"', '-c', 'model_providers.test_local.stream_max_retries=0',
      '-c', 'approval_policy="never"', 'exec', '--sandbox', 'read-only', '--skip-git-repo-check'];
    if (session) args.push('resume', session);
    args.push('--json', '--', 'Reply exactly INTEGRATION_OK. Do not call tools.');
    const child = spawn(runtime.command, args, { cwd: directory, env: { ...process.env, CODEX_HOME: directory }, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    let output = '', errors = '';
    child.stdout.on('data', chunk => { output += chunk; }); child.stderr.on('data', chunk => { errors += chunk; });
    const timer = setTimeout(() => child.kill(), 20000);
    let code; try { [code] = await once(child, 'close'); } finally { clearTimeout(timer); }
    assert.equal(code, 0, errors + output + gatewayErrors);
    const events = output.trim().split(/\r?\n/).map(line => JSON.parse(line));
    assert.ok(events.some(event => event.item?.text === 'INTEGRATION_OK'), output + gatewayErrors);
    return events.find(event => event.type === 'thread.started')?.thread_id;
  }
  try {
    const thread = await run(); assert.ok(thread); await run(thread);
    assert.equal(requests.length, 4); assert.ok(requests[3].messages.length > requests[0].messages.length);
    assert.ok(requests[1].messages.some(message => message.role === 'tool' && message.content.includes('LMSC_TOOL_OK')));
    assert.equal(webCalls, 1);
    assert.ok(requests[2].messages.some(message => message.role === 'tool' && message.content.includes('LMSC_WEB_OK')));
    console.log('Codex tools:', requests[0].tools?.map(tool => tool.function.name).join(', '));
  } finally {
    gateway.kill(); await once(gateway, 'exit'); upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
    mcp.closeAllConnections(); await new Promise(resolve => mcp.close(resolve));
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
