$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Initialize-LmStudioCodexState
$selected = Get-SelectedModelState
$health = Get-GatewayHealth
$missing = @(Get-MissingDependencyMessages)

Write-Host "Install root: $script:InstallRoot"
Write-Host "Codex home:   $script:CodexHome"
if ($missing.Count -eq 0) {
    Write-Host "Dependencies: OK"
} else {
    Write-Host "Dependencies: missing $($missing.Name -join ', ')"
    foreach ($item in $missing) {
        Write-Host "  - $($item.Fix)"
    }
}
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
