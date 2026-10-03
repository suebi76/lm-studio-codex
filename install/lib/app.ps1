$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path $PSScriptRoot "common.ps1")

try {
    Initialize-LmStudioCodexState
    Assert-Dependencies
    Ensure-LmStudioServer
    $selectedModel = Select-LmStudioModel
    Ensure-Gateway $selectedModel

    $env:CODEX_HOME = $script:CodexHome
    Write-Ok "Gateway is ready for LM Studio model: $($selectedModel.identifier)"
    Write-Info "Opening ChatGPT/Codex desktop app. If it was already open, start a new local Codex session after this."
    & codex app
    exit $LASTEXITCODE
} catch {
    Write-Host ""
    Write-Host "[lm-studio] Desktop app startup failed." -ForegroundColor Red
    exit 1
}
