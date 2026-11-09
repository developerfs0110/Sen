# scripts/register-schedule.ps1
# Pure ASCII script to register per-user daily Sen update check in Windows Task Scheduler

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workspace,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($Workspace -match '["''`$;|&<>\r\n]') {
    throw "Invalid Workspace path: shell metacharacters are prohibited in scheduled task registration."
}
$Workspace = [System.IO.Path]::GetFullPath($Workspace)
$leaf = Split-Path -Path $Workspace -Leaf
if ([string]::IsNullOrEmpty($leaf)) {
    $leaf = $Workspace.TrimEnd('\/').Replace(':', '')
}
$taskName = "Sen update check ($leaf)"

$installedScript = Join-Path -Path $Workspace -ChildPath ".agents/plugins/sen-method/scripts/check-updates.ps1"
$scriptToRun = if (Test-Path -LiteralPath $installedScript) {
    $installedScript
}
else {
    Join-Path -Path $PSScriptRoot -ChildPath "check-updates.ps1"
}
if ($scriptToRun -match '["''`$;|&<>\r\n]') {
    throw "Invalid check-updates script path: shell metacharacters are prohibited."
}

$argumentString = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptToRun`" -Workspace `"$Workspace`""

$userId = if ($env:USERDOMAIN -and $env:USERNAME) {
    "$($env:USERDOMAIN)\$($env:USERNAME)"
}
elseif ($env:USERNAME) {
    $env:USERNAME
}
elseif ($env:USER) {
    $env:USER
}
else {
    try { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name } catch { [Environment]::UserName }
}

if ($DryRun) {
    Write-Output "DryRun: Would register task '$taskName'"
    Write-Output "Action: powershell.exe $argumentString"
    Write-Output "User: $userId"
    Write-Output "Trigger: Daily"
    return [pscustomobject]@{
        TaskName  = $taskName
        Action    = "powershell.exe $argumentString"
        User      = $userId
        Trigger   = "Daily"
        Workspace = $Workspace
        DryRun    = $true
    }
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentString
$trigger = New-ScheduledTaskTrigger -Daily -At "09:00"
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "Registered scheduled task '$taskName'"
