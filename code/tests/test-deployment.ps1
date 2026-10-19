# Self-contained disposable file fixtures; never targets a configured personal instance.
$ErrorActionPreference='Stop'
$codeRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $codeRoot 'project-env.ps1')
. (Join-Path $codeRoot 'scripts/deployment-common.ps1')
$deploy=Join-Path $codeRoot 'scripts/deploy.ps1'
$rollback=Join-Path $codeRoot 'scripts/rollback.ps1'
$suiteRoot=Join-Path $codeRoot ('.tmp/deployment-tests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($suiteRoot)
$results=New-Object Collections.Generic.List[string]

function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Expect-Failure([scriptblock]$Operation,[string]$Pattern) {
    try { & $Operation | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected failure matching $Pattern"
}
function New-Fixture([string]$Name) {
    $base=Join-Path $suiteRoot $Name
    $target=Join-Path $base 'target 中文 with spaces'
    $runtime=Join-Path $base 'runtime'
    foreach ($directory in @($target,$runtime,(Join-Path $target '.latex-tools'),(Join-Path $target 'papers/example/.git'))) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    [IO.File]::WriteAllText((Join-Path $target 'Open-LaTeX.exe'),'old-open')
    [IO.File]::WriteAllText((Join-Path $target 'Start-LaTeX.exe'),'old-start')
    [IO.File]::WriteAllText((Join-Path $runtime 'Open-LaTeX.exe'),'new-open')
    [IO.File]::WriteAllText((Join-Path $runtime 'Start-LaTeX.exe'),'new-start')
    [IO.File]::WriteAllText((Join-Path $target 'papers/example/.git/HEAD'),'preserve-history')
    Write-DeploymentJson (Join-Path $target '.latex-tools/runtime.json') @{personalKey='preserve';containerName='old'}
    $config=Join-Path $base 'deployment.json'
    $map=Join-Path $base 'map.json'
    $baseline=Join-Path $base 'baseline.json'
    Write-DeploymentJson $config @{deploymentRoot=$target;containerName='fixture-container';historyTaskName='fixture-history'}
    Write-DeploymentJson $map @{schemaVersion=1;files=@(@{source='Open-LaTeX.exe';target='Open-LaTeX.exe'},@{source='Start-LaTeX.exe';target='Start-LaTeX.exe'});mergedRuntimeConfig='.latex-tools/runtime.json'}
    $parameters=@{ConfigPath=$config;MapPath=$map;RuntimeRoot=$runtime;BaselinePath=$baseline;Fixture=$true}
    & $deploy @parameters -Action Baseline | Out-Null
    return @{Root=$target;Parameters=$parameters;Config=$config;Base=$base}
}

$fixture=New-Fixture 'roundtrip'
$parameters=$fixture.Parameters
$plan=& $deploy @parameters -Action Plan
& $deploy @parameters -Action Apply -PlanPath $plan | Out-Null
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'Open-LaTeX.exe')) -eq 'new-open') 'Replacement failed.'
$merged=Get-Content -LiteralPath (Join-Path $fixture.Root '.latex-tools/runtime.json') -Raw | ConvertFrom-Json
Assert-True ($merged.personalKey -eq 'preserve' -and $merged.containerName -eq 'fixture-container') 'Config merge lost a personal key.'
& $rollback -ManifestPath $plan -ConfigPath $fixture.Config -Fixture | Out-Null
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'Open-LaTeX.exe')) -eq 'old-open') 'Rollback failed.'
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'papers/example/.git/HEAD')) -eq 'preserve-history') 'History was altered.'
$results.Add('roundtrip, private setting merge, Chinese/space paths, history preservation')

$fixture=New-Fixture 'baseline-conflict'; $parameters=$fixture.Parameters
[IO.File]::WriteAllText((Join-Path $fixture.Root 'Open-LaTeX.exe'),'user-edit')
Expect-Failure { & $deploy @parameters -Action Plan } 'changed since baseline'
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'Open-LaTeX.exe')) -eq 'user-edit') 'Conflict was overwritten.'
$results.Add('baseline conflict rejected')

$fixture=New-Fixture 'plan-conflict'; $parameters=$fixture.Parameters
$plan=& $deploy @parameters -Action Plan
[IO.File]::WriteAllText((Join-Path $fixture.Root 'Start-LaTeX.exe'),'user-edit')
Expect-Failure { & $deploy @parameters -Action Apply -PlanPath $plan } 'changed since plan'
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'Open-LaTeX.exe')) -eq 'old-open') 'Preflight changed a file.'
$results.Add('whole-plan preflight before modifications')

