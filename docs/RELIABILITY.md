# Reliability Review

This review removes several accumulated workarounds and adds regression coverage. It does not claim that every possible model or future Codex version is supported.

| Failure source | Change | Verification |
| --- | --- | --- |
| Windows daemon/socket failures | Exec session loop; optional capability-checked daemonless TUI | Installed Codex 0.160.0 protocol test |
| Lost context between tasks | Resume the exact returned thread ID | Two-turn real Codex test |
| Captured/swallowed PowerShell output | Shared Node launcher, live JSON event rendering | Runner output/exit tests |
| Quoting through Windows shims | JSON environment handoff; no prompt interpolation into a shell | Launcher argument tests |
| Stale selected model | Query loaded instances for every request | Model-change test |
| Streams silently ending | Require valid termination; emit structured failures | Truncation, malformed frames, empty answer, token limit tests |
| CRLF/split UTF-8 parsing | Incremental SSE parser | Byte-by-byte parser test |
| Parallel calls and discarded tool choice | Preserve history and forward choice/schema | Protocol conversion tests |
| Unknown context/token accounting | Loaded context overrides and upstream usage forwarding | Context and usage tests |
| Unsupported cloud tools | Disable web search, plugins, multi-agent in local defaults | Real Codex request/tool test |
| Overly complex translation for compatible models | Optional native Responses forwarding | Native terminal/nonstream/truncation tests |
| Hung requests and oversized payloads | Total timeout, disconnect cancellation, 16 MiB limit | Timeout and body-limit tests |
| Killing foreign processes | Verify installation-owned process command; reject conflicts | Windows ownership test; Unix install test |
| Reusing outdated gateways | Source hash and settings checked on startup | Lifecycle code review; diagnostic health metadata |
| Unix global command resolves wrong directory | Resolve symlinks before locating scripts | Unix installer smoke test |
| Installer overwrites other commands | Ownership checks and meaningful exit status | Unix conflict/reinstall/uninstall test |
| Doctor false positives | Stream completion, tool-result round trip, final-answer file plus exit code | Shared runtime diagnostics |
| Misleading desktop launch path | Retired with an explicit CLI guidance message | Documentation/code review |

## Test Commands

Run `node --test tests/*.test.js`. Set `LMSC_TEST_CODEX=1` to include the installed Codex integration test. It uses a controlled local model server, runs an echo tool call and verifies session continuation. It is not a real-model benchmark.

Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/windows-smoke.ps1`.

macOS/Linux: `bash tests/unix-install.sh`. GitHub Actions runs a Windows/macOS/Linux matrix with Node.js 22.

## Remaining Limits

- Run `lm-studio-doctor` with the actual loaded model on each target machine. At the local review's final smoke check, no model was loaded; no real-model success is claimed.
- Chat mode deliberately supports text and function tools. Native Responses capabilities depend on LM Studio and the model. There is no automatic cross-transport retry.
- A smaller context window can invalidate an existing session's history. Start fresh when needed; the gateway does not silently discard it.
- A model cannot be replaced during an active generation. Switch between tasks.
- Installer package downloads and OS installers can still require user action. Missing dependencies and failed commands are reported; no installation success is fabricated.
- Codex version changes may alter CLI flags, tool types and protocol behavior. The opt-in integration test and Doctor are the upgrade checks.
- The gateway binds loopback and rejects browser-origin requests, but it is not an authentication boundary against other local processes. Keep it local.
