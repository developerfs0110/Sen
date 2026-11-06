# tests/Skills.Tests.ps1
# Pure ASCII tests for INSTALL.md and skills/sen-*/SKILL.md

. "$PSScriptRoot/Assert.ps1"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
$skillsRoot = Join-Path -Path $repoRoot -ChildPath "skills"
$installMdPath = Join-Path -Path $repoRoot -ChildPath "INSTALL.md"

# Ruling R3: Task 7 checks sen-setup; Tasks 8 and 9 extend this list.
$Expected = @(
    'sen-setup',
    'sen-environment',
    'sen-update',
    'sen-onboarding',
    'sen-delivery-report',
    'sen-release-readiness',
    'sen-skill-capture'
)

$RequiredStrings = @{
    'sen-setup' = @(
        'Get-SenDriveCandidates',
        'install.ps1',
        'profile.md',
        ("File " + [char]0x2192 + " Open Folder"),
        'register-schedule.ps1'
    )
    'sen-environment' = @(
        'Get-SenInstallPlan',
        'Required',
        'ask_question',
        'is_multi_select',
        '(Recommended) Install all',
        'winget',
        'brew',
        '-v'
    )
    'sen-update' = @(
        'Get-SenUpdateStatus',
        'Update-SenPackages',
        'Restore-SenPackage',
        'sen-update-notice.md'
    )
    'sen-onboarding' = @(
        'profile.md',
        'Tier 1',
        'sen-setup'
    )
    'sen-delivery-report' = @(
        'verification-before-completion',
        'report.template.md'
    )
    'sen-release-readiness' = @(
        'security-audit',
        'vn-law-check',
        'dispatching-parallel-agents',
        'PASS',
        'WARN',
        'BLOCK'
    )
    'sen-skill-capture' = @(
        'writing-skills',
        'sen-'
    )
}

function Get-Utf8Text {
    param([string]$Path)
    $full = (Resolve-Path -LiteralPath $Path).Path
    return [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
}

function Get-FrontmatterField {
    param(
        [string]$Content,
        [string]$FieldName
    )
    if ($Content -notmatch "(?s)^---\s*\r?\n(.*?)\r?\n---") {
        return $null
    }
    $fm = $matches[1]
    $pattern = "(?m)^" + [regex]::Escape($FieldName) + ":\s*(.+?)\s*$"
    if ($fm -match $pattern) {
        $val = $matches[1].Trim()
        $val = $val.Trim(@([char]34, [char]39))
        return $val
    }
    return $null
}

Test "INSTALL.md exists at repository root" {
    Assert-True (Test-Path -LiteralPath $installMdPath) "INSTALL.md must exist at repo root"
}

Test "INSTALL.md contains developerfs0110/Sen and sen-setup" {
    Assert-True (Test-Path -LiteralPath $installMdPath) "INSTALL.md must exist"
    $text = Get-Utf8Text -Path $installMdPath
    Assert-True ($text.Contains("developerfs0110/Sen")) "INSTALL.md must contain 'developerfs0110/Sen'"
    Assert-True ($text.Contains("sen-setup")) "INSTALL.md must contain 'sen-setup'"
}

foreach ($s in $Expected) {
    $skillPath = Join-Path -Path $skillsRoot -ChildPath "$s/SKILL.md"

    Test "skills/$s/SKILL.md exists" {
        Assert-True (Test-Path -LiteralPath $skillPath) "skills/$s/SKILL.md must exist"
    }

    Test "skills/$s/SKILL.md has valid frontmatter name and description <= 300 chars" {
        Assert-True (Test-Path -LiteralPath $skillPath) "skills/$s/SKILL.md must exist"
        $text = Get-Utf8Text -Path $skillPath
        $fmName = Get-FrontmatterField -Content $text -FieldName "name"
        $fmDesc = Get-FrontmatterField -Content $text -FieldName "description"

        Assert-Equal $s $fmName "Frontmatter name must match directory '$s'"
        Assert-True (-not [string]::IsNullOrWhiteSpace($fmDesc)) "Frontmatter description must be non-empty for '$s'"
        Assert-True ($fmDesc.Length -le 300) "Frontmatter description for '$s' must be <= 300 chars (got $($fmDesc.Length))"
    }

    Test "skills/$s/SKILL.md is at most 12000 bytes" {
        Assert-True (Test-Path -LiteralPath $skillPath) "skills/$s/SKILL.md must exist"
        $full = (Resolve-Path -LiteralPath $skillPath).Path
        $byteLen = [System.IO.File]::ReadAllBytes($full).Length
        Assert-True ($byteLen -le 12000) "skills/$s/SKILL.md must be <= 12000 bytes (got $byteLen)"
    }

    if ($RequiredStrings.ContainsKey($s)) {
        $needles = $RequiredStrings[$s]
        for ($i = 0; $i -lt $needles.Count; $i++) {
            $needle = $needles[$i]
            Test "skills/$s/SKILL.md contains required string #$($i + 1) ($needle)" {
                Assert-True (Test-Path -LiteralPath $skillPath) "skills/$s/SKILL.md must exist"
                $text = Get-Utf8Text -Path $skillPath
                Assert-True ($text.Contains($needle)) "skills/$s/SKILL.md must contain '$needle'"
            }
        }
    }
}

Test "Expected skills list contains all 7 skills and matches skills/ directories" {
    Assert-Equal 7 $Expected.Count "Expected skills count must be 7"
    $dirs = @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Select-Object -ExpandProperty Name)
    Assert-Equal 7 $dirs.Count "skills/ must contain exactly 7 directories (got $($dirs.Count))"
    foreach ($d in $dirs) {
        Assert-True ($Expected -contains $d) "Directory 'skills/$d' must be in Expected list"
    }
}

Test "skills/sen-delivery-report/report.template.md exists and is non-empty" {
    $tplPath = Join-Path -Path $skillsRoot -ChildPath "sen-delivery-report/report.template.md"
    Assert-True (Test-Path -LiteralPath $tplPath) "skills/sen-delivery-report/report.template.md must exist"
    $tplText = Get-Utf8Text -Path $tplPath
    Assert-True (-not [string]::IsNullOrWhiteSpace($tplText)) "report.template.md must be non-empty"
}

$ChecklistFiles = @(
    'app-store.md',
    'licenses.md',
    'accessibility.md',
    'performance.md',
    'seo.md',
    'operations.md'
)

foreach ($cf in $ChecklistFiles) {
    $cfPath = Join-Path -Path $skillsRoot -ChildPath "sen-release-readiness/checklists/$cf"
    Test "skills/sen-release-readiness/checklists/$cf exists with 8 to 15 checklist items" {
        Assert-True (Test-Path -LiteralPath $cfPath) "skills/sen-release-readiness/checklists/$cf must exist"
        $cfText = Get-Utf8Text -Path $cfPath
        $itemCount = ([regex]::Matches($cfText, '(?m)^\s*-\s*\[[ xX]\]\s+.+')).Count
        Assert-True ($itemCount -ge 8 -and $itemCount -le 15) "Checklist $cf must have 8..15 items (got $itemCount)"
        Assert-True ($cfText.Contains("BLOCK") -or $cfText.Contains("WARN")) "Checklist $cf must denote BLOCK or WARN severity"
    }
}
