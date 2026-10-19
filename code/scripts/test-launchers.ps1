param([Parameter(Mandatory=$true)][string]$ContainerName, [switch]$VerifyTaskRegistration, [switch]$ConfigurationOnly, [switch]$VerifyDockerTimeout, [string]$RuntimeRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../project-env.ps1')
if ($ContainerName -notmatch '^open-latex-dev-[a-zA-Z0-9_.-]+$') {
    throw 'Use an isolated container whose name starts with open-latex-dev-.'
}
$codeRoot = Split-Path -Parent $PSScriptRoot
$runtime = if ($RuntimeRoot) { [IO.Path]::GetFullPath($RuntimeRoot) } else { Join-Path $codeRoot '.build/runtime' }
$codePrefix = [IO.Path]::GetFullPath($codeRoot).TrimEnd('\') + '\'
if (-not $runtime.StartsWith($codePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Launcher tests only accept a runtime built or extracted inside code/.'
}
$testRoot = Join-Path $codeRoot ('.tmp/launcher test 中文 ' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
Get-ChildItem -LiteralPath $runtime -Force | Copy-Item -Destination $testRoot -Recurse -Force
$configPath = Join-Path $testRoot '.latex-tools/runtime.json'

function Invoke-Diagnostic([string]$Name) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $testRoot $Name
    $info.Arguments = '--diagnose'
    $info.WorkingDirectory = $codeRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { throw ($Name + ' diagnostic timed out; no editor window was requested.') }
        [pscustomobject]@{ExitCode=$process.ExitCode; Output=$stdout.Result; Error=$stderr.Result}
    } finally { $process.Dispose() }
}

$checks = @()
foreach ($name in @('Open-LaTeX.exe','Start-LaTeX.exe')) {
    $result = Invoke-Diagnostic $name
    if ($result.ExitCode -ne 1 -or $result.Error -notlike '*Missing .latex-tools/runtime.json*') {
        throw ($name + ' missing configuration check failed: ' + $result.Output + $result.Error)
    }
    $checks += $name + ': missing configuration rejected without UI'
}
$configuration = @{containerName=$ContainerName; historyTaskName='Open-LaTeX-Dev-Unregistered'; workspacePath='/work'}
$configuration | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
$taskPlan = & (Join-Path $testRoot '.latex-tools/register-history-task.ps1') -Preview | ConvertFrom-Json
if (@($taskPlan.triggers).Count -ne 0 -or $taskPlan.workingDirectory -ne $testRoot -or
    $taskPlan.executable -ne (Join-Path $testRoot '.latex-tools/HistoryTaskRunner.exe')) {
    throw 'History task preview contains automatic triggers or depends on a different runtime directory.'
}
$checks += 'History task plan has no triggers and uses only deployment-local executable, script and working directory'
if ($VerifyTaskRegistration) {
    $testTaskName = 'Open-LaTeX-Dev-' + [Guid]::NewGuid().ToString('N')
    $configuration.historyTaskName = $testTaskName
    $configuration | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    $taskCreated = $false
    try {
        & (Join-Path $testRoot '.latex-tools/register-history-task.ps1') | Out-Null
        $taskCreated = $true
        $registered = Get-ScheduledTask -TaskName $testTaskName -TaskPath '\' -ErrorAction Stop
        if (@($registered.Triggers | Where-Object { $null -ne $_ }).Count -ne 0 -or @($registered.Actions).Count -ne 1 -or
            $registered.Actions[0].Execute -ne $taskPlan.executable -or $registered.Actions[0].Arguments -ne $taskPlan.arguments -or
            $registered.Actions[0].WorkingDirectory -ne $testRoot) {
            throw 'Registered isolated history task does not match its no-trigger runtime plan.'
        }
        & (Join-Path $testRoot '.latex-tools/register-history-task.ps1') | Out-Null
        $checks += 'Unique isolated history task registered, verified, preserved on repeated registration and removed without ever starting it'
    } finally {
        if ($taskCreated) { Unregister-ScheduledTask -TaskName $testTaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop }
    }
}
if ($VerifyDockerTimeout) {
    $fakeBin = Join-Path $testRoot 'fake-docker'
    [void][IO.Directory]::CreateDirectory($fakeBin)
    $fakeSource = Join-Path $fakeBin 'Sleep.cs'
    'internal static class Sleep { private static void Main() { System.Threading.Thread.Sleep(60000); } }' | Set-Content -LiteralPath $fakeSource -Encoding UTF8
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
    & $compiler /nologo /target:exe ('/out:' + (Join-Path $fakeBin 'docker.exe')) $fakeSource
    if ($LASTEXITCODE -ne 0) { throw 'Failed to build the intentionally unresponsive Docker CLI test fixture.' }
    $originalPath = $env:PATH
    try {
        $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $originalPath
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-Diagnostic 'Open-LaTeX.exe'
        $timer.Stop()
        $data = $result.Output | ConvertFrom-Json
        if ($result.ExitCode -ne 1 -or $data.containerStatus -ne 'unknown-timeout' -or $data.dockerExitCode -ne 124 -or
            $data.containerRunning -or $timer.Elapsed.TotalSeconds -gt 25) {
            throw ('Unresponsive Docker CLI did not produce a bounded unknown-timeout result: ' + $result.Output + $result.Error)
        }
        $checks += 'Unresponsive isolated Docker CLI returns unknown-timeout within 25 seconds; no Docker engine process is touched'
    } finally { $env:PATH = $originalPath }
}
if (-not $ConfigurationOnly) {
    foreach ($name in @('Open-LaTeX.exe','Start-LaTeX.exe')) {
        $result = Invoke-Diagnostic $name
        if ($result.ExitCode -ne 0) { throw ($name + ' diagnostic failed: ' + $result.Error + $result.Output) }
        $data = $result.Output | ConvertFrom-Json
        if ($data.container -ne $ContainerName -or $data.remoteActivation -ne 'not-checked' -or -not $data.containerRunning) {
            throw ($name + ' reported incorrect runtime state.')
        }
        if (($data.actionsPerformed -join ',') -ne 'read-config,inspect-container,find-code') {
            throw ($name + ' diagnostic reported unexpected actions.')
        }
        $checks += $name + ': configured isolated container inspected from Unicode/space path; no task/editor launch'
    }
}
$marker = Join-Path $testRoot '.latex-tools/.deployment-in-progress.json'
'{}' | Set-Content -LiteralPath $marker -Encoding UTF8
$result = Invoke-Diagnostic 'Open-LaTeX.exe'
if ($result.ExitCode -ne 1 -or $result.Error -notlike '*deployment is in progress*') { throw 'Deployment gate check failed.' }
$checks += 'Deployment marker blocks runtime entry'
Remove-Item -LiteralPath $marker
$configuration.containerName = 'invalid container;name'
$configuration | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
$result = Invoke-Diagnostic 'Open-LaTeX.exe'
if ($result.ExitCode -ne 1 -or $result.Error -notlike '*containerName must be a Docker container name*') { throw 'Invalid container check failed.' }
$checks += 'Invalid container configuration rejected before Docker invocation'
$record = [ordered]@{passed=$checks.Count; checks=$checks; containerInspection= $(if ($ConfigurationOnly) { 'not-tested' } else { 'passed' }); remoteActivation='not-tested'; testDirectory=$testRoot}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $testRoot 'test-result.json') -Encoding UTF8
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $codeRoot '.build/launcher-test-result.json') -Encoding UTF8
$record | ConvertTo-Json -Depth 5
