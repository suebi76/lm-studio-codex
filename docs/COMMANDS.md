# Commands

## Work in a Project

```text
lm-studio
lm-studio "Explain the project structure"
lm-studio exec --skip-git-repo-check "Explain the project structure"
lm-studio resume --last "Continue the previous task"
lm-studio --tui
lm-studio --help
```

The default loop continues the same Codex session. `:new` starts fresh, `:model` displays the current model, and `:exit` quits. Model selection refreshes automatically before requests. Help does not require a running LM Studio server.

The default loop and one-task mode use a workspace-write sandbox and no interactive approval prompts. Commands requiring additional permissions fail rather than escalating automatically. Native `exec`, `resume`, `fork`, and `review` arguments pass through; their behavior and flags follow your installed Codex version. `--codex` passes raw Codex arguments with the managed provider defaults.

`--tui` is the native interactive interface. On CLI versions with `--no-daemon`, the launcher enables it to avoid the observed Windows socket failures.

## Diagnostics

```text
lm-studio-status
lm-studio-model
lm-studio-doctor
lm-studio-stop
```

Windows lists loaded models with `lm-studio-model -List`; Unix uses `--list`.
Doctor tests streamed text, JSON, a tool call plus its result, and an actual Codex final answer. It does not certify long-running model reliability. To skip Codex, use `-SkipCodexSmoke` on Windows or `--skip-codex-smoke` on Unix.

Stop only terminates this installation's verified gateway; LM Studio remains running.

## Settings

| Variable | Default | Purpose |
| --- | --- | --- |
| LMSTUDIO_CODEX_HOME | Short OS-local path | Codex history/configuration |
| LMSTUDIO_BASE_URL | http://127.0.0.1:1234 | LM Studio server base URL |
| LMSTUDIO_CODEX_TRANSPORT | chat | chat translation or native responses |
| LMSTUDIO_CODEX_TIMEOUT_MS | 600000 | Maximum duration of one gateway request |
| LMSTUDIO_DOCTOR_TIMEOUT_SEC | 120 | Maximum duration of each diagnostic request |

PowerShell example:

```powershell
$env:LMSTUDIO_CODEX_TRANSPORT = "responses"
lm-studio-doctor
```

bash/zsh example:

```bash
export LMSTUDIO_CODEX_TRANSPORT=responses
lm-studio-doctor
```

Gateway settings are applied at the next helper startup. The public gateway port remains 18123. The old NO_DAEMON/USE_DAEMON environment overrides are obsolete.

## Desktop Command

`lm-studio-app` is retained only as a compatibility message. It does not turn the ChatGPT/Codex desktop app into an LM Studio client. Use the CLI from your VS Code terminal.
