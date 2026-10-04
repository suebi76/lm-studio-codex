param([switch] $SkipCodexSmoke)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
try {
    Initialize-LmStudioCodexState
    Assert-Dependencies
    Ensure-LmStudioServer
    $selected = Select-LmStudioModel
    Ensure-Gateway $selected
    $env:CODEX_HOME = $script:CodexHome
    $env:LMSTUDIO_CODEX_CONTEXT = [string]$selected.contextLength
    if ($selected.contextLength -and $selected.contextLength -lt 16384) {
        Write-Warn "Loaded context is $($selected.contextLength) tokens. Codex instructions and tools may leave little room for project files."
    }
    $doctorArgs = @()
    if ($SkipCodexSmoke) { $doctorArgs += "--skip-codex-smoke" }
    & node (Join-Path $PSScriptRoot "doctor-runtime.js") @doctorArgs
    exit $LASTEXITCODE
} catch {
    Write-Host "[lm-studio] Doctor failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
