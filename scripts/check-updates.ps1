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

$noticePath = Join-Path -Path $Workspace -ChildPath ".agents/rules/sen-update-notice.md"

try {
    # Run update check
    $statusArgs = @{ Workspace = $Workspace }
    if ($Git) { $statusArgs.Git = $Git }
    $updates = @(Get-SenUpdateStatus @statusArgs)
    $available = @($updates | Where-Object { $_.HasUpdate -eq $true })

    if ($available.Count -gt 0) {
        $instruction = "Mention these updates once, in the user's language, and offer to run the sen-update skill."
        $utf8 = [System.Text.UTF8Encoding]::new($false)

        function Build-NoticeText {
            param(
                [object[]]$Items,
                [int]$OmittedCount,
                [bool]$WithSummary
            )
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine("# Sen Update Notice")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Updates are available for the following package(s):")
            [void]$sb.AppendLine("")
            foreach ($u in $Items) {
                [void]$sb.AppendLine("- **$($u.Id)**: current '$($u.Current)', latest '$($u.Latest)'")
                if ($WithSummary -and -not [string]::IsNullOrWhiteSpace($u.Summary)) {
                    # Cap commit summary at 3 lines per package to conserve token budget in the notice rule.
                    $lines = @($u.Summary -split "[\r\n]+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    foreach ($sl in ($lines | Select-Object -First 3)) {
                        $cleanSl = ($sl -replace '[<>`$|;]', '').Trim()
                        if ($cleanSl.Length -gt 100) { $cleanSl = $cleanSl.Substring(0, 100) }
                        [void]$sb.AppendLine("  * $cleanSl")
                    }
                }
            }
            if ($OmittedCount -gt 0) {
                [void]$sb.AppendLine("- *(+$OmittedCount more)*")
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine($instruction)
            return $sb.ToString().TrimEnd("`r`n") + "`n"
        }

        $finalContent = ""
        # 1. Full notice with summaries
        $cand = Build-NoticeText -Items $available -OmittedCount 0 -WithSummary $true
        if ($utf8.GetByteCount($cand) -le 800) {
            $finalContent = $cand
        }
        else {
            # 2. All packages without summaries
            $cand = Build-NoticeText -Items $available -OmittedCount 0 -WithSummary $false
            if ($utf8.GetByteCount($cand) -le 800) {
                $finalContent = $cand
            }
            else {
                # 3. Truncate package list and append (+N more)
                $fitted = $false
                for ($k = $available.Count - 1; $k -ge 1; $k--) {
                    $sub = @($available | Select-Object -First $k)
                    $omitted = $available.Count - $k
                    $cand = Build-NoticeText -Items $sub -OmittedCount $omitted -WithSummary $false
                    if ($utf8.GetByteCount($cand) -le 800) {
                        $finalContent = $cand
                        $fitted = $true
                        break
                    }
                }
                if (-not $fitted) {
                    $finalContent = "# Sen Update Notice`n`nUpdates are available (+$(@($available).Count) packages)`n`n$instruction`n"
                }
            }
        }

        $rulesDir = Join-Path -Path $Workspace -ChildPath ".agents/rules"
        if (-not (Test-Path -LiteralPath $rulesDir)) {
            [System.IO.Directory]::CreateDirectory($rulesDir) | Out-Null
        }
        [System.IO.File]::WriteAllText($noticePath, $finalContent, $utf8)
    }
    else {
        if (Test-Path -LiteralPath $noticePath) {
            Remove-Item -LiteralPath $noticePath -Force -ErrorAction SilentlyContinue
        }
    }
}
finally {
    # Item 7: check-updates.ps1 always updates lastUpdateCheck, even on a git failure
    $lock = Read-SenLock -Workspace $Workspace
    $lock.lastUpdateCheck = $nowUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-SenLock -Workspace $Workspace -Lock $lock
}

exit 0
