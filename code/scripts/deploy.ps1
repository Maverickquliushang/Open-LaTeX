[CmdletBinding()]
param(
    [ValidateSet('Baseline','Plan','Apply')][string]$Action = 'Plan',
    [string]$ConfigPath,
    [string]$MapPath,
    [string]$RuntimeRoot,
    [string]$BaselinePath,
    [string]$PlanPath,
    [switch]$Fixture
)
. (Join-Path $PSScriptRoot 'deployment-common.ps1')
$codeRoot = Split-Path $PSScriptRoot -Parent
if (-not $ConfigPath) { $ConfigPath = Join-Path $codeRoot '.local/deployment.json' }
if (-not $MapPath) { $MapPath = Join-Path $codeRoot 'config/deployment-map.json' }
if (-not $RuntimeRoot) { $RuntimeRoot = Join-Path $codeRoot '.build/runtime' }
if (-not $BaselinePath) { $BaselinePath = Join-Path $codeRoot '.local/deployment-baseline.json' }
$configuration = Read-DeploymentConfig $ConfigPath
if ($Fixture) { Assert-FixtureRoot $configuration.deploymentRoot }
$mapping = Get-Content -LiteralPath $MapPath -Raw | ConvertFrom-Json
if ($mapping.schemaVersion -ne 1) { throw 'Unsupported deployment mapping schema.' }
$targets = @($mapping.files | ForEach-Object { $_.target }) + @($mapping.mergedRuntimeConfig)
if (($targets | Select-Object -Unique).Count -ne $targets.Count) { throw 'Duplicate deployment targets.' }
foreach ($relative in $targets) { Assert-RuntimeTarget $relative }

if ($Action -eq 'Baseline') {
    if (Test-Path -LiteralPath $BaselinePath) { throw 'Baseline already exists; preserve it and use a new path for a reviewed new baseline.' }
    $files = @($targets | ForEach-Object {
        [ordered]@{target=$_;sha256=(Get-FileDigest (Resolve-SafeChild $configuration.deploymentRoot $_))}
    })
    Write-DeploymentJson $BaselinePath ([ordered]@{schemaVersion=1;createdUtc=[DateTime]::UtcNow.ToString('o');deploymentRoot=$configuration.deploymentRoot;files=$files})
    Write-Output ([IO.Path]::GetFullPath($BaselinePath))
    return
}

