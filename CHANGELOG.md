# Changelog

## Unreleased

- Enable Exa MCP web search and page reading automatically in all managed Codex launch modes, with explicit offline opt-out and optional environment-backed API key.
- Translate namespaced MCP functions through the chat gateway, preserving tool identity, history and forced tool choice.
- Show MCP calls and failures in the terminal; include MCP connection/catalog checks in Doctor.
- Add namespace, MCP diagnostic and installed-Codex tool round-trip regression coverage.
- Align Codex stream idle timeout with the gateway limit for slow local prompt processing.

## v0.4.0 - 2026-10-04

- Shared Node.js session launcher with explicit session resumption, visible output/progress, exit codes and empty-answer detection.
- Discover the live model on each request; retain sessions across model changes and pass loaded context sizes when available.
- Harden streaming: CRLF and split UTF-8, completion validation, tool arguments, usage, structured errors, cancellation and bounded requests.
- Preserve parallel tool history, tool choice and JSON output schemas. Reject unsupported capabilities explicitly.
- Add optional native Responses forwarding. Disable unsupported cloud web search, plugins and multi-agent tools in the local default profile.
- Separate gateway liveness from model readiness; verify process ownership and restart after code/settings changes without killing foreign port owners.
- Fix Unix global symlinks, detach gateway lifecycle, protect unrelated installed commands and report incomplete installations with nonzero status.
- Replace duplicated Doctors with shared streamed checks, a tool-result round trip and final-answer verification through the actual Codex CLI.
- Require Node.js 22+, bound lms operations, and remove misleading model-family guarantees and desktop-app launch claims.
- Add protocol/session regression tests and a three-platform CI matrix, plus an opt-in real Codex integration test.
- Preserve Windows argument quoting and empty argument lists across PowerShell versions.
- Allow 300 seconds per Doctor check, show ongoing progress, and pin automatic Codex installation to tested 0.160.0.

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
