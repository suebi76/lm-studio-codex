param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $CodexArgs = @()
)
$ErrorActionPreference = "Stop"
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
. (Join-Path $PSScriptRoot "common.ps1")
try {
    if ($env:LMSTUDIO_CODEX_ARGS_JSON) {
        $CodexArgs = [string[]]($env:LMSTUDIO_CODEX_ARGS_JSON | ConvertFrom-Json)
        Remove-Item Env:LMSTUDIO_CODEX_ARGS_JSON
    }
    if ($CodexArgs.Count -eq 1 -and $CodexArgs[0] -in @("--help", "-h", "help")) {
        & node (Join-Path $PSScriptRoot "run-codex.js") --help
        exit $LASTEXITCODE
    }
    Write-Info "Starting LM Studio Codex CLI setup..."
    Initialize-LmStudioCodexState
    Assert-Dependencies
    Ensure-LmStudioServer
    $selectedModel = Select-LmStudioModel
    Ensure-Gateway $selectedModel
    $env:CODEX_HOME = $script:CodexHome
    $env:LMSTUDIO_CODEX_CONTEXT = [string] $selectedModel.contextLength
    Write-Ok "Using LM Studio model: $($selectedModel.identifier)"
    Write-Info "Working directory: $(Get-Location)"
    $env:LMSTUDIO_CODEX_ARGS_JSON = ConvertTo-Json -InputObject @($CodexArgs) -Compress
    & node (Join-Path $PSScriptRoot "run-codex.js")
    exit $LASTEXITCODE
} catch {
    Write-Host "[lm-studio] Startup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
