# scripts/uninstall.ps1
# Pure ASCII script to cleanly unregister Sen scheduled task and harness bridges

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Workspace = $PWD.Path,
    [switch]$RemovePluginDir,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$senMod = Join-Path -Path $PSScriptRoot -ChildPath "Sen.psm1"
if (Test-Path -LiteralPath $senMod) {
    Import-Module -Name $senMod -Global -Force
}

if (Get-Command Uninstall-SenSelf -ErrorAction SilentlyContinue) {
    $res = Uninstall-SenSelf -Workspace $Workspace -RemovePluginDir:$RemovePluginDir -DryRun:$DryRun
    Write-Output $res
}
