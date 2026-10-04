const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const readline = require('node:readline');
const { webConfigArgs } = require('./web-mcp');

function resolveCodex() {
  if (process.platform !== 'win32') return { command: 'codex', prefix: [] };
  const result = spawnSync('where.exe', ['codex'], { encoding: 'utf8', timeout: 10000, windowsHide: true });
  for (const candidate of (result.stdout || '').trim().split(/\r?\n/)) {
    if (/\.exe$/i.test(candidate)) return { command: candidate, prefix: [] };
    const cli = path.join(path.dirname(candidate), 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
    if (fs.existsSync(cli)) return { command: process.execPath, prefix: [cli] };
  }
  throw new Error('Cannot resolve Codex executable. Install the official CLI: npm install -g @openai/codex');
}

function defaults() {
  const timeout = Number(process.env.LMSTUDIO_CODEX_TIMEOUT_MS || 600000);
  if (!Number.isSafeInteger(timeout) || timeout < 100) throw new Error('LMSTUDIO_CODEX_TIMEOUT_MS must be an integer of at least 100.');
  const args = ['-c', 'model="lmstudio-loaded"', '-c', 'model_provider="lmstudio_gateway"',
    '-c', 'model_providers.lmstudio_gateway.name="LM Studio local"',
    '-c', 'model_providers.lmstudio_gateway.base_url="http://127.0.0.1:18123/v1"',
    '-c', 'model_providers.lmstudio_gateway.wire_api="responses"',
    '-c', 'model_providers.lmstudio_gateway.requires_openai_auth=false',
    '-c', 'model_providers.lmstudio_gateway.stream_max_retries=0',
    '-c', `model_providers.lmstudio_gateway.stream_idle_timeout_ms=${timeout + 10000}`,
    '-c', 'web_search="disabled"', '-c', 'features.multi_agent=false', '-c', 'features.plugins=false', ...webConfigArgs()];
  const context = Number(process.env.LMSTUDIO_CODEX_CONTEXT);
  if (Number.isSafeInteger(context) && context > 0) {
    args.push('-c', `model_context_window=${context}`, '-c', `model_auto_compact_token_limit=${Math.floor(context * 0.7)}`);
  }
  return args;
}

let lastModel;
async function refreshModel() {
  const response = await fetch('http://127.0.0.1:18123/ready', { signal: AbortSignal.timeout(7000) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error?.message || `Gateway HTTP ${response.status}`);
  if (result.contextLength) process.env.LMSTUDIO_CODEX_CONTEXT = String(result.contextLength);
  else if (lastModel && lastModel !== result.model) delete process.env.LMSTUDIO_CODEX_CONTEXT;
  lastModel = result.model;
  console.error(`[lm-studio] Model: ${result.model}; transport: ${result.transport}; context: ${process.env.LMSTUDIO_CODEX_CONTEXT || 'unknown'}`);
  return result;
}

async function runTask(runtime, args, sessionId, prompt, display = true) {
  const taskArgs = [...defaults(), '-c', 'approval_policy="never"', 'exec', '--sandbox', 'workspace-write', '--skip-git-repo-check'];
  if (sessionId) taskArgs.push('resume', sessionId);
  taskArgs.push(...args, '--json');
  if (prompt !== undefined) taskArgs.push('--', prompt);
  const child = spawn(runtime.command, [...runtime.prefix, ...taskArgs], { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true, detached: process.platform !== 'win32' });
  let threadId = sessionId;
  let answered = false;
  let failure = false;
  const started = Date.now();
  const timer = setInterval(() => {
    if (display) console.error(`[lm-studio] Working (${Math.round((Date.now() - started) / 1000)}s). Ctrl+C stops this task.`);
  }, 15000);
  const interrupt = () => {
    if (!child.pid || child.exitCode !== null) return;
    if (process.platform === 'win32') spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true });
    else { try { process.kill(-child.pid, 'SIGINT'); } catch { child.kill('SIGINT'); } }
  };
  process.on('SIGINT', interrupt);
  child.stderr.on('data', chunk => process.stderr.write(chunk));
  const lines = readline.createInterface({ input: child.stdout });
  lines.on('line', line => {
    let event;
    try { event = JSON.parse(line); } catch { process.stderr.write(line + '\n'); return; }
    if (event.type === 'thread.started') threadId = event.thread_id;
    if (event.type === 'error' || event.type === 'turn.failed') {
      failure = true;
      console.error(`[lm-studio] ${event.message || event.error?.message || JSON.stringify(event)}`);
    }
    if (event.type === 'item.started' && event.item?.type === 'command_execution') console.error(`[lm-studio] Command: ${event.item.command}`);
    if (event.type === 'item.started' && event.item?.type === 'mcp_tool_call') console.error(`[lm-studio] MCP: ${event.item.server}/${event.item.tool}`);
    if (event.type === 'item.completed') {
      const item = event.item || {};
      if (item.type === 'agent_message' && item.text) { answered = true; console.log(item.text); }
      else if (item.type === 'command_execution') {
        if (item.aggregated_output) process.stdout.write(item.aggregated_output + '\n');
        console.error(`[lm-studio] Command finished: ${item.exit_code ?? item.status}`);
      } else if (item.type === 'file_change') console.error(`[lm-studio] Files: ${JSON.stringify(item.changes)}`);
      else if (item.type === 'mcp_tool_call') console.error(`[lm-studio] MCP ${item.tool}: ${item.status}${item.error ? ` - ${JSON.stringify(item.error)}` : ''}`);
    }
  });
  try {
    const code = await new Promise((resolve, reject) => {
      child.on('error', reject);
      child.on('close', code => resolve(code ?? 130));
    });
    if (!answered && code === 0 && !failure) {
      console.error('[lm-studio] Codex finished without an answer. Run lm-studio-doctor and inspect gateway logs.');
      failure = true;
    }
    return { code: code || (failure ? 1 : 0), threadId };
  } finally { clearInterval(timer); process.off('SIGINT', interrupt); lines.close(); }
}

