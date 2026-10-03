$script:InstallRoot = Split-Path -Parent $PSScriptRoot
$script:StateDir = Join-Path $script:InstallRoot "state"
$script:LogDir = Join-Path $script:InstallRoot "logs"
if ($env:LMSTUDIO_CODEX_HOME) {
    $script:CodexHome = $env:LMSTUDIO_CODEX_HOME
} elseif ($env:LOCALAPPDATA) {
    $script:CodexHome = Join-Path $env:LOCALAPPDATA "lmsc\c"
} else {
    $script:CodexHome = Join-Path $script:StateDir "codex-home"
}
$script:ModelStateFile = Join-Path $script:StateDir "selected-model.json"
$script:GatewayUrl = "http://127.0.0.1:18123/health"
$script:LmStudioBaseUrl = "http://127.0.0.1:1234"

function Write-Info {
    param([string] $Message)
    Write-Host "[lm-studio] $Message"
}

function Write-Ok {
    param([string] $Message)
    Write-Host "[lm-studio] OK: $Message"
}

function Write-Warn {
    param([string] $Message)
    Write-Host "[lm-studio] WARNING: $Message" -ForegroundColor Yellow
}

function Stop-WithHelp {
    param(
        [string] $Message,
        [string[]] $Fix
    )

    Write-Host ""
    Write-Host "[lm-studio] ERROR: $Message" -ForegroundColor Red
    if ($Fix -and $Fix.Count -gt 0) {
        Write-Host ""
        Write-Host "What to do:"
        foreach ($line in $Fix) {
            Write-Host "  - $line"
        }
    }
    throw $Message
}

function Initialize-LmStudioCodexState {
    New-Item -ItemType Directory -Force -Path $script:StateDir, $script:LogDir, $script:CodexHome | Out-Null
    $configPath = Join-Path $script:CodexHome "config.toml"
    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath (Join-Path $script:InstallRoot "templates\config.toml") -Destination $configPath -Force
    }
}

function Test-HttpOk {
    param(
        [string] $Url,
        [int] $TimeoutSec = 2
    )
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
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

function Test-CommandAvailable {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-MissingDependencyMessages {
    $missing = @()

    if (-not (Test-CommandAvailable "node")) {
        $missing += [pscustomobject]@{
            Name = "Node.js"
            Fix = "Install Node.js LTS from https://nodejs.org or run: winget install OpenJS.NodeJS.LTS"
        }
    }

    if (-not (Test-CommandAvailable "codex")) {
        $missing += [pscustomobject]@{
            Name = "Codex CLI"
            Fix = "Install Codex CLI from https://developers.openai.com/codex or run after Node.js is installed: npm install -g @openai/codex"
        }
    }

    if (-not (Test-CommandAvailable "lms")) {
        $missing += [pscustomobject]@{
            Name = "LM Studio CLI"
            Fix = "Install LM Studio from https://lmstudio.ai, open it once, and enable/install the lms CLI from LM Studio's developer tools."
        }
    }

    return $missing
}

function Assert-Dependencies {
    $missing = @(Get-MissingDependencyMessages)
    if ($missing.Count -eq 0) {
        Write-Ok "Required commands found: node, codex, lms"
        return
    }

    $fixes = @()
    foreach ($item in $missing) {
        $fixes += "$($item.Name): $($item.Fix)"
    }

    Stop-WithHelp "Missing required dependency: $($missing.Name -join ', ')" $fixes
}

function Ensure-LmStudioServer {
    if (-not (Test-HttpOk "$script:LmStudioBaseUrl/v1/models")) {
        Write-Info "LM Studio server is not responding on $script:LmStudioBaseUrl. Starting it with lms..."
        & lms server start | Out-Host

        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-HttpOk "$script:LmStudioBaseUrl/v1/models" 2) {
                $ready = $true
                break
            }
        }

        if (-not $ready) {
            Stop-WithHelp "LM Studio server did not become reachable at $script:LmStudioBaseUrl." @(
                "Open LM Studio manually.",
                "Enable the local server in LM Studio.",
                "Confirm that http://127.0.0.1:1234/v1/models opens or returns JSON."
            )
        }
    } else {
        Write-Ok "LM Studio server is reachable at $script:LmStudioBaseUrl"
    }
}

