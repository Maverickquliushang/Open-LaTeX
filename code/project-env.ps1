$env:OPEN_LATEX_ROOT = Split-Path $PSScriptRoot -Parent
$env:OPEN_LATEX_CODE = $PSScriptRoot
foreach ($relative in @('.local', '.tmp', '.cache', '.cache/pip', '.cache/npm', '.cache/pycache')) {
    [void][System.IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot $relative))
}
$env:TEMP = Join-Path $PSScriptRoot '.tmp'
$env:TMP = $env:TEMP
$env:PYTHONPYCACHEPREFIX = Join-Path $PSScriptRoot '.cache/pycache'
$env:PYTHONUTF8 = '1'
$env:PIP_CACHE_DIR = Join-Path $PSScriptRoot '.cache/pip'
$env:npm_config_cache = Join-Path $PSScriptRoot '.cache/npm'
$env:DOTNET_CLI_HOME = Join-Path $PSScriptRoot '.cache/dotnet'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:NUGET_PACKAGES = Join-Path $PSScriptRoot '.cache/nuget'
