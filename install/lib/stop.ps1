$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

try {
    $pidFile = Join-Path $script:LogDir "gateway.pid"
    if (Test-Path -LiteralPath $pidFile) {
        $pidText = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1
        $gatewayPid = 0
        if ([int]::TryParse($pidText, [ref] $gatewayPid)) {
            Stop-Process -Id $gatewayPid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }

    Stop-GatewayOnPort
    Write-Ok "LM Studio Codex gateway stopped."
} catch {
    Write-Host ""
    Write-Host "[lm-studio] Stop failed." -ForegroundColor Red
    exit 1
}