function Get-LoadedLmStudioModels {
    try {
        $loadedJson = & lms ps --json
    } catch {
        Stop-WithHelp "Could not run 'lms ps --json'." @(
            "Open LM Studio and make sure the lms CLI is enabled.",
            "Try running 'lms ps --json' manually in a new terminal."
        )
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($loadedJson)) {
        Stop-WithHelp "Could not read loaded LM Studio models with 'lms ps --json'." @(
            "Open LM Studio.",
            "Load at least one chat/instruct LLM.",
            "Run 'lms ps --json' manually to confirm the LM Studio CLI works."
        )
    }

    try {
        return @($loadedJson | ConvertFrom-Json | Where-Object { $_.type -eq "llm" })
    } catch {
        Stop-WithHelp "LM Studio returned invalid JSON for 'lms ps --json'." @(
            "Update LM Studio.",
            "Run 'lms ps --json' manually and check whether it prints valid JSON."
        )
    }
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
        Stop-WithHelp "No LLM is loaded in LM Studio." @(
            "Open LM Studio.",
            "Load a chat/instruct model.",
            "Run 'lm-studio' again."
        )
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
        Stop-WithHelp "Requested model '$RequestedModel' is not loaded, or it matches more than one loaded model." @(
            "Run 'lm-studio-model -List' to see loaded model identifiers.",
            "Load the intended model in LM Studio.",
            "Run 'lm-studio-model ""model-identifier""' again."
        )
    }

    if ($loadedModels.Count -eq 1) {
        Save-SelectedModel $loadedModels[0]
        Write-Ok "Selected the only loaded model: $($loadedModels[0].identifier)"
        return $loadedModels[0]
    }

    Stop-WithHelp "More than one LLM is loaded in LM Studio." @(
        "Unload all but one model in LM Studio.",
        "Run 'lm-studio' again after only the intended model is loaded."
    )
}

function Ensure-Gateway {
    param($SelectedModel)

    $health = Get-GatewayHealth
    $expectedStateFile = (Resolve-Path -LiteralPath $script:ModelStateFile).Path
    if ($health -and ($health.gateway -ne "lm-studio-codex-gateway" -or $health.stateFile -ne $expectedStateFile)) {
        Write-Warn "Another process is using the Codex LM Studio gateway port. Restarting it..."
        Stop-GatewayOnPort
        Start-Sleep -Milliseconds 500
        $health = Get-GatewayHealth
    }

    if ($health) {
        Write-Ok "Gateway is already running on port 18123"
        return
    }

    $gatewayScript = Join-Path $script:InstallRoot "lib\lmstudio-responses-gateway.js"
    $stdoutLog = Join-Path $script:LogDir "gateway.out.log"
    $stderrLog = Join-Path $script:LogDir "gateway.err.log"
    $pidFile = Join-Path $script:LogDir "gateway.pid"

    $env:LMSTUDIO_BASE_URL = $script:LmStudioBaseUrl
    $env:LMSTUDIO_CODEX_MODEL_STATE_FILE = $script:ModelStateFile

    Write-Info "Starting local Codex <-> LM Studio gateway on http://127.0.0.1:18123..."
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
        $errorTail = ""
        if (Test-Path -LiteralPath $stderrLog) {
            $errorTail = (Get-Content -LiteralPath $stderrLog -Tail 20 -ErrorAction SilentlyContinue) -join "`n"
        }
        Stop-WithHelp "The local gateway did not start." @(
            "Check the error log: $stderrLog",
            "Make sure port 18123 is not blocked.",
            "Try 'lm-studio-stop' and then run 'lm-studio' again.",
            "Last gateway error: $errorTail"
        )
    }

    Write-Ok "Gateway is running"
}
