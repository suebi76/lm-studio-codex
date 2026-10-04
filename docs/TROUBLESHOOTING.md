# Troubleshooting

Start with `lm-studio-status`, then `lm-studio-doctor`. Gateway logs are in `install/logs/gateway.out.log` and `gateway.err.log`.

## No Global Command

Run the installer again. Restart VS Code completely if a new terminal still inherits the old PATH. Keep the installed folder at its original location, or rerun installation after moving it. Unix installs use `~/.local/bin`; symlinks now resolve the actual installation path.

## Missing Dependencies

Use Node.js 22 or newer, the official Codex CLI, and LM Studio with its lms CLI enabled. Install Codex with `npm install -g @openai/codex`. Open LM Studio once and follow its CLI setup instructions. Check `node --version`, `codex --version`, and `lms ps --json`.

The installer returns a nonzero exit code if required commands remain missing. Optional Node/Codex installation failures remain visible. Some Linux package repositories provide an older Node version; check the installed version rather than assuming it is sufficient.

## Endpoint Selection

Enable LM Studio's OpenAI-compatible local server. Default chat mode uses `/v1/chat/completions`; native responses mode uses `/v1/responses`. Model discovery also requires the native `/api/v1/models` endpoint. Update LM Studio if that catalog is unavailable. The gateway does not use an OpenAI cloud API key.

If the server is unavailable the helper tries `lms server start`. lms operations time out after 45 seconds with instructions. A custom server URL must match the server where your model is loaded.

## No Model or Model Changed

Load exactly one chat/instruct LLM. The next request discovers it automatically. Change models while no task is generating. After switching to a smaller context window use `:new` if the old history no longer fits. Reloading the model does not fix Codex socket or protocol errors.

## Working for Less Than a Second, No Answer

This symptom alone does not identify a model failure. Inspect whether `request.started` appears in gateway logs. If not, Codex has not reached the model. The default exec loop avoids the interactive daemon path and explicitly reports turns without an answer.

Try `lm-studio "Reply exactly OK"`. The native interface remains available via `lm-studio --tui`.

## Socket or Long-Path Errors

Keep the default short Codex home outside OneDrive. The exec loop does not rely on the interactive daemon. TUI uses `--no-daemon` only when the installed version supports it. The old daemon environment variables are no longer used.

## Stream Closed Before Completion

Current gateway versions report the upstream cause instead of silently closing a partial answer. Check for context overflow, exhausted output tokens, malformed tool arguments, model unloads or timeout messages. Do not repeatedly retry an editing task without checking what already changed.

The gateway stops upstream work when its client disconnects. It does not silently replay a partial generation on another transport.

## System Message Must Be at the Beginning

Use `LMSTUDIO_CODEX_TRANSPORT=chat`; this mode groups system/developer instructions at the beginning. Native responses mode delegates template handling to LM Studio.

## Model Metadata and Context

Codex may warn that a local model has no known metadata. The launcher supplies the loaded context size when exposed by LM Studio, but cannot infer every capability from a model name. An 8192-token context may leave little room after Codex instructions and tool schemas. Increase it only within your hardware budget, or reduce the task/history.

## Tool or Image Errors

Chat mode supports function tools and text. Use native responses mode for images or custom tools, with a compatible model. Cloud web search, plugins and multi-agent tools are disabled by default. Tool-call or tool-result failures in Doctor mean this model/configuration has not passed the agent workflow test, even if plain chat works.

## Port Conflict

The helper never kills an arbitrary process on port 18123. Stop the other installation/service using its own controls. `lm-studio-stop` verifies this installation's process before stopping it. An updated gateway is restarted when its source revision or settings change.

## Slow Model

Doctor defaults to 300 seconds per check and prints progress every 15 seconds. Increase `LMSTUDIO_DOCTOR_TIMEOUT_SEC` if needed; the gateway's total request limit is controlled separately by `LMSTUDIO_CODEX_TIMEOUT_MS`. A timeout does not by itself prove the model is unsuitable. Check LM Studio's own logs and hardware usage.

Codex sends instructions and tool schemas even for a short greeting. In a measured Qwen run, roughly 6600 input tokens processed at about 50 tokens/second, exceeding a former 120-second smoke limit before generation began. Check LM Studio's prompt-processing progress before treating a quiet initial period as a disconnect.
