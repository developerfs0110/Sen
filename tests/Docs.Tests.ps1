# tests/Docs.Tests.ps1
# ASCII-only tests for README.md, README.vi.md, docs/guide.md, and docs/huong-dan.md

. "$PSScriptRoot/Assert.ps1"

$repoRoot    = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
$readmeEn    = Join-Path -Path $repoRoot -ChildPath "README.md"
$readmeVi    = Join-Path -Path $repoRoot -ChildPath "README.vi.md"
$guideEn     = Join-Path -Path $repoRoot -ChildPath "docs/guide.md"
$guideVi     = Join-Path -Path $repoRoot -ChildPath "docs/huong-dan.md"
$validatePs1 = Join-Path -Path $repoRoot -ChildPath "scripts/Validate-Repo.ps1"

function Get-Utf8Text {
    param([string]$Path)
    Assert-True (Test-Path -LiteralPath $Path) "File must exist: $Path"
    $full = (Resolve-Path -LiteralPath $Path).Path
    return [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
}

function Get-H2Headings {
    param([string]$Text)
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^##\s+(.+?)\s*$') {
            $list.Add($matches[1])
        }
    }
    return ,$list.ToArray()
}

# Build Vietnamese strings from Unicode code points so this file stays 100% ASCII
$authorLine1 = "Mr B" + [char]0x00F2 + "n Bon - tunbh.study@gmail.com"
$authorLine2 = "(+84) 793.166.866 - (+84) 96.158.1163"
$authorLine3 = "Donate: TPBank - 61.222.666.888"

# Vietnamese slogan (Spec Section 1)
$sloganVi = "Sen: l" + [char]0x00E0 + "m vi" + [char]0x1EC7 + "c v" + [char]0x1EDB + "i " +
    [char]0x0111 + [char]0x1ED9 + "i AI m" + [char]0x1ED9 + "t c" + [char]0x00E1 + "ch g" +
    [char]0x1ECD + "n, r" + [char]0x00F5 + ", nh" + [char]0x1EB9 + "."
$sloganEn = "Calm, clear AI work."

# 5 Principles in Vietnamese (Spec Section 1)
$principlesVi = @(
    ([char]0x0110 + [char]0x00FA + "ng m" + [char]0x1EE9 + "c ki" + [char]0x1EC3 + "m so" + [char]0x00E1 + "t"),
    ("Minh b" + [char]0x1EA1 + "ch"),
    ("C" + [char]0x00F3 + " b" + [char]0x1EB1 + "ng ch" + [char]0x1EE9 + "ng m" + [char]0x1EDB + "i b" + [char]0x00E1 + "o xong"),
    ("G" + [char]0x1ECD + "n nh" + [char]0x1EB9 + " m" + [char]0x1EB7 + "c " + [char]0x0111 + [char]0x1ECB + "nh"),
    ("T" + [char]0x00ED + "ch l" + [char]0x0169 + "y")
)

$principlesEn = @(
    "Right level of control",
    "Transparent",
    "Evidence before claiming done",
    "Lean by default",
    "Compound over time"
)

Test "README.md and README.vi.md exist and cross-link on line 1" {
    Assert-True (Test-Path -LiteralPath $readmeEn) "README.md must exist"
    Assert-True (Test-Path -LiteralPath $readmeVi) "README.vi.md must exist"

    $enLines = (Get-Utf8Text $readmeEn) -split "`r?`n"
    $viLines = (Get-Utf8Text $readmeVi) -split "`r?`n"

    Assert-True ($enLines[0] -match '\[.+?\]\(README\.vi\.md\)') "Line 1 of README.md must link to README.vi.md"
    Assert-True ($viLines[0] -match '\[.+?\]\(README\.md\)') "Line 1 of README.vi.md must link to README.md"
}

