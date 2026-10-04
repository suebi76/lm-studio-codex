# Portable Install Folder

Keep this folder at a stable path. It contains everything specific to this project; dependencies are installed separately.

Requirements: Windows/macOS/Linux, Node.js 22+, official Codex CLI, LM Studio with lms CLI and OpenAI-compatible server endpoints, and exactly one loaded chat/instruct model.

## Windows

Run `install.bat`, or `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1` from this folder. Add `-InstallMissing` to try installing Node.js LTS and Codex. Missing dependencies return a failure code with repair instructions. The batch file pauses intentionally at the end so its result remains readable.

## macOS/Linux

Run `bash install.sh`. Add `--install-missing` to try available package installation methods. Enable lms in LM Studio itself. Reopen the terminal after installation; restart VS Code if it still inherits an old PATH.

## Use

In a project directory run `lm-studio`. Enter a task; follow-up tasks resume the same session. `:new` starts fresh; `:exit` exits. Run `lm-studio-doctor` after loading a new model.

Change models between tasks. The next request automatically uses the single loaded model. A smaller model context may require a fresh session.

`lm-studio --help` works without starting the server. `lm-studio --tui` opens the native CLI interface.

## State and Uninstall

Runtime logs and selection state stay in this folder's `logs/` and `state/` directories. Codex history is separate: Windows `%LOCALAPPDATA%\\lmsc\\c`, macOS `~/.lmsc/c`, Linux `~/.local/state/lmsc/c` (or XDG_STATE_HOME). Override with `LMSTUDIO_CODEX_HOME`. Do not publish runtime files.

Run `uninstall.ps1` or `bash uninstall.sh` to remove this installation's global commands. Conversation history is preserved. Reinstall after moving the folder.

See the repository's [commands](../docs/COMMANDS.md), [architecture](../docs/ARCHITECTURE.md), and [troubleshooting](../docs/TROUBLESHOOTING.md) for all settings.
