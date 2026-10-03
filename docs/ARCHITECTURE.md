# Architecture

Codex CLI expects a Responses-compatible model provider. LM Studio exposes an OpenAI-compatible chat endpoint. This project places a small local gateway between them.

```text
VS Code terminal
      |
      v
lm-studio command
      |
      v
Codex CLI
      |
      v
Local Responses gateway
http://127.0.0.1:18123/v1/responses
      |
      v
LM Studio
http://127.0.0.1:1234/v1/chat/completions
      |
      v
Loaded local model
```

## Files

- `install/bin/` contains Windows command wrappers.
- `install/bin-unix/` contains macOS/Linux command wrappers.
- `install/lib/` contains PowerShell orchestration, shell orchestration, and the Node.js gateway.
- `install/templates/config.toml` is copied into the short Codex runtime path as the Codex config.
- `install/state/` is runtime state and is ignored by Git.
- `install/logs/` is runtime logging and is ignored by Git.

## Gateway

The gateway:

- implements the minimal Responses API surface Codex needs
- converts Responses input into chat messages
- moves system/developer instructions to the beginning of the chat
- converts tool calls between Codex and LM Studio
- reads the selected model from runtime state before requests

`lm-studio-doctor` uses this same gateway instead of a separate test path. This makes the result representative for Codex CLI sessions.

The system/developer message handling is important for models whose chat template requires system text before user messages.

## Model Handling

The supported workflow is one loaded LLM in LM Studio.

The command stops when zero or multiple LLMs are loaded. This is intentional because a local coding agent should not silently pick the wrong model.

Windows and macOS/Linux share the same model state file, gateway, and Codex config template. The platform scripts only differ in how they install global commands and manage the gateway process.

`lm-studio` sets a short `CODEX_HOME`. This avoids Codex app-server Unix socket path limits and Windows plugin/cache path-length failures in portable folders.

## Ports

- LM Studio: `127.0.0.1:1234`
- Gateway: `127.0.0.1:18123`

If another process uses port `18123`, the helper attempts to stop an existing stale gateway. If the port still cannot be used, it prints a log path and repair steps.
