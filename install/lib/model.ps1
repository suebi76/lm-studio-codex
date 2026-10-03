param(
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

    $selected = Select-LmStudioModel
    Write-Ok "Current LM Studio model for Codex: $($selected.identifier)"
} catch {
    Write-Host ""
    Write-Host "[lm-studio] Model selection failed." -ForegroundColor Red
    exit 1
}
