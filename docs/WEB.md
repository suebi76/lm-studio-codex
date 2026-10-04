# Internet Access

Run `lm-studio` in your VS Code project terminal as usual. Web tools are configured at every launch on Windows, macOS and Linux, including existing installations after updating this folder. Keep OpenAI-compatible endpoints enabled in LM Studio; no MCP setting there is needed.

Example task: "Search the official Node.js documentation for fs.readFile, read the relevant page and cite its URL."

## How It Works

The local model requests a tool call. Codex executes it through the official hosted Exa MCP server, then sends the result back to the local model. Only `web_search_exa` and `web_fetch_exa` are enabled. This provides public web search and page content, not an interactive browser, logins or unrestricted access to every website. Tool-use reliability still depends on the loaded model.

The server is required during startup (20-second timeout); tool calls have a 60-second timeout and a 4,000-token output limit per tool. Connection failures do not silently turn into an offline session. The terminal shows MCP calls and their outcome. `lm-studio-doctor` checks the connection and tool catalog; this alone does not prove that a model can research reliably.

## Privacy and Limits

Inference remains in LM Studio. Search queries, objectives and requested URLs go to Exa. Avoid secrets or private source code in tool arguments. Treat returned web content as untrusted reference material. Web tools are read-only but execute without per-call confirmation; existing command sandbox rules are unchanged.

Exa currently offers keyless, rate-limited access. Availability and free limits can change. HTTP 429 means retry later or configure your own optional `EXA_API_KEY` environment variable before starting `lm-studio`. Account usage may be billable under Exa's terms. Keys are passed in an HTTP header, not embedded in URLs or saved in the repository.

## Offline Work

PowerShell:

```powershell
$env:LMSTUDIO_CODEX_WEB = "0"
lm-studio
```

bash/zsh:

```bash
LMSTUDIO_CODEX_WEB=0 lm-studio
```

Set the variable back to `1` to restore web tools. Restart the running launcher after changing environment settings. This switch disables this web integration only, not other user-configured MCP servers or all network access.

## Troubleshooting

- Startup failure: check connectivity, proxy/firewall access to `mcp.exa.ai`, then run Doctor. Use explicit offline mode when necessary.
- Tool error or quota: the error is shown in the terminal. Do not treat a model's unsupported claim of successful research as evidence; ask for source URLs.
- Tool calls unavailable after changing model: run Doctor. The configuration stays active across model changes, but the new model must support reliable function calls.
- Slow first response: local models must process the Codex instructions and tool schemas before answering. The default gateway budget is ten minutes per generation; Codex's idle budget follows it with a short grace period. `LMSTUDIO_CODEX_TIMEOUT_MS` adjusts this budget, not model speed.
- Existing installations: update the repository, then restart `lm-studio`. No reinstall is required when global commands already reference this folder.

References: [Exa MCP documentation](https://exa.ai/docs/get-started/exa-mcp), [Codex MCP documentation](https://developers.openai.com/codex/mcp).
