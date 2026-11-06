# tests/Skills.Tests.ps1
# Pure ASCII tests for INSTALL.md and skills/sen-*/SKILL.md

. "$PSScriptRoot/Assert.ps1"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
$skillsRoot = Join-Path -Path $repoRoot -ChildPath "skills"
$installMdPath = Join-Path -Path $repoRoot -ChildPath "INSTALL.md"

# Ruling R3: Task 7 checks sen-setup; Tasks 8 and 9 extend this list.
$Expected = @(
    'sen-setup'
)

$RequiredStrings = @{
    'sen-setup' = @(
        'Get-SenDriveCandidates',
        'install.ps1',
        'profile.md',
        ("File " + [char]0x2192 + " Open Folder"),
        'register-schedule.ps1'
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

Test "INSTALL.md contains <owner>/sen-method and sen-setup" {
    Assert-True (Test-Path -LiteralPath $installMdPath) "INSTALL.md must exist"
    $text = Get-Utf8Text -Path $installMdPath
    Assert-True ($text.Contains("<owner>/sen-method")) "INSTALL.md must contain '<owner>/sen-method'"
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
