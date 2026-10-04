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
    Write-Host "Last selected (cached): $($selected.id)"
} else {
    Write-Host "Selected:     none"
}
if ($health) {
    Write-Host "Gateway:      running on port $($health.port)"
    Write-Host "Transport:    $($health.transport)"
    try {
        $ready = Invoke-RestMethod -Uri "http://127.0.0.1:18123/ready" -TimeoutSec 7
        Write-Host "Live model:   $($ready.model)"
    } catch { Write-Warn "Gateway is alive, but LM Studio/model is not ready: $($_.Exception.Message)" }
} else {
    Write-Host "Gateway:      not running"
}
