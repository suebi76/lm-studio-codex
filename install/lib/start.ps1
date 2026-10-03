param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $CodexArgs
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-LmStudioCodexState
Ensure-LmStudioServer
$selectedModel = Select-LmStudioModel
Ensure-Gateway $selectedModel

$env:CODEX_HOME = $script:CodexHome
Write-Host "Using LM Studio model: $($selectedModel.identifier)"
Write-Host "Starting Codex in: $(Get-Location)"

if ($CodexArgs.Count -gt 0) {
    & codex @CodexArgs
} else {
    & codex
}
exit $LASTEXITCODE
