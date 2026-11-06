# scripts/install.ps1
# Non-interactive Sen installer (ASCII only). Prints one JSON result object as the last stdout line.
# Exit code: 0 on success, 1 on failure.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workspace,
    [switch]$WithVnLawCheck,
    [string]$SenSource = "",
    [Parameter(DontShow = $true)]
    [scriptblock]$Git = $null
)

$ErrorActionPreference = "Stop"

$result = [ordered]@{
    workspace     = $Workspace
    sen           = [ordered]@{ status = "failed" }
    packages      = @()
    lockWritten   = $false
    safetyCreated = $false
}
$ok = $true

try {
    Import-Module -Name (Join-Path $PSScriptRoot "Sen.psm1") -Force
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    if ([string]::IsNullOrEmpty($SenSource)) { $SenSource = $repoRoot }

    $Workspace = [System.IO.Path]::GetFullPath($Workspace)
    $result.workspace = $Workspace

    New-SenWorkspace -Path $Workspace -TemplateRoot (Join-Path $repoRoot "templates") | Out-Null

    $senArgs = @{ Workspace = $Workspace; Source = $SenSource }
    if ($Git) { $senArgs.Git = $Git }
    $sen = Install-SenSelf @senArgs
    $result.sen = [ordered]@{ status = $sen.Status }
    if ($sen.Commit) { $result.sen.commit = $sen.Commit }
    if ($sen.Error) { $result.sen.error = $sen.Error }
    if ($sen.Status -eq "failed") { $ok = $false }

    $safetyPath = Join-Path $Workspace ".agents/rules/safety.md"
    $result.safetyCreated = [bool](New-SenFileFromTemplate -Template (Join-Path $repoRoot "templates/safety.template.md") -Destination $safetyPath -Values @{ WORKSPACE_ROOT = $Workspace })

    $packages = Get-Content -LiteralPath (Join-Path $PSScriptRoot "packages.json") -Raw | ConvertFrom-Json
    $lock = Read-SenLock -Workspace $Workspace
    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    if ($sen.Status -ne "failed") {
        $oldSen = $lock.packages["sen-method"]
        if (-not ($sen.Status -eq "exists" -and $oldSen -is [hashtable] -and $oldSen.commit)) {
            $senCommit = if ($sen.Commit) { $sen.Commit } else { "unknown" }
            $senRepoUrl = if ($SenSource -match '^(https?://|git@)') { $SenSource } else { "https://github.com/<owner>/sen-method.git" }
            $lock.packages["sen-method"] = [ordered]@{ repo = $senRepoUrl; subPath = ""; commit = $senCommit; installedAt = $now }
        }
    }
    $pkgResults = @()
    $requiredOk = $true

    foreach ($pkg in @($packages)) {
        if (-not $pkg.required -and -not $WithVnLawCheck) { continue }
        $pArgs = @{ Workspace = $Workspace; Package = $pkg }
        if ($Git) { $pArgs.Git = $Git }
        $r = Install-SenPackage @pArgs
        $pkgResults += [ordered]@{ id = $r.Id; status = $r.Status; commit = $r.Commit; error = $r.Error }

        if ($r.Status -eq "failed") {
            if ($pkg.required) { $requiredOk = $false }
            continue
        }
        $old = $lock.packages[$r.Id]
        if ($r.Status -eq "exists" -and $old -is [hashtable] -and $old.commit) {
            continue
        }
        $commit = if ($r.Commit) { $r.Commit } else { "unknown" }
        $lock.packages[$r.Id] = [ordered]@{ repo = $pkg.repo; subPath = $pkg.subPath; commit = $commit; installedAt = $now }
    }
    $result.packages = $pkgResults

    if (-not $requiredOk) { $ok = $false }
    if ($ok) {
        Write-SenLock -Workspace $Workspace -Lock $lock
        $result.lockWritten = $true
    }
}
catch {
    $ok = $false
    $result.error = $_.Exception.Message
}

Write-Output (ConvertTo-Json -InputObject $result -Depth 6 -Compress)
if ($ok) { exit 0 } else { exit 1 }
