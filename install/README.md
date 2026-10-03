# LM Studio Codex CLI

This folder contains a portable setup for running Codex CLI against the model currently loaded in LM Studio.

## Requirements

- Windows, macOS, or Linux
- LM Studio with the `lms` CLI enabled
- Codex CLI installed and available as `codex`
- Node.js available as `node`

## Install

Windows PowerShell:

```powershell
.\install\install.ps1
```

Or double-click:

```text
install\install.bat
```

The installer prints every relevant step. If Node.js or Codex CLI is missing, you can ask it to try installing those:

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

LM Studio still needs to be installed and opened by the user, because models and the `lms` CLI are managed by LM Studio itself.

Then open a new VS Code terminal.

## Uninstall

Windows:

```powershell
.\install\uninstall.ps1
```

macOS/Linux:

```bash
./install/uninstall.sh
```

## Use

In any project folder:

```powershell
lm-studio
```

This starts Codex CLI in the current folder and routes model requests through LM Studio.

`lm-studio` starts Codex with `--no-daemon` by default and uses a short OS-local Codex runtime path. This avoids app-server socket and plugin-cache path errors in portable folders, especially under long OneDrive paths on Windows.

Default Codex runtime paths:

- Windows: `%LOCALAPPDATA%\lmsc\c`
- macOS: `~/.lmsc/c`
- Linux: `$XDG_STATE_HOME/lmsc/c` or `~/.local/state/lmsc/c`

To override the Codex runtime path:

```powershell
$env:LMSTUDIO_CODEX_HOME = "C:\lmsc\c"
```

On macOS/Linux:

```bash
export LMSTUDIO_CODEX_HOME="$HOME/.lmsc/c"
```

To force the Codex daemon anyway, set:

```powershell
$env:LMSTUDIO_CODEX_USE_DAEMON = "1"
```

On macOS/Linux:

```bash
export LMSTUDIO_CODEX_USE_DAEMON=1
```

Before using a new model for longer agent work, run:

```powershell
lm-studio-doctor
```

## Loaded model

Load exactly one chat/instruct LLM in LM Studio. `lm-studio` automatically uses that loaded model.

To show the currently loaded model:

```powershell
lm-studio-model -List
```

On macOS/Linux:

```bash
lm-studio-model --list
```

If more than one LLM is loaded, the command stops and asks you to unload all but one model in LM Studio. This keeps the gateway predictable.

## Change model

To change models:

1. Stop or finish the current Codex run.
2. In LM Studio, unload the old model.
3. Load the new model.
4. Run `lm-studio` again.

## Status and stop

```powershell
lm-studio-status
lm-studio-stop
lm-studio-doctor
```

`lm-studio-status` shows:

- install root
- Codex home used by this setup
- missing dependencies
- loaded model selected for Codex
- gateway status and active model

`lm-studio-doctor` checks the same setup plus model behavior for text output, JSON output, tool-call output, and a small Codex CLI smoke test.

Doctor gateway checks time out after 45 seconds by default. For slow models:

```powershell
$env:LMSTUDIO_DOCTOR_TIMEOUT_SEC = "90"
lm-studio-doctor
```

## What the commands check

Every start checks:

- `node` is available
- `codex` is available
- `lms` is available
- LM Studio server responds on `http://127.0.0.1:1234`
- at least one LLM is loaded in LM Studio
- no more than one LLM is loaded in LM Studio
- the local gateway on port `18123` is running and belongs to this install

If any check fails, the command prints a concrete fix instead of failing silently.

## Typical fixes

If `node` is missing:

```powershell
winget install OpenJS.NodeJS.LTS
```

On macOS with Homebrew:

```bash
brew install node
```

On Linux, use your distro package manager, for example:

```bash
sudo apt install nodejs npm
```

If `codex` is missing after Node.js is installed:

```bash
npm install -g @openai/codex
```

If `lms` is missing, install/open LM Studio and enable the LM Studio CLI from LM Studio's developer tools.

If no model is loaded, open LM Studio and load a chat/instruct model before running `lm-studio`.

## Optional desktop app experiment

```powershell
lm-studio-app
```

The CLI path is the reliable path. The desktop app command starts the same gateway and opens the ChatGPT/Codex desktop app for testing.

## Runtime state

The installer stores runtime state under:

```text
install/state/
install/logs/
```

These folders should not be committed. The Codex runtime cache is stored in the short OS-local path shown above.
