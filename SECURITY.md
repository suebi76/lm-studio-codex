# Security

This project runs local commands through Codex CLI and talks to LM Studio on localhost.

## Scope

- No remote service is required by the gateway.
- The gateway listens on `127.0.0.1:18123`.
- LM Studio is expected on `127.0.0.1:1234`.

## Reporting Issues

Please open a GitHub issue for security concerns that do not expose private data. If a report includes secrets, tokens, private paths, or other sensitive data, remove that information before posting publicly.

## Local Model Caveat

Local models vary in tool-use quality. The default loop uses workspace-write sandboxing with no approval prompts; commands requiring escalation fail. Review changes before committing them.

The gateway rejects browser-origin requests and listens only on loopback, but other local processes can still access it. Do not expose it to a network. Session history and logs can contain private project information and must not be published.
