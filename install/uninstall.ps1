$ErrorActionPreference = "Stop"

$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $InstallRoot "bin"
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathParts = @($UserPath -split ";" | Where-Object { $_ -and ($_ -ne $BinDir) })
[Environment]::SetEnvironmentVariable("Path", ($PathParts -join ";"), "User")

$ShimDir = Join-Path $env:APPDATA "npm"
$commands = @("lm-studio", "lm-studio-doctor", "lm-studio-model", "lm-studio-status", "lm-studio-stop", "lm-studio-app")
foreach ($command in $commands) {
    $ps1Shim = Join-Path $ShimDir "$command.ps1"
    if ((Test-Path -LiteralPath $ps1Shim) -and (Get-Content -LiteralPath $ps1Shim -Raw).Contains($BinDir.Replace("'", "''"))) {
        Remove-Item -LiteralPath $ps1Shim -Force
        $cmdShim = Join-Path $ShimDir "$command.cmd"
        if ((Test-Path -LiteralPath $cmdShim) -and (Get-Content -LiteralPath $cmdShim -Raw) -match 'LM Studio Codex|install[\\/]bin[\\/]lm-studio') {
            Remove-Item -LiteralPath $cmdShim -Force
        }
    }
}

Write-Host "Removed LM Studio Codex global commands."
