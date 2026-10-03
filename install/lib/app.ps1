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
Write-Host "Gateway is ready for LM Studio model: $($selectedModel.identifier)"
Write-Host "Opening ChatGPT/Codex desktop app. If it was already open, start a new local Codex session after this."
& codex app
