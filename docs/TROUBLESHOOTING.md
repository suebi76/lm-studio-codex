# Troubleshooting

## `lm-studio` is not recognized

Open a new terminal after running the installer. VS Code terminals keep the old `PATH` until reopened.

Run the installer again if needed:

```powershell
.\install\install.ps1
```

## `node` is missing

Install Node.js LTS:

```powershell
winget install OpenJS.NodeJS.LTS
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

## Qwen reports `System message must be at the beginning`

The direct LM Studio Responses route can trigger this on some Qwen templates. Use `lm-studio` so Codex goes through this project's gateway. The gateway moves system/developer text to the beginning before sending the chat request to LM Studio.

## Codex warnings about unknown model metadata

This is expected for local LM Studio model IDs. Codex uses fallback metadata. The gateway still routes requests to the loaded model.
