$ErrorActionPreference = "Stop"

$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $InstallRoot "bin"
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathParts = @($UserPath -split ";" | Where-Object { $_ })

if ($PathParts -notcontains $BinDir) {
    $newPath = (($PathParts + $BinDir) -join ";")
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$env:Path;$BinDir"
    Write-Host "Added to user PATH: $BinDir"
} else {
    Write-Host "Already in user PATH: $BinDir"
}

$ShimDir = Join-Path $env:APPDATA "npm"
New-Item -ItemType Directory -Force -Path $ShimDir | Out-Null

$commands = @("lm-studio", "lm-studio-model", "lm-studio-status", "lm-studio-stop", "lm-studio-app")
foreach ($command in $commands) {
    $ps1Target = Join-Path $BinDir "$command.ps1"
    $cmdTarget = Join-Path $BinDir "$command.cmd"
    $ps1Shim = Join-Path $ShimDir "$command.ps1"
    $cmdShim = Join-Path $ShimDir "$command.cmd"

    Set-Content -LiteralPath $ps1Shim -Encoding UTF8 -Value @"
#!/usr/bin/env pwsh
& "$ps1Target" @args
exit `$LASTEXITCODE
"@

    Set-Content -LiteralPath $cmdShim -Encoding ASCII -Value @"
@echo off
powershell -NoLogo -ExecutionPolicy Bypass -File "$ps1Target" %*
"@
}

Write-Host "Installed global commands:"
foreach ($command in $commands) {
    Write-Host "  $command"
}
Write-Host "Open a new VS Code terminal if an existing terminal does not see the updated PATH."
