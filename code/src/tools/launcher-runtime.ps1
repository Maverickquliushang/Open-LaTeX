param([switch]$Diagnose, [switch]$HistoryMenu)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'runtime-config.ps1')

function Invoke-DockerBounded([string]$Executable, [string]$Arguments, [int]$TimeoutSeconds) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = $Arguments
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Stop only this CLI request; the Docker engine and running containers are untouched.
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(1000)
            return [pscustomobject]@{Code=124; TimedOut=$true; Output=''; Error=('Docker command timed out after ' + $TimeoutSeconds + ' seconds.')}
        }
        [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),2000)
        [pscustomobject]@{
            Code=$process.ExitCode; TimedOut=$false
            Output=$(if ($stdout.IsCompleted) { $stdout.Result } else { '' })
            Error=$(if ($stderr.IsCompleted) { $stderr.Result } else { 'Docker CLI output stream did not close.' })
        }
    } finally { $process.Dispose() }
}

try {
    $settings = Get-OpenLaTeXRuntime
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $connection = @{containerName=('/' + $settings.ContainerName)} | ConvertTo-Json -Compress
    $connectionHex = -join ([Text.Encoding]::UTF8.GetBytes($connection) | ForEach-Object { $_.ToString('x2') })
    $workspaceUri = 'vscode-remote://attached-container+' + $connectionHex + $settings.WorkspacePath
    if ($Diagnose) {
        $inspection = Invoke-DockerBounded $docker ('inspect ' + $settings.ContainerName + ' --format "{{.State.Running}}"') 15
        $running = $inspection.Code -eq 0 -and $inspection.Output.Trim() -eq 'true'
        $containerStatus = if ($inspection.TimedOut) { 'unknown-timeout' } elseif ($inspection.Code -ne 0) { 'unknown-error' } elseif ($running) { 'running' } else { 'stopped' }
        $codeCommand = Get-Command code.cmd -ErrorAction SilentlyContinue
        [ordered]@{
            mode='diagnose'; container=$settings.ContainerName
            containerRunning=$(if ($inspection.Code -eq 0) { $running } else { $null }); containerStatus=$containerStatus
            dockerExitCode=$inspection.Code; dockerError=$inspection.Error.Trim()
            codeCommandFound=($null -ne $codeCommand)
            historyTask=$settings.HistoryTaskName; workspaceUri=$workspaceUri
            remoteActivation='not-checked'; actionsPerformed=@('read-config','inspect-container','find-code')
        } | ConvertTo-Json -Depth 4
        if (-not $running) { exit 1 }
        exit 0
    }
    $started = Invoke-DockerBounded $docker ('start ' + $settings.ContainerName) 60
    if ($started.Code -ne 0) { throw ('Could not start the configured container. Check Docker Desktop and runtime.json. ' + $started.Error) }
    if ($HistoryMenu) {
        & $docker exec -it $settings.ContainerName python3 /work/.latex-tools/paper_history.py menu
        exit $LASTEXITCODE
    }
    $code = (Get-Command code.cmd -ErrorAction Stop).Source
    & (Join-Path $env:SystemRoot 'System32/schtasks.exe') /Run /TN $settings.HistoryTaskName
    if ($LASTEXITCODE -ne 0) { throw 'Could not start the configured on-demand history task.' }
    & $code --new-window --folder-uri $workspaceUri
    if ($LASTEXITCODE -ne 0) { throw 'VS Code rejected the workspace-open request.' }
    Write-Output 'Workspace-open request sent. Remote connection and extension activation have not been verified.'
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
