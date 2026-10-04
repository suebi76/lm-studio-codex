const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { parseSse } = require('./lmstudio-responses-gateway');
const { resolveCodex, defaults } = require('./run-codex');
const seconds = Number(process.env.LMSTUDIO_DOCTOR_TIMEOUT_SEC || 120);
if (!Number.isFinite(seconds) || seconds <= 0) throw new Error('LMSTUDIO_DOCTOR_TIMEOUT_SEC must be positive.');
let warnings = 0;
const warn = message => { warnings++; console.error(`[lm-studio] WARNING: ${message}`); };
const pass = message => console.log(`[lm-studio] OK: ${message}`);
const outputText = response => (response.output || []).flatMap(item => item.content || []).map(part => part.text || '').join('\n');

async function request(input, extra = {}) {
  const response = await fetch('http://127.0.0.1:18123/v1/responses', {
    method: 'POST', headers: { 'content-type': 'application/json' }, signal: AbortSignal.timeout(seconds * 1000),
    body: JSON.stringify({ model: 'lmstudio-loaded', input, stream: true, max_output_tokens: 2048, ...extra }),
  });
  if (!response.ok) throw new Error(`Gateway HTTP ${response.status}: ${await response.text()}`);
  let completed;
  for await (const event of parseSse(response.body, false)) {
    if (event.type === 'response.failed' || event.type === 'response.incomplete') throw new Error(JSON.stringify(event.response?.error || event.response?.incomplete_details || event));
    if (event.type === 'response.completed') completed = event.response;
  }
  if (!completed) throw new Error('No response.completed event received.');
  return completed;
}

async function codexSmoke() {
  const runtime = resolveCodex();
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'lmsc-doctor-'));
  const output = path.join(directory, 'answer.txt');
  const args = [...runtime.prefix, ...defaults(), '-c', 'approval_policy="never"', 'exec', '--sandbox', 'read-only', '--skip-git-repo-check', '--ephemeral', '--output-last-message', output, 'Reply exactly: LM_STUDIO_CODEX_DOCTOR_OK'];
  try {
    const child = spawn(runtime.command, args, { stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true, detached: process.platform !== 'win32' });
    let errors = '';
    child.stderr.on('data', chunk => { errors = (errors + chunk).slice(-8000); });
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      if (process.platform === 'win32') spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true });
      else { try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); } }
    }, seconds * 1000);
    let code;
    try {
      code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
    } finally { clearTimeout(timer); }
    if (timedOut) throw new Error(`Codex smoke test exceeded ${seconds}s.`);
    if (code !== 0) throw new Error(`Codex smoke test exited ${code}: ${errors}`);
    if (!fs.existsSync(output) || !fs.readFileSync(output, 'utf8').trim()) throw new Error('Codex returned no answer.');
    if (fs.readFileSync(output, 'utf8').trim() !== 'LM_STUDIO_CODEX_DOCTOR_OK') warn('Codex answered, but did not return the exact requested marker.');
    else pass('Codex CLI returned the expected final answer.');
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
}

async function main() {
  console.log(`[lm-studio] Runtime tests: streaming, JSON, tool round trip, Codex. Timeout: ${seconds}s per check.`);
  console.log('[lm-studio] Testing streamed text...');
  const text = await request('Reply exactly: LM_STUDIO_GATEWAY_OK');
  if (!outputText(text).trim()) throw new Error('Model returned no text.');
  if (!outputText(text).includes('LM_STUDIO_GATEWAY_OK')) warn('Model did not follow the exact text instruction.');
  else pass('Streaming text and terminal completion event work.');
  console.log('[lm-studio] Testing JSON...');
  try {
    const result = await request('Return only this JSON, without markdown: {"ok":true}');
    if (JSON.parse(outputText(result)).ok !== true) throw new Error('Unexpected JSON value.');
    pass('Model produces JSON.');
  } catch (error) { warn(`JSON: ${error.message}`); }
  console.log('[lm-studio] Testing tool call and tool result...');
  const tools = [{ type: 'function', name: 'doctor_ping', description: 'Get a secret confirmation token.', parameters: { type: 'object', properties: {}, additionalProperties: false } }];
  const input = [{ role: 'user', content: 'Call doctor_ping once, then reply with its returned token.' }];
  const callResponse = await request(input, { tools, tool_choice: 'required' });
  const calls = (callResponse.output || []).filter(item => item.type === 'function_call');
  if (calls.length !== 1 || calls[0].name !== 'doctor_ping') throw new Error('Model did not produce the required tool call; unsuitable for this agent workflow/configuration.');
  JSON.parse(calls[0].arguments);
  const token = 'DOCTOR_' + require('node:crypto').randomBytes(6).toString('hex');
  const result = await request([...input, ...callResponse.output, { type: 'function_call_output', call_id: calls[0].call_id, output: token }], { tools, tool_choice: 'none' });
  if (!outputText(result).includes(token)) throw new Error('Model did not use the tool result correctly.');
  pass('Tool call and subsequent tool result work.');
  if (process.argv.includes('--skip-codex-smoke')) warn('Codex smoke test skipped.');
  else { console.log('[lm-studio] Testing Codex CLI...'); await codexSmoke(); }
  console.log(`[lm-studio] Doctor finished${warnings ? ` with ${warnings} warning(s)` : ' successfully'}. This is a basic capability test, not a guarantee for long agent tasks.`);
}

main().catch(error => { console.error(`[lm-studio] FAIL: ${error.message}`); process.exitCode = 1; });
