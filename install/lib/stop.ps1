$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

try {
    $pidFile = Join-Path $script:LogDir "gateway.pid"
    Stop-GatewayOnPort
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Ok "LM Studio Codex gateway stopped."
} catch {
    Write-Host ""
    Write-Host "[lm-studio] Stop failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
