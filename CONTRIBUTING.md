# Contributing

Thanks for improving this project.

## Development Setup

1. Clone the repository on Windows.
2. Install LM Studio, Node.js, and Codex CLI.
3. Run:

```powershell
.\install\install.ps1
```

## Validation

Before opening a pull request, run:

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
