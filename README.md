# LM Studio Codex

[![Validate](https://github.com/suebi76/lm-studio-codex/actions/workflows/validate.yml/badge.svg)](https://github.com/suebi76/lm-studio-codex/actions/workflows/validate.yml)

Run Codex CLI from any Windows, macOS, or Linux terminal while using the single model currently loaded in LM Studio.

This project provides a small local gateway between Codex' Responses API and LM Studio's OpenAI-compatible chat endpoint. It is designed for the practical workflow: open a project in VS Code, load one model in LM Studio, type `lm-studio` in the VS Code terminal, and work with Codex in that folder.

## What This Is

- A cross-platform helper for Codex CLI + LM Studio.
- A global `lm-studio` command for VS Code terminals, PowerShell, bash, and zsh.
- A local gateway that fixes model template issues such as Qwen's `System message must be at the beginning` error.
- A portable `install/` folder that can be cloned to another machine.
- A short OS-local Codex runtime path to avoid Windows path-length problems from internal plugin/cache files.

## What This Is Not

- It does not replace the normal ChatGPT chat model with LM Studio.
- It is not a separate LM Studio version of the ChatGPT Desktop app.
- It expects exactly one LLM loaded in LM Studio.

## Requirements

- Windows, macOS, or Linux
- LM Studio with the `lms` CLI enabled
- Node.js 22 or newer
- Codex CLI
- One chat/instruct model loaded in LM Studio

The installer checks these and prints concrete fixes if something is missing.

## Install

Clone the repository, then run the installer for your operating system.

Windows:

```powershell
.\install\install.ps1
```

Or double-click:

```text
install\install.bat
```

If Node.js or Codex CLI is missing, the installer can try to install those:

```powershell
.\install\install.ps1 -InstallMissing
```

macOS/Linux:

```bash
./install/install.sh
```

If Node.js or Codex CLI is missing, the installer can try to install what it can:

```bash
./install/install.sh --install-missing
```

LM Studio itself still needs to be installed and opened by the user, because model loading and the `lms` CLI are managed by LM Studio.

Open a new VS Code terminal after installation.

## Use

1. Open LM Studio.
2. Load exactly one chat/instruct model.
3. Open a project folder in VS Code.
4. Run:

```powershell
lm-studio
```

This starts a prompt loop in the current terminal folder. Each task runs through `codex exec`; subsequent tasks resume the exact same session. Codex can read, edit, and run commands in the project. Use `:new` to start fresh and `:exit` to quit. Tasks run with a workspace-write sandbox and no interactive approval prompts.

For one-off tasks:

```powershell
lm-studio "Analysiere dieses Projekt und fasse den aktuellen Stand zusammen"
```

`lm-studio` uses a short OS-local Codex runtime path. This avoids app-server socket and plugin-cache path errors in portable folders, especially under long OneDrive paths on Windows.

## Commands

```powershell
lm-studio          # start the stable Codex exec prompt loop through LM Studio
lm-studio "task"   # run one Codex task through LM Studio
lm-studio --tui    # optional/experimental Codex TUI, daemonless
lm-studio-doctor   # test the loaded model/setup for Coding-Agent workflows
lm-studio-status   # show install path, dependencies, selected model, gateway status
lm-studio-model    # verify/select the single loaded model
lm-studio-model -List
lm-studio-stop     # stop the local gateway
```

On macOS/Linux, use `lm-studio-model --list` instead of `-List`.

## Model Rule

Load exactly one LLM in LM Studio.

If no model is loaded, `lm-studio` stops and tells you to load one. If several LLMs are loaded, it stops and tells you to unload all but one. This keeps the gateway predictable.

To change models, finish the current task, unload the old model, and load the new one. The next request discovers it automatically; the terminal session can stay open. If the new model has less context capacity, use `:new` as needed.

The default gateway translates Chat Completions for strict model templates. An optional `LMSTUDIO_CODEX_TRANSPORT=responses` mode forwards to LM Studio's native Responses endpoint. See [Architecture](docs/ARCHITECTURE.md) for capabilities and limits. OpenAI-compatible endpoints must be enabled in LM Studio.

## Documentation

- [Install Guide](install/README.md)
- [Command Reference](docs/COMMANDS.md)
- [Model Recommendations](docs/MODEL_RECOMMENDATIONS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Reliability Review](docs/RELIABILITY.md)

## Status

Windows, macOS and Linux share the Node.js gateway, launcher and Doctor. CI covers protocol regressions on all three platforms; actual model/hardware compatibility still requires `lm-studio-doctor` on each machine. The native CLI protocol is tested locally with Codex 0.160.0. The desktop-app experiment is retired.

## License

MIT. See [LICENSE](LICENSE).
