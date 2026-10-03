# Troubleshooting

## `lm-studio` is not recognized

Open a new terminal after running the installer. VS Code terminals keep the old `PATH` until reopened.

Run the installer again if needed:

```powershell
.\install\install.ps1
```

On macOS/Linux:

```bash
./install/install.sh
```

If the installer added `~/.local/bin` to your shell profile, open a new terminal or run `source ~/.zshrc` / `source ~/.bashrc`.

## `node` is missing

Install Node.js LTS:

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

Then open a new terminal.

## `codex` is missing

After Node.js is installed:

```powershell
npm install -g @openai/codex
```

Then open a new terminal.

## `lms` is missing

Install LM Studio, open it once, and enable or install the LM Studio CLI from LM Studio's developer tools.

On macOS/Linux, if LM Studio supports it on your install, you can also try:

```bash
npx lmstudio install-cli
```

Check:

```powershell
lms ps --json
```

## LM Studio server is not reachable

The helper tries to start the server with:

```powershell
lms server start
```

If it still fails, open LM Studio and enable the local server. The expected URL is:

```text
http://127.0.0.1:1234/v1/models
```

## No model is loaded

Open LM Studio and load one chat/instruct model. Then run:

```powershell
lm-studio
```

## More than one model is loaded

Unload all but one LLM in LM Studio. Then run:

```powershell
lm-studio
```

## Gateway did not start

Run:

```powershell
lm-studio-stop
lm-studio-status
```

Then retry:

```powershell
lm-studio
```

Gateway logs are stored in:

```text
install/logs/
```

## `path must be shorter than SUN_LEN`

This is a Codex app-server daemon socket path limit, not an LM Studio model problem. It can happen when the portable install lives under a long folder such as OneDrive.

Current versions of `lm-studio` start Codex with `--no-daemon` by default and use a short OS-local Codex runtime path to avoid this.

If you still see this error:

```powershell
git pull
lm-studio-stop
lm-studio
```

If you installed from a release zip, download the newest release and replace the old folder.

Only force daemon mode if you intentionally want it:

```powershell
$env:LMSTUDIO_CODEX_USE_DAEMON = "1"
lm-studio
```

## Codex plugin sync reports `Filename too long`

This is another path-length symptom from Codex writing internal plugin/cache files under a long `CODEX_HOME`.

Current versions use a short default runtime path:

- Windows: `%LOCALAPPDATA%\lmsc\c`
- macOS: `~/.lmsc/c`
- Linux: `$XDG_STATE_HOME/lmsc/c` or `~/.local/state/lmsc/c`

If you still see this on Windows, choose an even shorter path:

```powershell
$env:LMSTUDIO_CODEX_HOME = "C:\lmsc\c"
lm-studio
```

On macOS/Linux:

```bash
export LMSTUDIO_CODEX_USE_DAEMON=1
lm-studio
```

## Qwen reports `System message must be at the beginning`

The direct LM Studio Responses route can trigger this on some Qwen templates. Use `lm-studio` so Codex goes through this project's gateway. The gateway moves system/developer text to the beginning before sending the chat request to LM Studio.

## Codex warnings about unknown model metadata

This is expected for local LM Studio model IDs. Codex uses fallback metadata. The gateway still routes requests to the loaded model.

## `lm-studio-doctor` warns about tool calls

The model can still be useful, but it may be unreliable for longer Coding-Agent workflows. Try a coding/agent model family such as Qwen Coder, DeepSeek Coder/V3-style models, Kimi K2/K-code style models, Devstral, or Codestral.

If a model passes text and JSON but fails tool calls, keep tasks small and review every file change carefully.

## `lm-studio-doctor` times out on the text check

The setup is reachable, but the loaded model did not produce a basic response fast enough for agent work. Try:

- a smaller quantization
- fewer background LM Studio tasks
- a coding model that fits your VRAM/RAM more comfortably
- raising the Doctor timeout for testing:

```powershell
$env:LMSTUDIO_DOCTOR_TIMEOUT_SEC = "90"
lm-studio-doctor
```

If the timeout only happens with one model, the gateway is probably fine and that model/build is not a good fit for responsive Coding-Agent sessions on the current machine.
