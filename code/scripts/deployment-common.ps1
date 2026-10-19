$ErrorActionPreference = 'Stop'
$script:DeploymentCodeRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $script:DeploymentCodeRoot 'project-env.ps1')

function Get-FileDigest([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Expected a file: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-SafeChild([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)' -or $Relative.Contains(':')) {
        throw "Unsafe relative path: $Relative"
    }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $path = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $path.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped its root: $Relative"
    }
    $cursor = $path
    while ($cursor.Length -ge $base.Length) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not deployment targets: $cursor"
            }
        }
        $cursor = Split-Path $cursor -Parent
    }
    return $path
}

function Assert-RuntimeTarget([string]$Relative) {
    $normalized = $Relative.Replace('\', '/')
    $roots = @('Open-LaTeX.exe', 'Start-LaTeX.exe', 'Open-LaTeX.cmd', 'Paper-History.cmd')
    if (($normalized -notin $roots) -and ($normalized -notmatch '^\.latex-tools/[^/]+\.(ps1|py|exe|ico|vsix|sh|json)$')) {
        throw "Not an allowed runtime component: $Relative"
    }
}

function Write-DeploymentJson([string]$Path, $Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $Path) }
}

function Read-DeploymentConfig([string]$Path) {
    $configuration = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($name in @('deploymentRoot', 'containerName', 'historyTaskName')) {
        if (-not $configuration.$name) { throw "Missing deployment setting: $name" }
    }
    if ($configuration.containerName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw 'Invalid Docker container name.' }
    $configuration.deploymentRoot = [IO.Path]::GetFullPath($configuration.deploymentRoot)
    if (-not (Test-Path -LiteralPath $configuration.deploymentRoot -PathType Container)) { throw 'Deployment root does not exist.' }
    return $configuration
}

function Invoke-ReadOnlyProbe([string]$Executable, [string]$Arguments, [int]$TimeoutSeconds = 15) {
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
            # Only this spawned read-only CLI is stopped, never its process tree or Docker Desktop.
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(3000)
            throw "Read-only runtime probe timed out after $TimeoutSeconds seconds; state remains unknown."
        }
        if (-not $stdout.Wait(1000) -or -not $stderr.Wait(1000)) { throw 'Runtime probe output collection timed out; state remains unknown.' }
        return [pscustomobject]@{ExitCode=$process.ExitCode;Output=$stdout.Result;Error=$stderr.Result}
    } finally { $process.Dispose() }
}

function Assert-FixtureRoot([string]$Root) {
    $temporaryRoot = [IO.Path]::GetFullPath((Join-Path $script:DeploymentCodeRoot '.tmp')).TrimEnd([char[]]'\/')
    if (-not ([IO.Path]::GetFullPath($Root)).StartsWith($temporaryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixture mode is permitted only inside this project code/.tmp directory.'
    }
}

function Assert-DeploymentIdle($Configuration, [switch]$Fixture) {
    if ($Fixture) { Assert-FixtureRoot $Configuration.deploymentRoot; return }
    # Failing to inspect means unknown, never permission to overwrite running components.
    $task = @(Get-ScheduledTask -ErrorAction Stop | Where-Object TaskName -EQ $Configuration.historyTaskName)
    if (@($task | Where-Object State -EQ 'Running').Count -gt 0) { throw 'History task is running. Wait for its normal completion before deployment.' }
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $rootPattern = [regex]::Escape($Configuration.deploymentRoot)
    foreach ($process in $processes) {
        if ($process.ProcessId -eq $PID) { continue }
        if ($process.CommandLine -match $rootPattern -and $process.CommandLine -match '(?i)history-session\.ps1|history-scheduler\.ps1|HistoryTaskRunner\.exe|Start-LaTeX\.exe|Open-LaTeX\.exe|launcher-runtime\.ps1|fast_build\.py') {
            throw "A runtime component is active (PID $($process.ProcessId)). Wait for completion."
        }
    }
    if ($Configuration.containerName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw 'Invalid Docker container name.' }
    $docker = (Get-Command docker.exe -ErrorAction Stop).Source
    $state = Invoke-ReadOnlyProbe $docker ('inspect ' + $Configuration.containerName + ' --format {{.State.Running}}')
    if ($state.ExitCode -ne 0) { throw 'Cannot inspect the target container; runtime state is unknown.' }
    if ($state.Output.Trim() -eq 'true') {
        $processTable = Invoke-ReadOnlyProbe $docker ('top ' + $Configuration.containerName + ' -eo pid,args')
        if ($processTable.ExitCode -ne 0) { throw 'Cannot inspect running container processes.' }
        if ($processTable.Output -match '(?i)(fast_build\.py|paper_history\.py|latexmk|pdflatex|xelatex|lualatex|luahbtex|bibtex|biber)(\s|$)') {
            throw 'A compiler or history operation is active in the target container. Wait for completion.'
        }
    } elseif ($state.Output.Trim() -ne 'false') {
        throw 'Container running state is not a recognized Boolean; runtime state is unknown.'
    }
}

function Publish-AtomicFile([string]$Source, [string]$Target, $ExpectedHash) {
    if ((Get-FileDigest $Target) -ne $ExpectedHash) { throw "Target changed before replacement: $Target" }
    [void][IO.Directory]::CreateDirectory((Split-Path $Target -Parent))
    $temporary = $Target + '.open-latex-' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::Copy($Source, $temporary, $false)
        if ((Get-FileDigest $Target) -ne $ExpectedHash) { throw "Target changed while preparing replacement: $Target" }
        if ($ExpectedHash) { [IO.File]::Replace($temporary, $Target, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Target) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Enter-DeploymentGate([string]$Root, [string]$Id) {
    $gate = Resolve-SafeChild $Root '.latex-tools/.deployment-in-progress.json'
    [void][IO.Directory]::CreateDirectory((Split-Path $gate -Parent))
    $stream = [IO.File]::Open($gate, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try {
        $payload = [Text.Encoding]::UTF8.GetBytes((@{id=$Id;processId=$PID;startedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json))
        $stream.Write($payload, 0, $payload.Length)
        $stream.Flush()
    } finally { $stream.Dispose() }
    return $gate
}

function Exit-DeploymentGate([string]$Path, [string]$Id) {
    if (Test-Path -LiteralPath $Path) {
        $record = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($record.id -ne $Id) { throw 'Deployment gate ownership changed; retained for inspection.' }
        Remove-Item -LiteralPath $Path -Force
    }
}
