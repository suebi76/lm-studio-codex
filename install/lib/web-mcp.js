const { parseSse } = require('./lmstudio-responses-gateway');

const WEB_URL = 'https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa';
const WEB_TOOLS = ['web_search_exa', 'web_fetch_exa'];

function webConfigArgs(env = process.env) {
  if (env.LMSTUDIO_CODEX_WEB === '0') return ['-c', 'mcp_servers.lmstudio_web.enabled=false'];
  return ['-c', 'mcp_servers.lmstudio_web=' +
    `{url=${JSON.stringify(WEB_URL)},enabled=true,required=true,startup_timeout_sec=20,tool_timeout_sec=60,` +
    `enabled_tools=${JSON.stringify(WEB_TOOLS)},default_tools_approval_mode="approve",` +
    `env_http_headers=${env.EXA_API_KEY ? '{"x-api-key"="EXA_API_KEY"}' : '{}'},` +
    'tools={web_search_exa={output_token_limit=4000},web_fetch_exa={output_token_limit=4000}}}'];
}

// A small diagnostic client; Codex itself owns MCP sessions during normal work.
async function checkWeb({ url = WEB_URL, live = false, env = process.env } = {}) {
  let session;
  let protocol = '2025-03-26';
  let nextId = 1;
  async function rpc(method, params = {}, notification = false) {
    const id = notification ? undefined : nextId++;
    const headers = { 'content-type': 'application/json', accept: 'application/json, text/event-stream' };
    if (env.EXA_API_KEY) headers['x-api-key'] = env.EXA_API_KEY;
    if (session) headers['mcp-session-id'] = session;
    if (method !== 'initialize') headers['mcp-protocol-version'] = protocol;
    const response = await fetch(url, {
      method: 'POST', headers, signal: AbortSignal.timeout(60000),
      body: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
    });
    if (!response.ok) throw new Error(`Web MCP HTTP ${response.status}${response.status === 429 ? ': rate limit reached; retry later or configure EXA_API_KEY.' : ''}`);
    session = response.headers.get('mcp-session-id') || session;
    if (notification) { await response.body?.cancel(); return; }
    let message;
    if (response.headers.get('content-type')?.includes('text/event-stream')) {
      for await (const event of parseSse(response.body, false)) {
        if (event.id === id) { message = event; break; }
      }
    } else message = await response.json();
    if (!message || message.id !== id) throw new Error('Web MCP returned no matching response.');
    if (message.error) throw new Error(`Web MCP: ${message.error.message}`);
    return message.result;
  }
  try {
    const init = await rpc('initialize', { protocolVersion: protocol, capabilities: {}, clientInfo: { name: 'lm-studio-codex-doctor', version: '0.5.0' } });
    protocol = init.protocolVersion;
    await rpc('notifications/initialized', {}, true);
    const catalog = await rpc('tools/list');
    for (const name of WEB_TOOLS) {
      if (!catalog.tools?.some(tool => tool.name === name)) throw new Error(`Web MCP is missing ${name}. Update the integration before relying on web access.`);
    }
    if (live) {
      return { tools: catalog.tools, call: async (name, args) => {
        if (!WEB_TOOLS.includes(name)) throw new Error('Tool is not enabled.');
        const result = await rpc('tools/call', { name, arguments: args });
        if (result.isError) throw new Error(`Web tool failed: ${JSON.stringify(result.content).slice(0,1000)}`);
        return result;
      } };
    }
    return { tools: catalog.tools };
  } catch (error) {
    throw new Error(`Internet tools unavailable: ${error.message}. Check your connection or use LMSTUDIO_CODEX_WEB=0 explicitly for offline work.`, { cause: error });
  }
}

if (require.main === module) checkWeb().then(result => {
  console.log(`[lm-studio] OK: Web MCP connected; available: ${result.tools.map(tool => tool.name).join(', ')}`);
}).catch(error => { console.error(`[lm-studio] ${error.message}`); process.exitCode = 1; });

module.exports = { WEB_URL, WEB_TOOLS, webConfigArgs, checkWeb };
