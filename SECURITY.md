# Security

This project runs local commands through Codex CLI and talks to LM Studio on localhost.

## Scope

- No remote service is required by the gateway.
- The gateway listens on `127.0.0.1:18123`.
- LM Studio is expected on `127.0.0.1:1234`.

## Web Access

The launcher enables hosted Exa MCP for web search and page reading by default. Tool arguments (queries, objectives, requested URLs) are sent to Exa, not just localhost. These read-only web tools run without individual approval prompts. Do not include secrets or private project content in research requests. Web pages and search results are untrusted data, not instructions. Set `LMSTUDIO_CODEX_WEB=0` to disable this integration; this does not disable other user-configured tools or act as a network firewall. Optional `EXA_API_KEY` is passed through an environment-backed header, never written into managed config or command arguments. External service availability and quotas apply.

## Reporting Issues

Please open a GitHub issue for security concerns that do not expose private data. If a report includes secrets, tokens, private paths, or other sensitive data, remove that information before posting publicly.

## Local Model Caveat

Local models vary in tool-use quality. The default loop uses workspace-write sandboxing with no approval prompts; commands requiring escalation fail. Review changes before committing them.

The gateway rejects browser-origin requests and listens only on loopback, but other local processes can still access it. Do not expose it to a network. Session history and logs can contain private project information and must not be published.
