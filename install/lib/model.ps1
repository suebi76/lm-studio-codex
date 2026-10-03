param(
    [string] $Model,
    [switch] $List
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-LmStudioCodexState
Ensure-LmStudioServer

if ($List) {
    $loaded = @(Get-LoadedLmStudioModels)
    if ($loaded.Count -eq 0) {
        Write-Host "No LLM is loaded in LM Studio."
        exit 1
    }
    $current = Get-SelectedModelState
    foreach ($item in $loaded) {
        $marker = if ($current -and $current.id -eq $item.identifier) { "*" } else { " " }
        Write-Host "$marker $($item.identifier) - $($item.displayName)"
    }
    exit 0
}

$selected = Select-LmStudioModel -RequestedModel $Model -ForcePrompt:([string]::IsNullOrWhiteSpace($Model))
Write-Host "Selected LM Studio model for Codex: $($selected.identifier)"
$health = Get-GatewayHealth
if ($health) {
    Write-Host "The running gateway will use this model on the next Codex request."
}
