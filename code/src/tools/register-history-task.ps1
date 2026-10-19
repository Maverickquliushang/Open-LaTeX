[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Preview)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'runtime-config.ps1')
$settings = Get-OpenLaTeXRuntime
$runner = Join-Path $PSScriptRoot 'HistoryTaskRunner.exe'
$session = Join-Path $PSScriptRoot 'history-session.ps1'
foreach ($file in @($runner,$session)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw ('Required runtime file is missing: ' + $file) }
}
$arguments = '"' + $session + '" "' + $settings.Root + '"'
$fullTaskName = $settings.HistoryTaskName.TrimStart('\')
$separator = $fullTaskName.LastIndexOf('\')
$taskName = if ($separator -lt 0) { $fullTaskName } else { $fullTaskName.Substring($separator + 1) }
$taskPath = if ($separator -lt 0) { '\' } else { '\' + $fullTaskName.Substring(0,$separator + 1) }
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$plan = [ordered]@{
    taskName=$taskName; taskPath=$taskPath; executable=$runner
    arguments=$arguments; workingDirectory=$settings.Root; user=$user
    logonType='Interactive'; runLevel='Limited'; triggers=@()
    multipleInstances='IgnoreNew'; executionTimeLimit='PT0S'
}
if ($Preview) { $plan | ConvertTo-Json -Depth 4; return }
Import-Module ScheduledTasks -ErrorAction Stop
$existing = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
if ($existing) {
    if (@($existing.Actions).Count -eq 1 -and @($existing.Triggers | Where-Object { $null -ne $_ }).Count -eq 0 -and
        $existing.Actions[0].Execute -eq $runner -and $existing.Actions[0].Arguments -eq $arguments -and
        $existing.Actions[0].WorkingDirectory -eq $settings.Root) {
        Write-Output 'The existing on-demand task already points to this runtime; its settings were preserved.'
        return
    }
    throw 'A different task already uses this name. Inspect it and choose a distinct task name; this script does not overwrite existing tasks.'
}
$action = New-ScheduledTaskAction -Execute $runner -Argument $arguments -WorkingDirectory $settings.Root
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
$task = New-ScheduledTask -Action $action -Principal $principal -Settings $taskSettings -Description 'Open-LaTeX history session; started only when the workspace launcher requests it. No automatic triggers.'
if ($PSCmdlet.ShouldProcess($taskPath + $taskName, 'Register on-demand Open-LaTeX history task without triggers')) {
    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -InputObject $task -ErrorAction Stop | Out-Null
    Write-Output 'Registered on-demand history task with no automatic triggers. The task has not been started.'
}
