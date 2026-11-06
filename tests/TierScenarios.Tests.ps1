# tests/TierScenarios.Tests.ps1
# Automated verification of all 32 tier classification scenarios in tests/tier-scenarios.md (ASCII-only)

. "$PSScriptRoot/Assert.ps1"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
Import-Module $senModule -Force

$scenariosPath = Join-Path -Path $PSScriptRoot -ChildPath "tier-scenarios.md"

Test "tests/tier-scenarios.md exists and has 32 scenarios" {
    Assert-True (Test-Path -LiteralPath $scenariosPath) "tier-scenarios.md must exist"
}

$lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $scenariosPath).Path, [System.Text.Encoding]::UTF8)
$scenarioRows = [System.Collections.Generic.List[object]]::new()
$inResults = $false

foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -match '^##\s+Results') {
        $inResults = $true
        continue
    }
    if ($inResults) { continue }
    if ($t.StartsWith("|") -and $t.EndsWith("|")) {
        $cols = @($t.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($cols.Count -ge 3) {
            $reqCol = $cols[0]
            $tierCol = $cols[1]
            if ($reqCol -eq "---" -or $reqCol -match '^Y.u c.u$') { continue }
            $expectedTier = -1
            if ($tierCol -match '1') { $expectedTier = 1 }
            elseif ($tierCol -match '2') { $expectedTier = 2 }
            elseif ($tierCol -match '3') { $expectedTier = 3 }
            elseif ($tierCol -match '(?i)(no label|kh.ng nh.n)') { $expectedTier = 0 }
            if ($expectedTier -ge 0) {
                $scenarioRows.Add([pscustomobject]@{
                    Request      = $reqCol
                    ExpectedTier = $expectedTier
                    RawTierLabel = $tierCol
                })
            }
        }
    }
}

Test "tier-scenarios.md contains exactly 32 parsed scenarios" {
    Assert-Equal 32 $scenarioRows.Count "Expected 32 scenarios in tier-scenarios.md, got $($scenarioRows.Count)"
}

$idx = 0
foreach ($row in $scenarioRows) {
    $idx++
    $r = $row
    Test "Tier scenario #$idx matches expected tier ($($r.ExpectedTier))" {
        $res = Get-SenTaskRiskScore -Request $r.Request
        Assert-Equal $r.ExpectedTier $res.Tier "Scenario #$idx ('$($r.Request)') expected tier $($r.ExpectedTier) but got $($res.Tier) (reasons: $($res.Reasons -join '; '))"
    }
}