Test "README.md and README.vi.md have the 8 sections in Spec 10.1 order" {
    $enText = Get-Utf8Text $readmeEn
    $viText = Get-Utf8Text $readmeVi

    # Section 1 is # Sen + slogan at the top, followed by 7 ## headings (Sections 2..8)
    Assert-True ($enText -match '(?m)^#\s+Sen\b') "README.md must have # Sen title (Section 1)"
    Assert-True ($viText -match '(?m)^#\s+Sen\b') "README.vi.md must have # Sen title (Section 1)"

    $enH2 = Get-H2Headings $enText
    $viH2 = Get-H2Headings $viText

    Assert-Equal 7 $enH2.Count "README.md must have 7 ## headings (Spec 10.1 sections 2-8)"
    Assert-Equal 7 $viH2.Count "README.vi.md must have 7 ## headings (Spec 10.1 sections 2-8)"

    Assert-True ($enH2[0] -match 'What Sen Is') "README.md section 2 heading"
    Assert-True ($enH2[1] -match 'Problem') "README.md section 3 heading"
    Assert-True ($enH2[2] -match 'Five Principles') "README.md section 4 heading"
    Assert-True ($enH2[3] -match 'How Sen Works') "README.md section 5 heading"
    Assert-True ($enH2[4] -match 'Quick Start') "README.md section 6 heading"
    Assert-True ($enH2[5] -match 'What Sen Uses') "README.md section 7 heading"
    Assert-True ($enH2[6] -match 'Author & Support') "README.md section 8 heading"

    # Vietnamese H2 checks
    $viSec2 = "Sen l" + [char]0x00E0 + " g" + [char]0x00EC
    $viSec3 = "V" + [char]0x1EA5 + "n " + [char]0x0111 + [char]0x1EC1 + " Sen gi" + [char]0x1EA3 + "i quy" + [char]0x1EBF + "t"
    $viSec4 = "N" + [char]0x0103 + "m nguy" + [char]0x00EA + "n l" + [char]0x00FD
    $viSec5 = "Sen ho" + [char]0x1EA1 + "t " + [char]0x0111 + [char]0x1ED9 + "ng th" + [char]0x1EBF + " n" + [char]0x00E0 + "o"
    $viSec6 = "B" + [char]0x1EAF + "t " + [char]0x0111 + [char]0x1EA7 + "u nhanh"
    $viSec7 = "Sen d" + [char]0x00F9 + "ng nh" + [char]0x1EEF + "ng g" + [char]0x00EC
    $viSec8 = "T" + [char]0x00E1 + "c gi" + [char]0x1EA3 + " & " + [char]0x1EE6 + "ng h" + [char]0x1ED9

    Assert-True ($viH2[0].Contains($viSec2)) "README.vi.md section 2 heading"
    Assert-True ($viH2[1].Contains($viSec3)) "README.vi.md section 3 heading"
    Assert-True ($viH2[2].Contains($viSec4)) "README.vi.md section 4 heading"
    Assert-True ($viH2[3].Contains($viSec5)) "README.vi.md section 5 heading"
    Assert-True ($viH2[4].Contains($viSec6)) "README.vi.md section 6 heading"
    Assert-True ($viH2[5].Contains($viSec7)) "README.vi.md section 7 heading"
    Assert-True ($viH2[6].Contains($viSec8)) "README.vi.md section 8 heading"
}

Test "Both READMEs contain verbatim slogan, 5 principles, Mermaid diagram, office placeholder, credits, and author block" {
    $enText = Get-Utf8Text $readmeEn
    $viText = Get-Utf8Text $readmeVi

    Assert-True ($enText.Contains($sloganEn)) "README.md must contain English slogan"
    Assert-True ($viText.Contains($sloganVi)) "README.vi.md must contain Vietnamese slogan"

    foreach ($p in $principlesEn) {
        Assert-True ($enText.Contains($p)) "README.md must contain principle: $p"
    }
    foreach ($p in $principlesVi) {
        Assert-True ($viText.Contains($p)) "README.vi.md must contain principle: $p"
    }

    foreach ($txt in @($enText, $viText)) {
        Assert-True ($txt.Contains('```mermaid')) "README must contain a Mermaid diagram"
        Assert-True ($txt.Contains('<!-- office screenshot: added with sen-office -->')) "README must contain office screenshot HTML comment"
        Assert-True ($txt.Contains('<owner>/sen-method')) "README must contain <owner>/sen-method install URL"
        Assert-True ($txt.Contains('superpowers') -and $txt.Contains('Jesse Vincent') -and $txt.Contains('MIT')) "README must credit superpowers (Jesse Vincent, MIT)"
        Assert-True ($txt.Contains('security-audit') -and $txt.Contains('Cloudflare') -and $txt.Contains('MIT')) "README must credit security-audit (Cloudflare, MIT)"
        Assert-True ($txt.Contains('vn-law-check') -and $txt.Contains('vn-web-compliance-audit') -and $txt.Contains('MIT')) "README must credit vn-law-check (Contributors to vn-web-compliance-audit, MIT)"
        Assert-True ($txt.Contains($authorLine1)) "README must contain author line 1"
        Assert-True ($txt.Contains($authorLine2)) "README must contain author line 2"
        Assert-True ($txt.Contains($authorLine3)) "README must contain author line 3"
    }

    Assert-True ($enText -match '\[.+?\]\(docs/guide\.md\)') "README.md must link to docs/guide.md"
    Assert-True ($viText -match '\[.+?\]\(docs/huong-dan\.md\)') "README.vi.md must link to docs/huong-dan.md"
}

