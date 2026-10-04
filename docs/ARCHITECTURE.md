# Architecture

The global command runs in the terminal's current directory. PowerShell and bash perform OS-specific setup; shared Node.js code handles sessions and diagnostics.

`lm-studio -> Codex CLI -> 127.0.0.1:18123 -> LM Studio (127.0.0.1:1234)`

## Sessions

The default prompt loop uses Codex exec JSON events and resumes the exact thread ID for the next task. It does not guess using `--last`. `:new` starts another session; `:exit` exits. Output, commands, file changes, failures, and periodic progress are visible. Empty successful turns are treated as failures.

`--tui` opens the native interface and uses `--no-daemon` when the installed CLI advertises it. No undocumented daemon flag is imposed on exec. Managed provider settings are passed at launch so an old copied config cannot redirect requests.

## Transports

The default `chat` transport translates Responses into Chat Completions. It moves system/developer instructions to the beginning for strict templates, preserves parallel function-call history, forwards tool choice and JSON schemas, and translates streaming text, tool calls, and token usage.

Set `LMSTUDIO_CODEX_TRANSPORT=responses` to forward requests to LM Studio's native `/v1/responses`. This avoids translation and preserves features such as image inputs and custom tools when the model/server supports them. There is no silent retry on another transport: a retry could duplicate work.

Chat mode supports text and function tools, not every Responses feature. Unsupported content is rejected with a concrete error rather than silently removed. Cloud web search, plugins, and multi-agent tools are disabled in the managed local profile. Unsupported capabilities can still vary between Codex releases.

## Model Selection

Every inference request queries LM Studio's native `/api/v1/models` catalog and requires exactly one loaded LLM. The cached selection file is diagnostic only. Requests never silently load a model named in stale state. Switch models between tasks; the next request uses the new model. An active generation cannot migrate to a different model.

Loaded context size is passed to Codex when available. Token usage is forwarded when LM Studio supplies it. No history is silently truncated. Switching to a smaller context may require `:new`.

## Lifecycle

`/health` reports process identity, source revision, upstream address, transport and timeout without requiring a loaded model. `/ready` checks live model availability. Startup verifies the gateway belongs to this installation and restarts it after source/settings changes. Foreign port owners are never killed. Unix launches use nohup; Windows launches use hidden processes.

Requests have a 16 MiB body limit and a configurable total timeout. Disconnecting a client aborts its upstream generation. Truncated streams, malformed events, missing terminal events, invalid tool arguments and empty output produce errors. Logs include model, transport, duration and errors, not full prompts.

## Runtime Files

- `install/state/`: cached selection, ignored by Git.
- `install/logs/`: gateway output and errors, ignored by Git.
- Windows Codex home: `%LOCALAPPDATA%\\lmsc\\c`.
- macOS: `~/.lmsc/c`.
- Linux: `$XDG_STATE_HOME/lmsc/c`, defaulting to `~/.local/state/lmsc/c`.

`LMSTUDIO_CODEX_HOME` overrides the Codex home. Keep it short and local. It contains conversation history and potentially user configuration; do not publish it.

## Upstream Documentation

- [Codex custom providers](https://developers.openai.com/codex/config-advanced)
- [LM Studio Codex integration](https://lmstudio.ai/docs/integrations/codex)
- [LM Studio Responses endpoint](https://lmstudio.ai/docs/developer/openai-compat/responses)
