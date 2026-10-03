$ErrorActionPreference = "Stop"

$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $InstallRoot "bin"
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathParts = @($UserPath -split ";" | Where-Object { $_ -and ($_ -ne $BinDir) })
[Environment]::SetEnvironmentVariable("Path", ($PathParts -join ";"), "User")

$ShimDir = Join-Path $env:APPDATA "npm"
$commands = @("lm-studio", "lm-studio-model", "lm-studio-status", "lm-studio-stop", "lm-studio-app")
foreach ($command in $commands) {
    Remove-Item -LiteralPath (Join-Path $ShimDir "$command.ps1") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $ShimDir "$command.cmd") -Force -ErrorAction SilentlyContinue
}

Write-Host "Removed LM Studio Codex global commands."