$fixture=New-Fixture 'artifact-conflict'; $parameters=$fixture.Parameters
$plan=& $deploy @parameters -Action Plan
[IO.File]::WriteAllText((Join-Path (Split-Path $plan -Parent) 'staged/Start-LaTeX.exe'),'altered-build')
Expect-Failure { & $deploy @parameters -Action Apply -PlanPath $plan } 'Staged artifact changed'
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'Open-LaTeX.exe')) -eq 'old-open') 'Altered artifact caused mutation.'
$results.Add('staged hash mismatch rejected')

$fixture=New-Fixture 'rollback-conflict'; $parameters=$fixture.Parameters
$plan=& $deploy @parameters -Action Plan
& $deploy @parameters -Action Apply -PlanPath $plan | Out-Null
[IO.File]::WriteAllText((Join-Path $fixture.Root 'Start-LaTeX.exe'),'later-user-change')
Expect-Failure { & $rollback -ManifestPath $plan -ConfigPath $fixture.Config -Fixture } 'changed after deployment'
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'Open-LaTeX.exe')) -eq 'new-open') 'Rollback preflight modified another file.'
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'Start-LaTeX.exe')) -eq 'later-user-change') 'Rollback discarded user changes.'
$results.Add('post-deployment user changes protected')

$fixture=New-Fixture 'partial-failure'; $parameters=$fixture.Parameters
$plan=& $deploy @parameters -Action Plan
$locked=[IO.File]::Open((Join-Path $fixture.Root 'Start-LaTeX.exe'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try { Expect-Failure { & $deploy @parameters -Action Apply -PlanPath $plan } 'process|access|used|sharing|另一个|进程|访问' }
finally { $locked.Dispose() }
$partial=Get-Content -LiteralPath $plan -Raw | ConvertFrom-Json
Assert-True ($partial.state -eq 'failed' -and $partial.files[0].state -eq 'applied' -and $partial.files[1].state -eq 'failed') 'Partial failure was not recorded.'
& $rollback -ManifestPath $plan -ConfigPath $fixture.Config -Fixture | Out-Null
Assert-True ([IO.File]::ReadAllText((Join-Path $fixture.Root 'Open-LaTeX.exe')) -eq 'old-open') 'Partial rollback failed.'
$results.Add('locked runtime file, partial failure journal, manifest-only rollback')

$fixture=New-Fixture 'new-file'; $parameters=$fixture.Parameters
Remove-Item -LiteralPath (Join-Path $fixture.Root 'Open-LaTeX.exe')
$parameters.BaselinePath=Join-Path $fixture.Base 'baseline-with-absent-file.json'
& $deploy @parameters -Action Baseline | Out-Null
$plan=& $deploy @parameters -Action Plan
& $deploy @parameters -Action Apply -PlanPath $plan | Out-Null
& $rollback -ManifestPath $plan -ConfigPath $fixture.Config -Fixture | Out-Null
Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Root 'Open-LaTeX.exe'))) 'Rollback left an introduced file.'
$results.Add('introduced files removed only by their own rollback manifest')

Expect-Failure { Assert-FixtureRoot (Split-Path $codeRoot -Parent) } 'only inside'
Expect-Failure { Assert-RuntimeTarget 'papers/private.tex' } 'Not an allowed'
Expect-Failure { Resolve-SafeChild $suiteRoot '../escape.txt' } 'Unsafe relative'
$results.Add('fixture bypass and protected path restrictions')

$invalidConfig=Join-Path $suiteRoot 'invalid-container.json'
Write-DeploymentJson $invalidConfig @{deploymentRoot=$fixture.Root;containerName='bad container';historyTaskName='fixture-history'}
Expect-Failure { Read-DeploymentConfig $invalidConfig } 'Invalid Docker container name'
$shell=(Get-Process -Id $PID).Path
$probe=Invoke-ReadOnlyProbe $shell '-NoProfile -NonInteractive -Command "[Console]::WriteLine(42)"' 5
Assert-True ($probe.ExitCode -eq 0 -and $probe.Output.Trim() -eq '42') 'Read-only probe output failed.'
$clock=[Diagnostics.Stopwatch]::StartNew()
Expect-Failure { Invoke-ReadOnlyProbe $shell '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"' 1 } 'timed out'
$clock.Stop()
Assert-True ($clock.Elapsed.TotalSeconds -lt 6) 'Timed-out probe was not bounded.'
$results.Add('invalid container rejected, probe output and bounded timeout')
$report=Join-Path $suiteRoot 'results.json'
Write-DeploymentJson $report @{passed=$results.Count;cases=@($results.ToArray());root=$suiteRoot}
$results | ForEach-Object { Write-Output ('PASS ' + $_) }
Write-Output $report
