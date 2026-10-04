const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { spawn } = require('node:child_process');
const path = require('node:path');
const { once } = require('node:events');
const { parseSse, convertResponsesInputToChat } = require('../install/lib/lmstudio-responses-gateway');
let upstream, gateway, base, received, mode = 'ok', model = 'first', disconnected = false;

async function startGateway(transport = 'chat', timeout = 2000) {
  const entry = path.resolve(__dirname, '../install/lib/lmstudio-responses-gateway.js');
  const child = spawn(process.execPath, ['-e', `const {server}=require(process.argv[1]);server.listen(0,'127.0.0.1',()=>console.log(server.address().port));`, entry], {
    env: { ...process.env, LMSTUDIO_BASE_URL: `http://127.0.0.1:${upstream.address().port}`, LMSTUDIO_CODEX_TRANSPORT: transport, LMSTUDIO_CODEX_TIMEOUT_MS: String(timeout) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stderr.resume();
  const [chunk] = await once(child.stdout, 'data');
  child.stdout.resume();
  return { child, base: `http://127.0.0.1:${Number(chunk.toString().trim())}` };
}

before(async () => {
  upstream = http.createServer(async (req, res) => {
    if (req.url === '/api/v1/models') {
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ models: model ? [{ type: 'llm', key: model, loaded_instances: [{ id: model }] }] : [] }));
      return;
    }
    let text = '';
    for await (const chunk of req) text += chunk;
    received = JSON.parse(text);
    if (mode === 'http-error') { res.writeHead(400); res.end('context window exceeded'); return; }
    if (mode === 'hang') { req.on('close', () => { disconnected = true; }); res.on('close', () => { disconnected = true; }); return; }
    res.setHeader('content-type', 'text/event-stream');
    if (req.url === '/v1/responses') {
      if (mode === 'truncated') { res.end('data: {"type":"response.created"}\n\n'); return; }
      if (received.stream === false) { res.setHeader('content-type', 'application/json'); res.end('{"status":"completed","output":[]}'); return; }
      res.end('data: {"type":"response.completed","response":{"status":"completed","output":[]}}\n\n');
      return;
    }
    if (mode === 'malformed') { res.end('data: invalid\n\n'); return; }
    const delta = mode === 'tool' ? { tool_calls: [{ index: 0, id: 'call1', function: { name: received.tools?.[0].function.name || 'ping', arguments: '{"ok":true}' } }] } : { content: mode === 'empty' ? '' : 'Gruesse \u00e4' };
    res.write(`data: ${JSON.stringify({ choices: [{ delta }] })}\r\n\r\n`);
    if (mode === 'truncated') { res.end(); return; }
    res.write(`data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: mode === 'length' ? 'length' : mode === 'tool' ? 'tool_calls' : 'stop' }] })}\r\n\r\n`);
    res.write('data: {"choices":[],"usage":{"prompt_tokens":20,"completion_tokens":5,"total_tokens":25}}\n\n');
    res.end('data: [DONE]\r\n\r\n');
  });
  upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
  const started = await startGateway(); gateway = started.child; base = started.base;
});
after(async () => {
  gateway.kill(); await once(gateway, 'exit');
  upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
});

function request(extra = {}, target = base) {
  return fetch(target + '/v1/responses', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ model: 'lmstudio-loaded', input: 'hello', stream: false, ...extra }) });
}

