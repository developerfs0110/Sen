# scripts/check-updates.ps1
# Pure ASCII script to check package updates and maintain zero-token notice file

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workspace,
    [switch]$Force,
    [Parameter(DontShow = $true)]
    [scriptblock]$Git = $null
)

$ErrorActionPreference = "Stop"

Import-Module -Name (Join-Path $PSScriptRoot "Sen.psm1") -Force

$Workspace = [System.IO.Path]::GetFullPath($Workspace)
$lock = Read-SenLock -Workspace $Workspace
$nowUtc = [DateTime]::UtcNow

$gatePassed = $false
if ($Force) {
    $gatePassed = $true
}
elseif ([string]::IsNullOrEmpty($lock.lastUpdateCheck)) {
    $gatePassed = $true
}
else {
    try {
        $lastCheck = [DateTime]::Parse($lock.lastUpdateCheck, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
        $diffDays = ($nowUtc - $lastCheck).TotalDays
        if ($diffDays -ge 7.0) {
            $gatePassed = $true
        }
    }
    catch {
        $gatePassed = $true
    }
}

if (-not $gatePassed) {
    exit 0
}

# Run update check
$statusArgs = @{ Workspace = $Workspace }
if ($Git) { $statusArgs.Git = $Git }
$updates = @(Get-SenUpdateStatus @statusArgs)
$available = @($updates | Where-Object { $_.HasUpdate -eq $true })

$noticePath = Join-Path -Path $Workspace -ChildPath ".agents/rules/sen-update-notice.md"

if ($available.Count -gt 0) {
    $instruction = "Mention these updates once, in the user's language, and offer to run the sen-update skill."
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Sen Update Notice")
    $lines.Add("")
    $lines.Add("Updates are available for the following package(s):")
    $lines.Add("")
    foreach ($u in $available) {
        $lines.Add("- **$($u.Id)**: current '$($u.Current)', latest '$($u.Latest)'")
        if (-not [string]::IsNullOrWhiteSpace($u.Summary)) {
            $summaryLines = @($u.Summary -split "[\r\n]+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            foreach ($sl in ($summaryLines | Select-Object -First 3)) {
                $lines.Add("  * $sl")
            }
        }
    }
    $lines.Add("")
    $lines.Add($instruction)
    $lines.Add("")
    $content = $lines -join "`n"

    # Enforce at most 800 bytes
    $utf8Encoding = [System.Text.UTF8Encoding]::new($false)
    $bytes = $utf8Encoding.GetBytes($content)
    if ($bytes.Length -gt 800) {
        $shortLines = [System.Collections.Generic.List[string]]::new()
        $shortLines.Add("# Sen Update Notice")
        $shortLines.Add("")
        $shortLines.Add("Updates are available for:")
        foreach ($u in $available) {
            $shortLines.Add("- **$($u.Id)**: latest '$($u.Latest)'")
        }
        $shortLines.Add("")
        $shortLines.Add($instruction)
        $shortLines.Add("")
        $content = $shortLines -join "`n"
    }

    $rulesDir = Join-Path -Path $Workspace -ChildPath ".agents/rules"
    if (-not (Test-Path -LiteralPath $rulesDir)) {
        [System.IO.Directory]::CreateDirectory($rulesDir) | Out-Null
    }
    [System.IO.File]::WriteAllText($noticePath, $content, $utf8Encoding)
}
else {
    if (Test-Path -LiteralPath $noticePath) {
        Remove-Item -LiteralPath $noticePath -Force -ErrorAction SilentlyContinue
    }
}

# Update lastUpdateCheck in lock
$lock = Read-SenLock -Workspace $Workspace
$lock.lastUpdateCheck = $nowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-SenLock -Workspace $Workspace -Lock $lock

exit 0
