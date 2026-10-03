param(
    [switch] $SkipCodexSmoke
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path $PSScriptRoot "common.ps1")

$script:DoctorWarned = $false
$script:DoctorFailed = $false
$script:DoctorTimeoutSec = 45
if ($env:LMSTUDIO_DOCTOR_TIMEOUT_SEC) {
    $parsedTimeout = 0
    if ([int]::TryParse($env:LMSTUDIO_DOCTOR_TIMEOUT_SEC, [ref] $parsedTimeout) -and $parsedTimeout -gt 0) {
        $script:DoctorTimeoutSec = $parsedTimeout
    }
}

function Write-DoctorPass {
    param([string] $Message)
    Write-Host "[lm-studio] OK: $Message" -ForegroundColor Green
}

function Write-DoctorWarn {
    param([string] $Message)
    $script:DoctorWarned = $true
    Write-Host "[lm-studio] WARNING: $Message" -ForegroundColor Yellow
}

function Write-DoctorFail {
    param([string] $Message)
    $script:DoctorFailed = $true
    Write-Host "[lm-studio] FAIL: $Message" -ForegroundColor Red
}

function Get-AssistantText {
    param($Response)

    $parts = @()
    foreach ($item in @($Response.output)) {
        if ($item.type -ne "message") {
            continue
        }
        foreach ($content in @($item.content)) {
            if ($content.type -eq "output_text" -and $content.text) {
                $parts += [string] $content.text
            }
        }
    }
    return ($parts -join "`n")
}

function Invoke-GatewayResponse {
    param(
        [string] $Prompt,
        [object[]] $Tools = $null,
        [int] $MaxTokens = 128
    )

    $body = [ordered]@{
        model = "lmstudio-loaded"
        input = $Prompt
        stream = $false
        temperature = 0
        max_output_tokens = $MaxTokens
    }
    if ($Tools) {
        $body.tools = $Tools
    }

    Invoke-RestMethod `
        -Method Post `
        -Uri "http://127.0.0.1:18123/v1/responses" `
        -ContentType "application/json" `
        -Body ($body | ConvertTo-Json -Depth 20) `
        -TimeoutSec $script:DoctorTimeoutSec
}

function Test-GatewayText {
    try {
        $response = Invoke-GatewayResponse "Reply exactly: LM_STUDIO_GATEWAY_OK" -MaxTokens 512
        $text = Get-AssistantText $response
        if ($text -match "LM_STUDIO_GATEWAY_OK") {
            Write-DoctorPass "Gateway text response works"
            return $true
        }
        Write-DoctorWarn "Gateway responded, but the model did not follow an exact short instruction. Output: $text"
        return $true
    } catch {
        Write-DoctorFail "Gateway text response failed within $script:DoctorTimeoutSec seconds: $($_.Exception.Message)"
        return $false
    }
}

function Test-GatewayJson {
    try {
        $response = Invoke-GatewayResponse 'Return only this compact JSON object and no markdown: {"ok":true,"kind":"doctor"}' -MaxTokens 512
        $text = Get-AssistantText $response
        $match = [regex]::Match($text, '\{[\s\S]*\}')
        if (-not $match.Success) {
            Write-DoctorWarn "Model did not return parseable JSON. Output: $text"
            return
        }

        $parsed = $match.Value | ConvertFrom-Json
        if ($parsed.ok -eq $true -and $parsed.kind -eq "doctor") {
            Write-DoctorPass "Model can produce simple JSON"
            return
        }
        Write-DoctorWarn "Model returned JSON, but not the requested object. Output: $text"
    } catch {
        Write-DoctorWarn "JSON check failed: $($_.Exception.Message)"
    }
}

function Test-GatewayToolCalling {
    try {
        $tools = @(
            [ordered]@{
                type = "function"
                name = "doctor_ping"
                description = "Use this to confirm that tool calling works."
                parameters = [ordered]@{
                    type = "object"
                    properties = [ordered]@{
                        ok = [ordered]@{ type = "boolean" }
                    }
                    required = @("ok")
                    additionalProperties = $false
                }
            }
        )
        $response = Invoke-GatewayResponse "Call the doctor_ping tool exactly once with ok=true. Do not answer in normal text." -Tools $tools -MaxTokens 128
        $toolCalls = @($response.output | Where-Object { $_.type -eq "function_call" })
        if ($toolCalls.Count -eq 0) {
            $text = Get-AssistantText $response
            Write-DoctorWarn "No tool call was produced. This model may be weak for Coding-Agent workflows. Output: $text"
            return
        }

        $call = $toolCalls[0]
        if ($call.name -ne "doctor_ping") {
            Write-DoctorWarn "Model produced a tool call, but with the wrong function name: $($call.name)"
            return
        }

        $arguments = $call.arguments | ConvertFrom-Json
        if ($arguments.ok -eq $true) {
            Write-DoctorPass "Model can produce a simple tool call"
            return
        }
        Write-DoctorWarn "Model produced a tool call, but with unexpected arguments: $($call.arguments)"
    } catch {
        Write-DoctorWarn "Tool-call check failed: $($_.Exception.Message)"
    }
}

function Test-CodexSmoke {
    if ($SkipCodexSmoke) {
        Write-DoctorWarn "Codex smoke test skipped by user"
        return
    }

    $stdoutLog = Join-Path $script:LogDir "doctor-codex.out.log"
    $stderrLog = Join-Path $script:LogDir "doctor-codex.err.log"
    Remove-Item -LiteralPath $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue

    $oldCodexHome = $env:CODEX_HOME
    $env:CODEX_HOME = $script:CodexHome
    try {
        Write-Info "Running Codex CLI smoke test..."
        $codexArgs = @("--no-daemon", "exec", "--skip-git-repo-check", "Reply exactly: LM_STUDIO_CODEX_DOCTOR_OK")
        if ($env:LMSTUDIO_CODEX_USE_DAEMON -eq "1") {
            $codexArgs = @("exec", "--skip-git-repo-check", "Reply exactly: LM_STUDIO_CODEX_DOCTOR_OK")
        }
        $process = Start-Process `
            -FilePath "codex" `
            -ArgumentList $codexArgs `
            -WorkingDirectory (Get-Location) `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -NoNewWindow `
            -PassThru

        if (-not $process.WaitForExit(120000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Write-DoctorFail "Codex CLI smoke test timed out after 120 seconds. See $stderrLog"
            return
        }

        $stdout = ""
        if (Test-Path -LiteralPath $stdoutLog) {
            $stdout = Get-Content -LiteralPath $stdoutLog -Raw -ErrorAction SilentlyContinue
        }

        if ($process.ExitCode -eq 0 -and $stdout -match "LM_STUDIO_CODEX_DOCTOR_OK") {
            Write-DoctorPass "Codex CLI can complete a simple request through LM Studio"
            return
        }

        if ($process.ExitCode -eq 0) {
            Write-DoctorWarn "Codex CLI completed, but the model did not return the exact marker. See $stdoutLog"
            return
        }

        Write-DoctorFail "Codex CLI smoke test failed with exit code $($process.ExitCode). See $stderrLog"
    } finally {
        $env:CODEX_HOME = $oldCodexHome
    }
}

