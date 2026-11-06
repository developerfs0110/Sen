# tests/Rule.Tests.ps1
# ASCII-only tests for rules/AGENTS.md (the always-on core rule)

. "$PSScriptRoot/Assert.ps1"

$rulePath = Join-Path -Path $PSScriptRoot -ChildPath "../rules/AGENTS.md"

function Get-RuleText {
    $full = (Resolve-Path -LiteralPath $rulePath).Path
    return [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
}

Test "rules/AGENTS.md exists" {
    Assert-True (Test-Path -LiteralPath $rulePath) "rules/AGENTS.md must exist"
}

Test "rules/AGENTS.md is at most 6000 bytes" {
    $full = (Resolve-Path -LiteralPath $rulePath).Path
    $len = [System.IO.File]::ReadAllBytes($full).Length
    Assert-True ($len -le 6000) "rules/AGENTS.md must be <= 6000 bytes (got $len)"
}

Test "rules/AGENTS.md has fewer than 100 lines" {
    $text = Get-RuleText
    $lineCount = @($text -split "`n").Count
    if ($text.EndsWith("`n")) { $lineCount-- }
    Assert-True ($lineCount -lt 100) "rules/AGENTS.md must be < 100 lines (got $lineCount)"
}

$required = @(
    "Tier 1", "Tier 2", "Tier 3",
    ("[C" + [char]0x1EA5 + "p 1"),
    "just do it", "CONTEXT.md", "flash_lite",
    "verification-before-completion", "security-audit", "vn-law-check",
    "sen-environment", "sen-delivery-report", "sen-skill-capture",
    "using-superpowers", "Native", "Subagent-driven",
    ("2" + [char]0x2013 + "3"),
    "project's AGENTS.md",
    "If the sen-office plugin is installed, also follow its rules."
)
for ($i = 0; $i -lt $required.Count; $i++) {
    $needle = $required[$i]
    Test "rules/AGENTS.md contains required string #$($i + 1)" {
        Assert-True ((Get-RuleText).Contains($needle)) "rules/AGENTS.md must contain required string #$($i + 1)"
    }
}

Test "rules/AGENTS.md contains no personal path and no fallback comment" {
    $text = Get-RuleText
    Assert-True (-not $text.Contains("TUNBH")) "rules/AGENTS.md must not contain 'TUNBH'"
    Assert-True (-not $text.Contains("Copied by sen-setup")) "rules/AGENTS.md must not contain the fallback copy comment"
}
