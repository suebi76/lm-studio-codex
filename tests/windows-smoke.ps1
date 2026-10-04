$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../install/lib/common.ps1')

# Commands other than Node are mocked; CI needs neither LM Studio nor Codex.
function Test-CommandAvailable { param([string]$Name) return $true }
Assert-Dependencies

$script:Stopped = @()
function Get-CimInstance {
    @(
        [pscustomobject]@{ ProcessId=101; CommandLine='node "C:\other\gateway.js"' },
        [pscustomobject]@{ ProcessId=102; CommandLine=('node "' + (Join-Path $script:InstallRoot 'lib\lmstudio-responses-gateway.js') + '"') }
    )
}
function Stop-Process { param($Id, [switch]$Force, $ErrorAction) $script:Stopped += $Id }
Stop-GatewayOnPort
if ($script:Stopped.Count -ne 1 -or $script:Stopped[0] -ne 102) { throw 'Process ownership check failed.' }

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('lmsc-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $script:ModelStateFile = Join-Path $temporary 'model.json'
    function Get-LoadedLmStudioModels { @() }
    try { Select-LmStudioModel; throw 'Expected no-model error' } catch {
        if ($_.Exception.Message -notmatch 'No LLM') { throw }
    }
    function Get-LoadedLmStudioModels { @([pscustomobject]@{identifier='one';type='llm'}) }
    $selected = Select-LmStudioModel
    if ($selected.identifier -ne 'one') { throw 'Wrong selected model' }
    function Get-GatewayHealth { [pscustomobject]@{gateway='foreign';stateFile='foreign'} }
    try { Ensure-Gateway $selected; throw 'Expected port conflict' } catch {
        if ($_.Exception.Message -notmatch 'another service') { throw }
    }
    if ($script:Stopped.Count -ne 1) { throw 'Foreign process was stopped.' }
} finally {
    # Only this test's explicitly created file and empty directory are removed.
    Remove-Item -LiteralPath $script:ModelStateFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporary -Force
}
Write-Host 'Windows preflight, model and process ownership tests passed.'
