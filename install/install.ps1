param(
    [switch] $InstallMissing
)

$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $InstallRoot "bin"

. (Join-Path $InstallRoot "lib\common.ps1")

Write-Info "Installing LM Studio Codex CLI helpers..."
Write-Info "Install root: $InstallRoot"

function Try-InstallMissingDependency {
    param([string] $Name)

    if ($Name -eq "Node.js") {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Info "Installing Node.js LTS with winget..."
            & winget install --id OpenJS.NodeJS.LTS --source winget --accept-package-agreements --accept-source-agreements
            return
        }
        Write-Warn "winget is not available. Install Node.js manually from https://nodejs.org"
        return
    }

    if ($Name -eq "Codex CLI") {
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Write-Info "Installing Codex CLI with npm..."
            & npm install -g @openai/codex
            return
        }
        Write-Warn "npm is not available. Install Node.js first, then run: npm install -g @openai/codex"
        return
    }

    if ($Name -eq "LM Studio CLI") {
        Write-Warn "Install LM Studio manually from https://lmstudio.ai, open it once, and enable/install the lms CLI."
    }
}

$missingBefore = @(Get-MissingDependencyMessages)
if ($missingBefore.Count -gt 0) {
    Write-Warn "Some dependencies are missing:"
    foreach ($item in $missingBefore) {
        Write-Host "  - $($item.Name): $($item.Fix)"
    }

    if ($InstallMissing) {
        foreach ($item in $missingBefore) {
            Try-InstallMissingDependency $item.Name
        }
    } else {
        Write-Info "Installer will still create commands. Run '.\install\install.ps1 -InstallMissing' to try installing Node/Codex automatically."
    }
} else {
    Write-Ok "All required commands are already available"
}

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathParts = @($UserPath -split ";" | Where-Object { $_ })

if ($PathParts -notcontains $BinDir) {
    $newPath = (($PathParts + $BinDir) -join ";")
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$env:Path;$BinDir"
    Write-Ok "Added to user PATH: $BinDir"
} else {
    Write-Ok "Already in user PATH: $BinDir"
}

$ShimDir = Join-Path $env:APPDATA "npm"
New-Item -ItemType Directory -Force -Path $ShimDir | Out-Null

$commands = @("lm-studio", "lm-studio-doctor", "lm-studio-model", "lm-studio-status", "lm-studio-stop", "lm-studio-app")
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

Write-Ok "Installed global commands:"
foreach ($command in $commands) {
    Write-Host "  $command"
}

$missingAfter = @(Get-MissingDependencyMessages)
if ($missingAfter.Count -gt 0) {
    Write-Host ""
    Write-Warn "Installation finished, but these dependencies still need attention:"
    foreach ($item in $missingAfter) {
        Write-Host "  - $($item.Name): $($item.Fix)"
    }
} else {
    Write-Ok "Preflight passed. You can open a VS Code terminal and run: lm-studio"
}

Write-Info "Open a new VS Code terminal if an existing terminal does not see the updated PATH."
