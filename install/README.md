# LM Studio Codex CLI for Windows

This folder contains a portable Windows setup for running Codex CLI against the model currently loaded in LM Studio.

## Requirements

- Windows
- LM Studio with the `lms` CLI enabled
- Codex CLI installed and available as `codex`
- Node.js available as `node`

## Install

Run this from PowerShell:

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

LM Studio still needs to be installed and opened by the user, because models and the `lms` CLI are managed by LM Studio itself.

Then open a new VS Code terminal.

## Use

In any project folder:

```powershell
lm-studio
```

This starts Codex CLI in the current folder and routes model requests through LM Studio.

## Multiple loaded models

If LM Studio has one LLM loaded, it is selected automatically. If several LLMs are loaded, run:

```powershell
lm-studio-model
```

To list loaded models:

```powershell
lm-studio-model -List
```

To select a loaded model by identifier:

```powershell
lm-studio-model "model-identifier"
```

## Switch model during a Codex session

Open a second terminal and run:

```powershell
lm-studio-model
```

The running gateway reads the selected model before each Codex request, so the next request in the active session uses the newly selected model.

## Status and stop

```powershell
lm-studio-status
lm-studio-stop
```

`lm-studio-status` shows:

- install root
- Codex home used by this setup
- missing dependencies
- selected model
- gateway status and active model

## What the commands check

Every start checks:

- `node` is available
- `codex` is available
- `lms` is available
- LM Studio server responds on `http://127.0.0.1:1234`
- at least one LLM is loaded in LM Studio
- the local gateway on port `18123` is running and belongs to this install

If any check fails, the command prints a concrete fix instead of failing silently.

## Typical fixes

If `node` is missing:

```powershell
winget install OpenJS.NodeJS.LTS
```

If `codex` is missing after Node.js is installed:

```powershell
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

These folders should not be committed.
