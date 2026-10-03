param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $CodexArgs
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path $PSScriptRoot "common.ps1")

try {
    Write-Info "Starting LM Studio Codex CLI setup..."
    Initialize-LmStudioCodexState
    Assert-Dependencies
    Ensure-LmStudioServer
    $selectedModel = Select-LmStudioModel
    Ensure-Gateway $selectedModel

    $env:CODEX_HOME = $script:CodexHome
    Write-Ok "Using LM Studio model: $($selectedModel.identifier)"
    Write-Info "Starting Codex in: $(Get-Location)"

    $finalArgs = @()
    if ($env:LMSTUDIO_CODEX_NO_DAEMON -eq "1") {
        $finalArgs += "--no-daemon"
        Write-Warn "Running Codex with --no-daemon because LMSTUDIO_CODEX_NO_DAEMON=1 is set."
    } else {
        Write-Info "Running Codex with the standard interactive daemon. CODEX_HOME is short: $script:CodexHome"
    }
    $finalArgs += $CodexArgs

    & codex @finalArgs
    exit $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "[lm-studio] Startup failed." -ForegroundColor Red
    Write-Host "[lm-studio] Run 'lm-studio-status' for diagnostics after fixing the issue."
    exit 1
}
