[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ManifestPath, [string]$ConfigPath, [switch]$Fixture)
. (Join-Path $PSScriptRoot 'deployment-common.ps1')
$codeRoot = Split-Path $PSScriptRoot -Parent
if (-not $ConfigPath) { $ConfigPath = Join-Path $codeRoot '.local/deployment.json' }
$configuration = Read-DeploymentConfig $ConfigPath
if ($Fixture) { Assert-FixtureRoot $configuration.deploymentRoot }
$manifestFile = [IO.Path]::GetFullPath($ManifestPath)
$manifestDirectory = Split-Path $manifestFile -Parent
$manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.state -notin @('applied','failed','rollback-failed')) { throw 'Manifest is not an applied or partially applied deployment.' }
if ($manifest.deploymentRoot -ne $configuration.deploymentRoot -or $manifest.containerName -ne $configuration.containerName -or $manifest.historyTaskName -ne $configuration.historyTaskName) { throw 'Manifest belongs to another deployment configuration.' }
$gate=$null
try {
    Assert-DeploymentIdle $configuration -Fixture:$Fixture
    $gate=Enter-DeploymentGate $configuration.deploymentRoot ($manifest.id + '-rollback')
    Assert-DeploymentIdle $configuration -Fixture:$Fixture
    $entries=@($manifest.files | Where-Object { $_.state -eq 'applied' -or ($_.state -eq 'failed' -and (Get-FileDigest (Resolve-SafeChild $configuration.deploymentRoot $_.target)) -eq $_.afterSha256) })
    # Validate the complete rollback before restoring any file. Later user edits are never discarded.
    foreach ($entry in $entries) {
        Assert-RuntimeTarget $entry.target
        $target=Resolve-SafeChild $configuration.deploymentRoot $entry.target
        if ((Get-FileDigest $target) -ne $entry.afterSha256) { throw "Target changed after deployment; rollback refused: $($entry.target)" }
        if ($null -ne $entry.beforeSha256 -and (Get-FileDigest (Resolve-SafeChild $manifestDirectory $entry.backup)) -ne $entry.beforeSha256) { throw "Backup is missing or changed: $($entry.target)" }
    }
    [array]::Reverse($entries)
    foreach ($entry in $entries) {
        Assert-DeploymentIdle $configuration -Fixture:$Fixture
        $target=Resolve-SafeChild $configuration.deploymentRoot $entry.target
        if ($null -eq $entry.beforeSha256) {
            # Remove only files introduced by this manifest, and only at their deployed hash.
            if ((Get-FileDigest $target) -ne $entry.afterSha256) { throw "Target changed during rollback: $($entry.target)" }
            Remove-Item -LiteralPath $target -Force
        } else {
            Publish-AtomicFile (Resolve-SafeChild $manifestDirectory $entry.backup) $target $entry.afterSha256
        }
        $entry.state='rolled-back'
        Write-DeploymentJson $manifestFile $manifest
    }
    $manifest.state='rolled-back'; $manifest.rolledBackUtc=[DateTime]::UtcNow.ToString('o')
    Write-DeploymentJson $manifestFile $manifest
} catch {
    $manifest.state='rollback-failed'; $manifest.error=$_.Exception.Message
    Write-DeploymentJson $manifestFile $manifest
    throw
} finally { if ($gate) { Exit-DeploymentGate $gate ($manifest.id + '-rollback') } }
Write-Output $manifestFile
