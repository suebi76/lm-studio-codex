$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Initialize-LmStudioCodexState
$selected = Get-SelectedModelState
$health = Get-GatewayHealth

Write-Host "Install root: $script:InstallRoot"
Write-Host "Codex home:   $script:CodexHome"
if ($selected) {
    Write-Host "Selected:     $($selected.id)"
} else {
    Write-Host "Selected:     none"
}
if ($health) {
    Write-Host "Gateway:      running on port $($health.port)"
    Write-Host "Gateway model:$($health.model)"
} else {
    Write-Host "Gateway:      not running"
}
