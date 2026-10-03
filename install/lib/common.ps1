$script:InstallRoot = Split-Path -Parent $PSScriptRoot
$script:StateDir = Join-Path $script:InstallRoot "state"
$script:LogDir = Join-Path $script:InstallRoot "logs"
$script:CodexHome = Join-Path $script:StateDir "codex-home"
$script:ModelStateFile = Join-Path $script:StateDir "selected-model.json"
$script:GatewayUrl = "http://127.0.0.1:18123/health"
$script:LmStudioBaseUrl = "http://127.0.0.1:1234"

function Initialize-LmStudioCodexState {
    New-Item -ItemType Directory -Force -Path $script:StateDir, $script:LogDir, $script:CodexHome | Out-Null
    $configPath = Join-Path $script:CodexHome "config.toml"
    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath (Join-Path $script:InstallRoot "templates\config.toml") -Destination $configPath -Force
    }
}

function Test-HttpOk {
    param([string] $Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
    } catch {
        return $false
    }
}

function Get-GatewayHealth {
    try {
        return Invoke-RestMethod -Uri $script:GatewayUrl -TimeoutSec 2
    } catch {
        return $null
    }
}

function Stop-GatewayOnPort {
    try {
        $connections = @(Get-NetTCPConnection -LocalPort 18123 -State Listen -ErrorAction SilentlyContinue)
        foreach ($connection in $connections) {
            if ($connection.OwningProcess) {
                Stop-Process -Id $connection.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
    }
}

function Ensure-LmStudioServer {
    if (-not (Get-Command lms -ErrorAction SilentlyContinue)) {
        throw "lms.exe was not found. Install LM Studio and enable the LM Studio CLI first."
    }

    if (-not (Test-HttpOk "$script:LmStudioBaseUrl/v1/models")) {
        Write-Host "Starting LM Studio local server..."
        & lms server start | Out-Host
    }
}

function Get-LoadedLmStudioModels {
    $loadedJson = & lms ps --json
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read loaded LM Studio models with 'lms ps --json'."
    }
    return @($loadedJson | ConvertFrom-Json | Where-Object { $_.type -eq "llm" })
}

function Get-SelectedModelState {
    if (-not (Test-Path -LiteralPath $script:ModelStateFile)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $script:ModelStateFile -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Save-SelectedModel {
    param($Model)
    $state = [ordered]@{
        id = $Model.identifier
        displayName = $Model.displayName
        modelKey = $Model.modelKey
        architecture = $Model.architecture
        selectedAt = (Get-Date).ToString("o")
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ModelStateFile -Encoding UTF8
}

function Select-LmStudioModel {
    param(
        [string] $RequestedModel,
        [switch] $ForcePrompt
    )

    $loadedModels = @(Get-LoadedLmStudioModels)
    if ($loadedModels.Count -eq 0) {
        throw "No LLM is loaded in LM Studio. Load a model in LM Studio, then run lm-studio again."
    }

    if ($RequestedModel) {
        $matches = @($loadedModels | Where-Object {
            $_.identifier -eq $RequestedModel -or
            $_.modelKey -eq $RequestedModel -or
            $_.displayName -eq $RequestedModel
        })
        if ($matches.Count -eq 1) {
            Save-SelectedModel $matches[0]
            return $matches[0]
        }
        throw "Requested model '$RequestedModel' is not loaded, or it matches more than one loaded model."
    }

    $current = Get-SelectedModelState
    if (-not $ForcePrompt -and $current -and $current.id) {
        $currentLoaded = @($loadedModels | Where-Object { $_.identifier -eq $current.id })
        if ($currentLoaded.Count -eq 1) {
            return $currentLoaded[0]
        }
    }

    if (-not $ForcePrompt -and $loadedModels.Count -eq 1) {
        Save-SelectedModel $loadedModels[0]
        return $loadedModels[0]
    }

    Write-Host "Loaded LM Studio models:"
    for ($i = 0; $i -lt $loadedModels.Count; $i++) {
        $n = $i + 1
        Write-Host "[$n] $($loadedModels[$i].identifier) - $($loadedModels[$i].displayName)"
    }

    do {
        $choice = Read-Host "Use which model number for Codex?"
        $parsed = 0
        $valid = [int]::TryParse($choice, [ref] $parsed)
    } while (-not $valid -or $parsed -lt 1 -or $parsed -gt $loadedModels.Count)

    $selected = $loadedModels[$parsed - 1]
    Save-SelectedModel $selected
    return $selected
}

function Ensure-Gateway {
    param($SelectedModel)

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw "node.exe was not found. Install Node.js or use the Node.js bundled with your tooling."
    }

    $health = Get-GatewayHealth
    $expectedStateFile = (Resolve-Path -LiteralPath $script:ModelStateFile).Path
    if ($health -and ($health.gateway -ne "lm-studio-codex-gateway" -or $health.stateFile -ne $expectedStateFile)) {
        Write-Host "Restarting gateway because another process is using the Codex LM Studio port..."
        Stop-GatewayOnPort
        Start-Sleep -Milliseconds 500
        $health = Get-GatewayHealth
    }

    if ($health) {
        return
    }

    $gatewayScript = Join-Path $script:InstallRoot "lib\lmstudio-responses-gateway.js"
    $stdoutLog = Join-Path $script:LogDir "gateway.out.log"
    $stderrLog = Join-Path $script:LogDir "gateway.err.log"
    $pidFile = Join-Path $script:LogDir "gateway.pid"

    $env:LMSTUDIO_BASE_URL = $script:LmStudioBaseUrl
    $env:LMSTUDIO_CODEX_MODEL_STATE_FILE = $script:ModelStateFile

    Write-Host "Starting local Codex <-> LM Studio gateway..."
    $process = Start-Process -FilePath "node" `
        -ArgumentList @("`"$gatewayScript`"") `
        -WorkingDirectory $script:InstallRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru
    Set-Content -LiteralPath $pidFile -Value $process.Id

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 300
        if (Test-HttpOk $script:GatewayUrl) {
            $ready = $true
            break
        }
    }

    if (-not $ready) {
        throw "The local gateway did not start. See $stderrLog"
    }
}