if ($Action -eq 'Plan') {
    $baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
    if ($baseline.deploymentRoot -ne $configuration.deploymentRoot) { throw 'Baseline belongs to another deployment root.' }
    foreach ($relative in $targets) {
        $matches = @($baseline.files | Where-Object target -EQ $relative)
        if ($matches.Count -ne 1) { throw "Missing baseline for $relative" }
        if ((Get-FileDigest (Resolve-SafeChild $configuration.deploymentRoot $relative)) -ne $matches[0].sha256) { throw "Target changed since baseline: $relative" }
    }
    $id = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $planDirectory = Join-Path $codeRoot ('.local/deployments/' + $id)
    [void][IO.Directory]::CreateDirectory($planDirectory)
    $planFile = Join-Path $planDirectory 'manifest.json'
    $files = New-Object Collections.Generic.List[object]
    foreach ($entry in $mapping.files) {
        $source = Resolve-SafeChild $RuntimeRoot $entry.source
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Build artifact is missing: $source" }
        $stagedRelative = 'staged/' + $entry.target.Replace('\','/')
        $staged = Resolve-SafeChild $planDirectory $stagedRelative
        [void][IO.Directory]::CreateDirectory((Split-Path $staged -Parent))
        [IO.File]::Copy($source, $staged, $false)
        $before = ($baseline.files | Where-Object target -EQ $entry.target).sha256
        $after = Get-FileDigest $staged
        $files.Add([ordered]@{target=$entry.target;source=$entry.source;staged=$stagedRelative;backup=('backup/' + $entry.target);beforeSha256=$before;afterSha256=$after;state='planned';error=$null})
    }
    $runtimeConfiguration = [ordered]@{}
    $configTarget = Resolve-SafeChild $configuration.deploymentRoot $mapping.mergedRuntimeConfig
    if (Test-Path -LiteralPath $configTarget) {
        $existing = Get-Content -LiteralPath $configTarget -Raw | ConvertFrom-Json
        foreach ($property in $existing.PSObject.Properties) { $runtimeConfiguration[$property.Name] = $property.Value }
    }
    $runtimeConfiguration.containerName = $configuration.containerName
    $runtimeConfiguration.historyTaskName = $configuration.historyTaskName
    $runtimeConfiguration.workspacePath = '/work'
    $stagedRelative = 'staged/' + $mapping.mergedRuntimeConfig
    $staged = Resolve-SafeChild $planDirectory $stagedRelative
    Write-DeploymentJson $staged $runtimeConfiguration
    $files.Add([ordered]@{target=$mapping.mergedRuntimeConfig;source='merged-local-configuration';staged=$stagedRelative;backup=('backup/' + $mapping.mergedRuntimeConfig);beforeSha256=(Get-FileDigest $configTarget);afterSha256=(Get-FileDigest $staged);state='planned';error=$null})
    $manifest = [ordered]@{
        schemaVersion=1;id=$id;createdUtc=[DateTime]::UtcNow.ToString('o');state='planned';error=$null
        productVersion=(Get-Content -LiteralPath (Join-Path $codeRoot 'VERSION') -Raw).Trim()
        deploymentRoot=$configuration.deploymentRoot;containerName=$configuration.containerName;historyTaskName=$configuration.historyTaskName
        files=@($files.ToArray());appliedUtc=$null;rolledBackUtc=$null
    }
    Write-DeploymentJson $planFile $manifest
    Write-Output $planFile
    return
}

if (-not $PlanPath) { throw 'Apply requires -PlanPath from a reviewed Plan.' }
$planFile = [IO.Path]::GetFullPath($PlanPath)
$planDirectory = Split-Path $planFile -Parent
$manifest = Get-Content -LiteralPath $planFile -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.state -ne 'planned') { throw 'Apply accepts only an unapplied schemaVersion 1 plan.' }
if ($manifest.deploymentRoot -ne $configuration.deploymentRoot -or $manifest.containerName -ne $configuration.containerName -or $manifest.historyTaskName -ne $configuration.historyTaskName) { throw 'Plan and local deployment configuration do not match.' }
$gate = $null
try {
    Assert-DeploymentIdle $configuration -Fixture:$Fixture
    $gate = Enter-DeploymentGate $configuration.deploymentRoot $manifest.id
    Assert-DeploymentIdle $configuration -Fixture:$Fixture
    # Preflight every component before changing any component.
    foreach ($entry in $manifest.files) {
        Assert-RuntimeTarget $entry.target
        $target = Resolve-SafeChild $configuration.deploymentRoot $entry.target
        $staged = Resolve-SafeChild $planDirectory $entry.staged
        if ((Get-FileDigest $target) -ne $entry.beforeSha256) { throw "Target changed since plan: $($entry.target)" }
        if ((Get-FileDigest $staged) -ne $entry.afterSha256) { throw "Staged artifact changed: $($entry.target)" }
        if ($null -ne $entry.beforeSha256) {
            $backup = Resolve-SafeChild $planDirectory $entry.backup
            [void][IO.Directory]::CreateDirectory((Split-Path $backup -Parent))
            [IO.File]::Copy($target, $backup, $false)
            if ((Get-FileDigest $backup) -ne $entry.beforeSha256) { throw "Backup verification failed: $($entry.target)" }
        }
    }
    $manifest.state = 'applying'
    Write-DeploymentJson $planFile $manifest
    foreach ($entry in $manifest.files) {
        try {
            Assert-DeploymentIdle $configuration -Fixture:$Fixture
            $target = Resolve-SafeChild $configuration.deploymentRoot $entry.target
            $staged = Resolve-SafeChild $planDirectory $entry.staged
            if ($entry.beforeSha256 -eq $entry.afterSha256) { $entry.state='unchanged' }
            else {
                Publish-AtomicFile $staged $target $entry.beforeSha256
                if ((Get-FileDigest $target) -ne $entry.afterSha256) { throw 'Post-replacement hash verification failed.' }
                $entry.state='applied'
            }
            Write-DeploymentJson $planFile $manifest
        } catch {
            $entry.state='failed'; $entry.error=$_.Exception.Message
            throw
        }
    }
    $manifest.state='applied'; $manifest.appliedUtc=[DateTime]::UtcNow.ToString('o')
    Write-DeploymentJson $planFile $manifest
} catch {
    $manifest.state='failed'; $manifest.error=$_.Exception.Message
    Write-DeploymentJson $planFile $manifest
    throw
} finally {
    if ($gate) { Exit-DeploymentGate $gate $manifest.id }
}
Write-Output $planFile
