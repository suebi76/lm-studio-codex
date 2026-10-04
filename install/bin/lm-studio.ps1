#!/usr/bin/env pwsh
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$previousArgs = $env:LMSTUDIO_CODEX_ARGS_JSON
try {
    $env:LMSTUDIO_CODEX_ARGS_JSON = ConvertTo-Json -InputObject @($args) -Compress
    & powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "lib\start.ps1")
    $code = $LASTEXITCODE
} finally { $env:LMSTUDIO_CODEX_ARGS_JSON = $previousArgs }
exit $code
