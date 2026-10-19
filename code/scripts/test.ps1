param([string]$ContainerName = 'open-latex-dev-validation', [switch]$BuildImage)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../project-env.ps1')
if ($ContainerName -notmatch '^open-latex-dev-[a-zA-Z0-9-]+$') {
    throw 'Test containers must use an open-latex-dev-* name.'
}
$probeInfo = New-Object Diagnostics.ProcessStartInfo
$probeInfo.FileName = (Get-Command docker -ErrorAction Stop).Source
$probeInfo.Arguments = 'info --format "{{.OSType}}"'
$probeInfo.UseShellExecute = $false
$probeInfo.CreateNoWindow = $true
$probeInfo.RedirectStandardOutput = $true
$probeInfo.RedirectStandardError = $true
$probe = [Diagnostics.Process]::Start($probeInfo)
try {
    $stdout = $probe.StandardOutput.ReadToEndAsync()
    $stderr = $probe.StandardError.ReadToEndAsync()
    if (-not $probe.WaitForExit(20000)) {
        $probe.Kill()
        throw 'Docker engine did not respond within 20 seconds. Inspect Docker Desktop; this script does not restart it.'
    }
    if ($probe.ExitCode -ne 0 -or $stdout.Result.Trim() -ne 'linux') {
        throw ('A running Docker Linux engine is required: ' + $stderr.Result)
    }
} finally { $probe.Dispose() }
if ($BuildImage) {
    & docker build --file (Join-Path $env:OPEN_LATEX_CODE 'config/Dockerfile.test') --tag open-latex-dev-test:0.1.0 (Join-Path $env:OPEN_LATEX_CODE 'config')
    if ($LASTEXITCODE) { throw 'Test image build failed.' }
}
$inspect = & docker inspect $ContainerName 2>$null
if ($LASTEXITCODE -eq 0) {
    $state = ($inspect | ConvertFrom-Json)[0]
    if ($state.Config.Labels.'org.open-latex.role' -ne 'isolated-test') { throw 'Existing container is not managed by this test script.' }
    $repoMount = $state.Mounts | Where-Object Destination -eq '/repo'
    $workMount = $state.Mounts | Where-Object Destination -eq '/work'
    $work = Join-Path $env:OPEN_LATEX_CODE '.tmp/dev-work'
    if ($state.Mounts.Count -ne 2 -or $repoMount.RW -or $repoMount.Source -ne $env:OPEN_LATEX_CODE -or $workMount.Source -ne $work -or -not $workMount.RW) {
        throw 'Existing test container mounts differ from the isolated project mounts.'
    }
    if (-not $state.State.Running) {
        & docker start $ContainerName
        if ($LASTEXITCODE) { throw 'Could not start isolated test container.' }
    }
} else {
    $work = Join-Path $env:OPEN_LATEX_CODE '.tmp/dev-work'
    [void][IO.Directory]::CreateDirectory($work)
    & docker run -d --name $ContainerName --label org.open-latex.role=isolated-test --mount "type=bind,source=$env:OPEN_LATEX_CODE,target=/repo,readonly" --mount "type=bind,source=$work,target=/work" open-latex-dev-test:0.1.0
    if ($LASTEXITCODE) { throw 'Could not create isolated test container.' }
}
& docker exec $ContainerName python3 /repo/tests/test_build_audit.py --work-root /work --report /work/regressions.json
if ($LASTEXITCODE) { throw 'Build/audit regressions failed.' }
& docker exec $ContainerName python3 /repo/tests/test_history.py
if ($LASTEXITCODE) { throw 'Isolated tests failed.' }
