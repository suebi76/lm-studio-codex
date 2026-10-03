# Command Reference

## `lm-studio`

Starts Codex CLI in the current terminal directory and routes model calls through LM Studio.

```powershell
lm-studio
```

You can pass Codex CLI arguments through:

```powershell
lm-studio exec --skip-git-repo-check "Reply exactly: OK"
```

What it does:

- checks `node`, `codex`, and `lms`
- starts the LM Studio local server if needed
- verifies exactly one LLM is loaded
- starts the local gateway on `127.0.0.1:18123`
- sets a short `CODEX_HOME`
- starts Codex

The short `CODEX_HOME` avoids app-server socket and plugin-cache path errors in portable installs. To override the runtime path, set `LMSTUDIO_CODEX_HOME`. To force no-daemon troubleshooting mode, set `LMSTUDIO_CODEX_NO_DAEMON=1` before running `lm-studio`.

## `lm-studio-status`

Shows diagnostics.

```powershell
lm-studio-status
```

It prints:

- install root
- Codex home
- dependency status
- selected loaded model
- gateway status

## `lm-studio-doctor`

Runs a practical health check for the loaded model and the local Codex workflow.

```powershell
lm-studio-doctor
```

On macOS/Linux:

```bash
lm-studio-doctor
```

It checks:

- dependencies and LM Studio server
- exactly one loaded LLM
- gateway health
- plain text response
- simple JSON response
- simple tool/function call response
- Codex CLI smoke test

To skip the Codex CLI smoke test:

```powershell
lm-studio-doctor -SkipCodexSmoke
```

On macOS/Linux:

```bash
lm-studio-doctor --skip-codex-smoke
```

Gateway runtime checks time out after 45 seconds by default. To give a very slow model more time:

```powershell
$env:LMSTUDIO_DOCTOR_TIMEOUT_SEC = "90"
lm-studio-doctor
```

On macOS/Linux:

```bash
LMSTUDIO_DOCTOR_TIMEOUT_SEC=90 lm-studio-doctor
```

## `lm-studio-model`

Checks the loaded LM Studio model.

```powershell
lm-studio-model
lm-studio-model -List
```

On macOS/Linux:

```bash
lm-studio-model --list
```

The tool expects one loaded LLM. If several are loaded, unload all but one in LM Studio.

## `lm-studio-stop`

Stops the local gateway.

```powershell
lm-studio-stop
```

LM Studio itself is not stopped.

## `lm-studio-app`

Experimental helper for the ChatGPT/Codex Desktop app.

```powershell
lm-studio-app
```

It starts the same gateway and opens the Desktop app through `codex app`. The CLI path is the supported path.

## Installers

Windows:

```powershell
.\install\install.ps1
.\install\uninstall.ps1
```

macOS/Linux:

```bash
./install/install.sh
./install/uninstall.sh
```
