# Changelog

## Unreleased

- Changed `lm-studio` to use Codex's standard interactive daemon again now that the runtime path is short.
- Added `LMSTUDIO_CODEX_NO_DAEMON=1` as the explicit troubleshooting opt-out.
- Fixed Windows `lm-studio-doctor` Codex smoke test startup when `codex` resolves to a PowerShell/npm shim.
- Fixed Windows `lm-studio-doctor` success detection when Codex writes the expected marker but PowerShell reports an empty process exit code.
- Added Doctor warnings for high LM Studio context length, parallel requests, and non-idle model status.

## v0.3.0 - 2026-10-03

- Added `lm-studio-doctor` for model/setup health checks.
- Added model recommendation documentation.
- Changed `lm-studio` and Doctor Codex smoke tests to use `codex --no-daemon` by default, avoiding socket path errors in long portable install paths.
- Changed the default Codex runtime path to a short OS-local directory to avoid Windows plugin/cache path-length failures.
- Added a configurable Doctor gateway timeout via `LMSTUDIO_DOCTOR_TIMEOUT_SEC`.

## v0.2.0 - 2026-10-03

- Added macOS/Linux installer and shell command wrappers.

## v0.1.0 - 2026-10-03

- Added portable Windows installer under `install/`.
- Added global commands for Codex CLI through LM Studio.
- Added local Responses-to-chat gateway.
- Added checks for dependencies, LM Studio server state, loaded model count, and gateway health.
- Added documentation for installation, commands, architecture, and troubleshooting.
