#!/usr/bin/env pwsh
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& powershell -NoLogo -ExecutionPolicy Bypass -File (Join-Path $root "lib\start.ps1") @args
exit $LASTEXITCODE
