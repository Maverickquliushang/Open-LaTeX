param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../project-env.ps1')
$codeRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $codeRoot '.build' }
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$codePrefix = [IO.Path]::GetFullPath($codeRoot).TrimEnd('\') + '\'
if (-not $outputRoot.StartsWith($codePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Build output must remain inside code/.'
}
$runtime = Join-Path $outputRoot 'runtime'
$runtimeTools = Join-Path $runtime '.latex-tools'
$artifacts = Join-Path $outputRoot 'artifacts'
foreach ($directory in @($runtime, $runtimeTools, $artifacts)) {
    [void][IO.Directory]::CreateDirectory($directory)
}
$toolsSource = Join-Path $codeRoot 'src/tools'
$extensionSource = Join-Path $codeRoot 'src/extension'
$version = (Get-Content -LiteralPath (Join-Path $codeRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must contain a three-part numeric product version.' }
$assemblyInfo = Join-Path $artifacts 'AssemblyInfo.cs'
@"
using System.Reflection;
[assembly: AssemblyProduct("Open-LaTeX")]
[assembly: AssemblyVersion("$version.0")]
[assembly: AssemblyFileVersion("$version.0")]
[assembly: AssemblyInformationalVersion("$version")]
"@ | Set-Content -LiteralPath $assemblyInfo -Encoding UTF8
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework 4 C# compiler was not found.' }
& (Join-Path $toolsSource 'build-launcher-icon.ps1') -OutputDirectory $artifacts
& (Join-Path $toolsSource 'build-start-icon.ps1') -SourcePng (Join-Path $artifacts 'Open-LaTeX-preview.png') -OutputDirectory $artifacts
foreach ($entry in @(
    @{Source='OpenLaTeX.cs'; Output=(Join-Path $runtime 'Open-LaTeX.exe'); Icon='Open-LaTeX.ico'},
    @{Source='StartLaTeX.cs'; Output=(Join-Path $runtime 'Start-LaTeX.exe'); Icon='Start-LaTeX.ico'},
    @{Source='HistoryTaskRunner.cs'; Output=(Join-Path $runtimeTools 'HistoryTaskRunner.exe'); Icon='Open-LaTeX.ico'}
)) {
    & $compiler /nologo /target:winexe /optimize+ /platform:anycpu /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll ('/win32icon:' + (Join-Path $artifacts $entry.Icon)) ('/out:' + $entry.Output) (Join-Path $toolsSource $entry.Source) $assemblyInfo
    if ($LASTEXITCODE -ne 0) { throw ('C# compilation failed: ' + $entry.Source) }
}
foreach ($name in @('Open-LaTeX.cmd','Paper-History.cmd')) {
    Copy-Item -LiteralPath (Join-Path $toolsSource $name) -Destination (Join-Path $runtime $name) -Force
}
foreach ($name in @('launcher-runtime.ps1','runtime-config.ps1','register-history-task.ps1','history-session.ps1','history-scheduler.ps1','fast_build.py','audit_latex.py','paper_history.py','install-modern-texlive.sh')) {
    Copy-Item -LiteralPath (Join-Path $toolsSource $name) -Destination (Join-Path $runtimeTools $name) -Force
}
foreach ($name in @('Open-LaTeX.ico','Start-LaTeX.ico')) {
    Copy-Item -LiteralPath (Join-Path $artifacts $name) -Destination (Join-Path $runtimeTools $name) -Force
}
$metadata = Get-Content -LiteralPath (Join-Path $extensionSource 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$vsixName = 'paper-history-' + $metadata.version + '.vsix'
& python (Join-Path $PSScriptRoot 'package-extension.py') --source $extensionSource --output (Join-Path $artifacts $vsixName)
if ($LASTEXITCODE -ne 0) { throw 'Extension packaging failed.' }
Copy-Item -LiteralPath (Join-Path $artifacts $vsixName) -Destination (Join-Path $runtimeTools $vsixName) -Force
Copy-Item -LiteralPath (Join-Path $codeRoot 'config/runtime.example.json') -Destination (Join-Path $runtimeTools 'runtime.example.json') -Force
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $codeRoot) 'LICENSE') -Destination (Join-Path $runtime 'LICENSE') -Force
Copy-Item -LiteralPath (Join-Path $codeRoot 'config/RUNTIME_README.md') -Destination (Join-Path $runtime 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $codeRoot 'config/vscode-settings.json') -Destination (Join-Path $runtime 'vscode-settings.example.json') -Force
$allowedRuntimeFiles = @(
    'LICENSE','README.md','vscode-settings.example.json','Open-LaTeX.exe','Start-LaTeX.exe','Open-LaTeX.cmd','Paper-History.cmd',
    '.latex-tools/HistoryTaskRunner.exe','.latex-tools/launcher-runtime.ps1','.latex-tools/runtime-config.ps1',
    '.latex-tools/register-history-task.ps1','.latex-tools/history-session.ps1','.latex-tools/history-scheduler.ps1','.latex-tools/fast_build.py',
    '.latex-tools/audit_latex.py','.latex-tools/paper_history.py','.latex-tools/install-modern-texlive.sh',
    '.latex-tools/Open-LaTeX.ico','.latex-tools/Start-LaTeX.ico','.latex-tools/runtime.example.json',
    ('.latex-tools/' + $vsixName)
)
$unexpected = @(Get-ChildItem -LiteralPath $runtime -File -Recurse -Force | Where-Object {
    $_.FullName.Substring($runtime.Length + 1).Replace('\','/') -notin $allowedRuntimeFiles
})
if ($unexpected.Count) { throw 'Build runtime contains unrecognized files. Preserve that directory and choose a fresh project-local output directory.' }
$build = [ordered]@{
    productVersion=$version
    extensionVersion=$metadata.version
    generatedAt=(Get-Date -Format o)
    runtimeConfiguration='Copy .latex-tools/runtime.example.json to .latex-tools/runtime.json and set deployment values.'
    files=@(Get-ChildItem -LiteralPath $runtime -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{path=$_.FullName.Substring($runtime.Length + 1).Replace('\','/'); sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
}
$build | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputRoot 'build-manifest.json') -Encoding UTF8
Write-Output ('Runtime built: ' + $runtime)