async function main(args = process.argv.slice(2)) {
  if (process.env.LMSTUDIO_CODEX_ARGS_JSON) {
    args = JSON.parse(process.env.LMSTUDIO_CODEX_ARGS_JSON);
    delete process.env.LMSTUDIO_CODEX_ARGS_JSON;
    if (!Array.isArray(args) || args.some(arg => typeof arg !== 'string')) throw new Error('Invalid launcher arguments.');
  }
  if (['--help', '-h', 'help'].includes(args[0])) {
    console.log('lm-studio                 Continue tasks in a session (exec loop)\nlm-studio "task"          Run one task\nlm-studio exec ...        Native Codex exec arguments\nlm-studio resume ...      Native exec resume\nlm-studio --tui           Native interactive Codex UI\nLoop: :new, :model, :exit. Model changes apply on the next request.');
    return 0;
  }
  const runtime = resolveCodex();
  console.error(process.env.LMSTUDIO_CODEX_WEB === '0'
    ? '[lm-studio] Web MCP disabled explicitly (offline mode).'
    : '[lm-studio] Web MCP: Exa search and page reading enabled. Search queries and requested URLs are sent to Exa.');
  if (args.length) {
    if (!args.includes('--help') && !args.includes('-h')) await refreshModel();
    if (!['exec', 'resume', 'fork', 'review', '--codex', '--tui'].includes(args[0])) {
      if (args[0].startsWith('-')) throw new Error(`Unknown option ${args[0]}. Use lm-studio --help.`);
      return (await runTask(runtime, [], null, args.join(' '))).code;
    }
    let nativeArgs;
    if (args[0] === '--tui') {
      const help = spawnSync(runtime.command, [...runtime.prefix, '--help'], { encoding: 'utf8', timeout: 10000, windowsHide: true });
      nativeArgs = [...defaults(), ...(help.stdout?.includes('--no-daemon') ? ['--no-daemon'] : []), ...args.slice(1)];
    } else if (args[0] === '--codex') nativeArgs = [...defaults(), ...args.slice(1)];
    else nativeArgs = [...defaults(), 'exec', ...(args[0] === 'exec' ? args.slice(1) : args)];
    return await new Promise((resolve, reject) => {
      const child = spawn(runtime.command, [...runtime.prefix, ...nativeArgs], { stdio: 'inherit' });
      child.on('error', reject);
      child.on('close', code => resolve(code ?? 130));
    });
  }
  let threadId;
  console.error('[lm-studio] Ready. :new starts a fresh session; :model checks the model; :exit quits.');
  const input = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: !!process.stdin.isTTY, prompt: 'lm-studio> ' });
  input.on('SIGINT', () => { if (input.paused) process.emit('SIGINT'); else input.close(); });
  try {
    if (process.stdin.isTTY) input.prompt();
    for await (const line of input) {
      const command = line.trim();
      if ([':exit', ':quit', 'exit', 'quit'].includes(command)) break;
      if (command === ':new') { threadId = undefined; console.error('[lm-studio] New session.'); }
      else if (command === ':model') {
        try { await refreshModel(); } catch (error) { console.error(`[lm-studio] ${error.message}`); }
      } else if (command) {
        input.pause();
        try {
          await refreshModel();
          const result = await runTask(runtime, [], threadId, line);
          threadId = result.threadId;
          console.error(`[lm-studio] Task ${result.code === 0 ? 'completed' : `failed (${result.code})`}.${threadId ? ` Session: ${threadId}` : ''}`);
        } catch (error) { console.error(`[lm-studio] ${error.message}`); }
        finally { input.resume(); }
      }
      if (process.stdin.isTTY) input.prompt();
    }
  } finally { input.close(); }
  return 0;
}

if (require.main === module) main().then(code => { process.exitCode = code; }).catch(error => {
  console.error(`[lm-studio] ERROR: ${error.message}`);
  process.exitCode = 1;
});
module.exports = { runTask, defaults, resolveCodex };