Test "docs/huong-dan.md and docs/guide.md have 9 sections per Spec 10.2, tier-scenarios examples, and author footer" {
    Assert-True (Test-Path -LiteralPath $guideVi) "docs/huong-dan.md must exist"
    Assert-True (Test-Path -LiteralPath $guideEn) "docs/guide.md must exist"

    $viText = Get-Utf8Text $guideVi
    $enText = Get-Utf8Text $guideEn

    $viH2 = Get-H2Headings $viText
    $enH2 = Get-H2Headings $enText

    Assert-Equal 9 $viH2.Count "docs/huong-dan.md must have 9 ## headings (Spec 10.2)"
    Assert-Equal 9 $enH2.Count "docs/guide.md must have 9 ## headings (Spec 10.2)"

    for ($i = 1; $i -le 9; $i++) {
        Assert-True ($viH2[$i - 1].StartsWith("$i.")) "docs/huong-dan.md heading #$i must start with '$i.'"
        Assert-True ($enH2[$i - 1].StartsWith("$i.")) "docs/guide.md heading #$i must start with '$i.'"
    }

    # Check <owner>/sen-method placeholder and ZIP installation mention
    Assert-True ($viText.Contains('<owner>/sen-method')) "docs/huong-dan.md must use <owner>/sen-method"
    Assert-True ($enText.Contains('<owner>/sen-method')) "docs/guide.md must use <owner>/sen-method"
    Assert-True ($viText -match '(?i)\.zip') "docs/huong-dan.md must cover ZIP download"
    Assert-True ($enText -match '(?i)\.zip') "docs/guide.md must cover ZIP download"

    # Check exact examples from tests/tier-scenarios.md
    $viEx1 = [char]0x0110 + [char]0x1ED5 + "i m" + [char]0x00E0 + "u n" + [char]0x00FA + "t"
    $viEx2 = "Th" + [char]0x00EA + "m ch" + [char]0x1EE9 + "c n" + [char]0x0103 + "ng l" + [char]0x1ECD + "c s" + [char]0x1EA3 + "n ph" + [char]0x1EA9 + "m theo gi" + [char]0x00E1
    $viEx3 = "L" + [char]0x00E0 + "m m" + [char]0x1ED9 + "t website b" + [char]0x00E1 + "n h" + [char]0x00E0 + "ng m" + [char]0x1EDB + "i cho ti" + [char]0x1EC7 + "m b" + [char]0x00E1 + "nh"

    Assert-True ($viText.Contains($viEx1)) "docs/huong-dan.md must include Tier 1 scenario from tier-scenarios.md"
    Assert-True ($viText.Contains($viEx2)) "docs/huong-dan.md must include Tier 2 scenario from tier-scenarios.md"
    Assert-True ($viText.Contains($viEx3)) "docs/huong-dan.md must include Tier 3 scenario from tier-scenarios.md"

    Assert-True ($enText.Contains('Fix the typo "Welcom" on the home page')) "docs/guide.md must include Tier 1 scenario from tier-scenarios.md"
    Assert-True ($enText.Contains('Add dark mode to the app')) "docs/guide.md must include Tier 2 scenario from tier-scenarios.md"
    Assert-True ($enText.Contains('Build a new mobile app for booking appointments')) "docs/guide.md must include Tier 3 scenario from tier-scenarios.md"

    foreach ($txt in @($viText, $enText)) {
        Assert-True ($txt.Contains('profile.md')) "Guide must cover profile.md"
        Assert-True ($txt.Contains('AGENTS.md')) "Guide must cover project AGENTS.md"
        Assert-True ($txt.Contains('CONTEXT.md')) "Guide must cover CONTEXT.md"
        Assert-True ($txt.Contains($authorLine1)) "Guide must contain author line 1"
        Assert-True ($txt.Contains($authorLine2)) "Guide must contain author line 2"
        Assert-True ($txt.Contains($authorLine3)) "Guide must contain author line 3"
    }
}

Test "Validate-Repo.ps1 passes with 0 errors across the repository" {
    $errs = @(& $validatePs1 -Root $repoRoot)
    Assert-Equal 0 $errs.Count ("Validate-Repo.ps1 reported errors: " + ($errs -join "; "))
}
