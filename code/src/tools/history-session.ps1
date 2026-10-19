param(
    [ValidateRange(1,86400)][int]$IntervalSeconds = 300,
    [ValidateRange(0,100)][int]$MaxCycles = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'runtime-config.ps1')
$settings = Get-OpenLaTeXRuntime
$projectRoot = $settings.Root
$stateDir = Join-Path $projectRoot '.tmp\paper-history'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$sessionFile = Join-Path $stateDir 'session.json'
$shellPath = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
$schedulerPath = Join-Path $PSScriptRoot 'history-scheduler.ps1'
$dockerPath = (Get-Command docker.exe -ErrorAction Stop).Source
$sessionStarted = Get-Date -Format o
$cycle = 0

function Invoke-HiddenProcess([string]$Executable, [string]$Arguments) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = $Arguments
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{Code=$process.ExitCode;Output=$stdout.Result;Error=$stderr.Result}
    } finally { $process.Dispose() }
}

function Write-SessionState([string]$Status, [int]$LastExitCode, [string]$Detail) {
    $record = [ordered]@{
        status=$Status; started=$sessionStarted; updated=(Get-Date -Format o)
        processId=$PID; intervalSeconds=$IntervalSeconds; cycles=$cycle
        lastExitCode=$LastExitCode; detail=$Detail
    }
    $json = $record | ConvertTo-Json
    [IO.File]::WriteAllText($sessionFile, $json, (New-Object Text.UTF8Encoding($false)))
}

try {
    Write-SessionState 'running' 0 'Started by the LaTeX launcher.'
    while ($true) {
        $container = Invoke-HiddenProcess $dockerPath ('inspect ' + $settings.ContainerName + ' --format "{{.State.Running}}"')
        if ($container.Code -ne 0 -or $container.Output.Trim() -ne 'true') {
            Write-SessionState 'stopped' 0 'Docker or the configured container is stopped. Open LaTeX to start a new session.'
            exit 0
        }
        $result = Invoke-HiddenProcess $shellPath ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $schedulerPath + '"')
        $cycle++
        Write-SessionState 'running' $result.Code $result.Error.Trim()
        if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) {
            Write-SessionState 'stopped' $result.Code 'Bounded verification completed.'
            exit $result.Code
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
} catch {
    Write-SessionState 'failed' 1 $_.Exception.Message
    exit 1
}
