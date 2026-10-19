$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $OutputEncoding
. (Join-Path $PSScriptRoot 'runtime-config.ps1')
$settings = Get-OpenLaTeXRuntime
$projectRoot = $settings.Root
$stateDir = Join-Path $projectRoot '.tmp\paper-history'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$logFile = Join-Path $stateDir 'scheduler.log'
try {
    $dockerCommand = (Get-Command docker.exe -ErrorAction Stop).Source
    $state = & $dockerCommand inspect $settings.ContainerName --format '{{.State.Running}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or $state -ne 'true') { exit 0 }
    $result = & $dockerCommand exec $settings.ContainerName python3 /work/.latex-tools/paper_history.py sweep 2>&1
    $resultCode = $LASTEXITCODE
    if ((Test-Path -LiteralPath $logFile) -and (Get-Item -LiteralPath $logFile).Length -gt 2MB) {
        Move-Item -LiteralPath $logFile -Destination ($logFile + '.previous') -Force
    }
    Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ((Get-Date -Format o) + ' ' + ($result -join "`n"))
    exit $resultCode
} catch {
    Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ((Get-Date -Format o) + ' ERROR ' + $_.Exception.Message)
    exit 1
}
