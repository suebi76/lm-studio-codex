param(
    [string] $Model,
    [switch] $List
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path $PSScriptRoot "common.ps1")

try {
    Initialize-LmStudioCodexState
    Assert-Dependencies
    Ensure-LmStudioServer

    if ($List) {
        $loaded = @(Get-LoadedLmStudioModels)
        if ($loaded.Count -eq 0) {
            Stop-WithHelp "No LLM is loaded in LM Studio." @(
                "Open LM Studio.",
                "Load a chat/instruct model.",
                "Run 'lm-studio-model -List' again."
            )
        }
        $current = Get-SelectedModelState
        foreach ($item in $loaded) {
            $marker = if ($current -and $current.id -eq $item.identifier) { "*" } else { " " }
            Write-Host "$marker $($item.identifier) - $($item.displayName)"
        }
        exit 0
    }

    $selected = Select-LmStudioModel -RequestedModel $Model -ForcePrompt:([string]::IsNullOrWhiteSpace($Model))
    Write-Ok "Selected LM Studio model for Codex: $($selected.identifier)"
    $health = Get-GatewayHealth
    if ($health) {
        Write-Info "The running gateway will use this model on the next Codex request."
    }
} catch {
    Write-Host ""
    Write-Host "[lm-studio] Model selection failed." -ForegroundColor Red
    exit 1
}