test('health is live even with no model; readiness fails clearly', async () => {
  model = null;
  assert.equal((await fetch(base + '/health')).status, 200);
  assert.equal((await fetch(base + '/ready')).status, 502);
  model = 'first';
});
test('uses the live model on each request', async () => {
  mode = 'ok'; await (await request()).json(); assert.equal(received.model, 'first');
  model = 'second'; await (await request()).json(); assert.equal(received.model, 'second');
  assert.equal((await request({ model: 'first' })).status, 400);
});
test('non-streaming text and streamed terminal event', async () => {
  const result = await (await request()).json();
  assert.equal(result.output[0].content[0].text, 'Gruesse \u00e4');
  assert.equal(result.usage.input_tokens, 20); assert.equal(result.usage.total_tokens, 25);
  const stream = await (await request({ stream: true })).text();
  assert.match(stream, /response.completed/);
  assert.match(stream, /sequence_number/);
});
test('tool choice and JSON output schema reach upstream', async () => {
  await (await request({ tools: [{ type: 'function', name: 'ping' }], tool_choice: 'required', parallel_tool_calls: false, text: { format: { type: 'json_schema', name: 'test', schema: { type: 'object' } } } })).json();
  assert.equal(received.tool_choice, 'required');
  assert.equal(received.parallel_tool_calls, false);
  assert.equal(received.response_format.json_schema.name, 'test');
});
test('namespace tools preserve identity, forced choice and history', async () => {
  const tools = [{ type: 'namespace', name: 'mcp__lmstudio_web', tools: [{ type: 'function', name: 'web_search_exa' }] }];
  mode = 'tool';
  try {
    const result = await (await request({ tools, tool_choice: { type: 'function', namespace: tools[0].name, name: 'web_search_exa' } })).json();
    const call = result.output[0];
    assert.equal(call.namespace, tools[0].name);
    assert.equal(call.name, 'web_search_exa');
    const alias = received.tools[0].function.name;
    assert.ok(alias.length <= 64);
    assert.equal(received.tool_choice.function.name, alias);
    assert.equal(convertResponsesInputToChat({ input: [call] })[0].tool_calls[0].function.name, alias);
    const stream = await (await request({ tools, stream: true })).text();
    assert.match(stream, /"namespace":"mcp__lmstudio_web"/);
    assert.match(stream, /response.completed/);
  } finally { mode = 'ok'; }
});
test('tool calls finish with valid arguments', async () => {
  mode = 'tool'; const result = await (await request()).json();
  assert.equal(result.output[0].call_id, 'call1'); assert.equal(result.output[0].arguments, '{"ok":true}');
  mode = 'ok';
});
for (const failure of ['truncated', 'malformed', 'empty', 'length']) test(`${failure} cannot masquerade as success`, async () => {
  mode = failure;
  assert.equal((await request()).status, 502);
  const text = await (await request({ stream: true })).text();
  assert.match(text, /response.failed/); assert.doesNotMatch(text, /response.completed/);
  mode = 'ok';
});
test('upstream HTTP errors retain details', async () => {
  mode = 'http-error'; const response = await request();
  assert.equal(response.status, 400); assert.match(await response.text(), /context window exceeded/); mode = 'ok';
});
test('bad JSON and unsupported history are rejected', async () => {
  assert.equal((await fetch(base + '/v1/responses', { method: 'POST', body: '{' })).status, 400);
  assert.equal((await request({ previous_response_id: 'old' })).status, 400);
  assert.equal((await request({ input: [{ role: 'user', content: [{ type: 'input_image', image_url: 'image' }] }] })).status, 400);
});
test('browser requests are refused', async () => {
  assert.equal((await fetch(base + '/health', { headers: { origin: 'https://example.org' } })).status, 403);
});
test('oversized requests have a bounded 413 failure', async () => {
  assert.equal((await request({ input: 'x'.repeat(16 * 1024 * 1024) })).status, 413);
});
test('timeouts abort upstream; no hanging request', async () => {
  const local = await startGateway('chat', 100);
  try {
    mode = 'hang'; disconnected = false;
    const result = await request({}, local.base); assert.equal(result.status, 502);
    await new Promise(resolve => setTimeout(resolve, 50)); assert.equal(disconnected, true);
  } finally { mode = 'ok'; local.child.kill(); await once(local.child, 'exit'); }
});
test('native Responses transport preserves payload and terminal event', async () => {
  const local = await startGateway('responses');
  try {
    const result = await request({ stream: true, previous_response_id: 'previous', tools: [{ type: 'custom', name: 'patch' }] }, local.base);
    assert.match(await result.text(), /response.completed/);
    assert.equal(received.previous_response_id, 'previous'); assert.equal(received.tools[0].type, 'custom');
    assert.equal((await (await request({ stream: false }, local.base)).json()).status, 'completed');
    mode = 'truncated';
    assert.match(await (await request({ stream: true }, local.base)).text(), /response.failed/);
    mode = 'ok';
  } finally { local.child.kill(); await once(local.child, 'exit'); }
});
test('parallel call history is a single assistant turn', () => {
  const messages = convertResponsesInputToChat({ input: [
    { type: 'function_call', call_id: 'a', name: 'a' }, { type: 'function_call', call_id: 'b', name: 'b' },
    { type: 'function_call_output', call_id: 'a', output: 'A' }, { type: 'function_call_output', call_id: 'b', output: 'B' },
  ] });
  assert.equal(messages[0].tool_calls.length, 2); assert.equal(messages[1].tool_call_id, 'a');
});
test('SSE tolerates byte-split UTF-8 and CRLF boundaries', async () => {
  const bytes = Buffer.from('data: {"value":"\u00e4"}\r\n\r\ndata: [DONE]\n\n');
  async function* fragments() { for (const byte of bytes) yield Buffer.from([byte]); }
  const result = []; for await (const item of parseSse(fragments())) result.push(item);
  assert.deepEqual(result, [{ value: '\u00e4' }]);
});
