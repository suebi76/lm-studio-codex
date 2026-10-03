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

    if ($CodexArgs.Count -gt 0) {
        & codex @CodexArgs
    } else {
        & codex
    }
    exit $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "[lm-studio] Startup failed." -ForegroundColor Red
    Write-Host "[lm-studio] Run 'lm-studio-status' for diagnostics after fixing the issue."
    exit 1
}
