$ErrorActionPreference = 'Stop'

# Runtime files live in <workspace>/.latex-tools, independently of the development tree.
function Get-OpenLaTeXRuntime {
    $runtimeRoot = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.deployment-in-progress.json')) {
        throw 'A deployment is in progress. Wait for it to complete before starting work.'
    }
    $configPath = Join-Path $PSScriptRoot 'runtime.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw 'Missing .latex-tools/runtime.json. Copy config/runtime.example.json and set the deployment container and on-demand history task.'
    }
    $settings = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$settings.containerName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') {
        throw 'runtime.json containerName must be a Docker container name.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$settings.historyTaskName) -or [string]$settings.historyTaskName -match '["\r\n]') {
        throw 'runtime.json historyTaskName must name an existing on-demand task.'
    }
    if ([string]$settings.workspacePath -ne '/work') {
        throw 'This release requires the workspace to be mounted at /work in the Linux container.'
    }
    [pscustomobject]@{
        Root = $runtimeRoot
        ContainerName = [string]$settings.containerName
        HistoryTaskName = [string]$settings.historyTaskName
        WorkspacePath = [string]$settings.workspacePath
    }
}