function Write-ModelRecommendation {
    param([string] $ModelId)

    $lower = $ModelId.ToLowerInvariant()
    Write-Host ""
    Write-Host "Model recommendation:"
    if ($lower -match "qwen" -and $lower -match "coder") {
        Write-DoctorPass "Recommended for local coding agents. Qwen Coder models are usually strong at code and tool-style workflows."
        return
    }
    if ($lower -match "qwen") {
        Write-DoctorPass "Good candidate. For heavier agent work, prefer a Qwen Coder or large Qwen instruct model if it fits your hardware."
        return
    }
    if ($lower -match "deepseek" -and ($lower -match "coder|v3|v4")) {
        Write-DoctorPass "Recommended if your hardware can run it comfortably. DeepSeek coding/V3-style models are strong for larger code tasks."
        return
    }
    if ($lower -match "kimi|moonshot") {
        Write-DoctorPass "Good candidate for agentic workflows, especially Kimi K2/K-code style models with tool-use support."
        return
    }
    if ($lower -match "devstral|codestral") {
        Write-DoctorPass "Good coding-agent candidate. Devstral is the better fit for multi-step agent work; Codestral is stronger for coding completion/editing."
        return
    }
    if ($lower -match "gemma") {
        Write-DoctorWarn "Gemma can work for smaller coding tasks, but watch the JSON/tool-call checks. For autonomous repo edits, a coder/agent model is usually safer."
        return
    }
    if ($lower -match "llama|mistral|phi|granite|starcoder") {
        Write-DoctorWarn "Usable depending on size and quantization. Prefer an instruct/coder variant and trust the Doctor checks over the model family name."
        return
    }

    Write-DoctorWarn "Unknown model family. If text, JSON, and tool-call checks pass, try it on small repo tasks first."
}

try {
    Write-Info "Running LM Studio Codex doctor..."
    Initialize-LmStudioCodexState
    Assert-Dependencies
    Ensure-LmStudioServer
    $selectedModel = Select-LmStudioModel
    Ensure-Gateway $selectedModel

    Write-DoctorPass "Preflight checks passed"
    Write-DoctorPass "Loaded model: $($selectedModel.identifier)"
    Write-ModelRecommendation $selectedModel.identifier

    Write-Host ""
    Write-Host "Runtime checks:"
    $gatewayResponsive = Test-GatewayText
    if ($gatewayResponsive) {
        Test-GatewayJson
        Test-GatewayToolCalling
        Test-CodexSmoke
    } else {
        Write-Warn "Skipping JSON, tool-call, and Codex smoke checks because the model did not answer the basic gateway test."
    }

    Write-Host ""
    if ($script:DoctorFailed) {
        Write-DoctorFail "Doctor finished with failures. Fix the failed checks before using this model for agent work."
        exit 1
    }
    if ($script:DoctorWarned) {
        Write-Warn "Doctor finished with warnings. The setup can run, but this model may be unreliable for longer coding-agent sessions."
        exit 0
    }
    Write-DoctorPass "Doctor finished cleanly. This model/setup looks ready for Coding-Agent workflows."
} catch {
    Write-Host ""
    Write-Host "[lm-studio] Doctor failed before runtime checks." -ForegroundColor Red
    Write-Host "[lm-studio] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
