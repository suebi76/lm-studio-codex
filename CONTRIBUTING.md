# Contributing

Thanks for improving this project.

## Development Setup

1. Clone the repository on Windows, macOS, or Linux.
2. Install LM Studio, Node.js 22+, and Codex CLI.
3. Run:

```powershell
.\install\install.ps1
```

## Validation

Before opening a pull request, run:

```text
node --test tests/*.test.js
```

For the installed Codex integration test, set `LMSC_TEST_CODEX=1` before running the tests. It uses a mock local model server and an isolated temporary Codex home, executes an echo command, and verifies session continuation. It does not establish real-model quality. On Unix also run `bash tests/unix-install.sh` to test installation, symlink invocation, reinstallation, uninstall, and foreign-command protection.

With a real model loaded, run:

```powershell
lm-studio-status
lm-studio exec --skip-git-repo-check "Reply exactly: OK"
```

Also parse-check PowerShell files:

```powershell
$errors = @()
Get-ChildItem -Recurse -Filter *.ps1 install | ForEach-Object {
  $tokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
  if ($parseErrors) { $errors += $parseErrors }
}
if ($errors.Count) { $errors; exit 1 }
```

## Runtime Data

Do not commit:

- `install/state/`
- `install/logs/`
- `.codex-home/`
- `logs/`

These are ignored by Git.
