# tests/Validate-Repo.Tests.ps1
# ASCII-only tests for Validate-Repo.ps1

. "$PSScriptRoot/Assert.ps1"

$validateScript = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Validate-Repo.ps1"

function New-MockRepo {
    $tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen_test_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    return $tempDir
}

function Remove-MockRepo {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "plugin.json with unknown field foo reports unknown plugin.json field: foo" {
    $repo = New-MockRepo
    try {
        $json = @{
            name = "sen-method"
            version = "0.1.0"
            foo = "bar"
        } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $repo "plugin.json") -Value $json -Encoding UTF8

        if (-not (Test-Path -LiteralPath $validateScript)) {
            throw "Validate-Repo.ps1 script not found at $validateScript"
        }
        $errors = @(& $validateScript -Root $repo)
        $hasMatch = $false
        foreach ($err in $errors) {
            if ($err -like "*unknown plugin.json field: foo*") {
                $hasMatch = $true
                break
            }
        }
        Assert-True $hasMatch "Expected 'unknown plugin.json field: foo' in errors: $($errors -join '; ')"
    }
    finally {
        Remove-MockRepo $repo
    }
}

Test "skill directory not starting with sen- reports skill name must start with sen-: abc" {
    $repo = New-MockRepo
    try {
        $json = @{
            name = "sen-method"
            version = "0.1.0"
        } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $repo "plugin.json") -Value $json -Encoding UTF8

        $skillDir = Join-Path $repo "skills/abc"
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
        $skillContent = @"
---
name: abc
description: test
---
# Skill
"@
        Set-Content -LiteralPath (Join-Path $skillDir "SKILL.md") -Value $skillContent -Encoding UTF8

        if (-not (Test-Path -LiteralPath $validateScript)) {
            throw "Validate-Repo.ps1 script not found at $validateScript"
        }
        $errors = @(& $validateScript -Root $repo)
        $hasMatch = $false
        foreach ($err in $errors) {
            if ($err -like "*skill name must start with sen-: abc*") {
                $hasMatch = $true
                break
            }
        }
        Assert-True $hasMatch "Expected 'skill name must start with sen-: abc' in errors: $($errors -join '; ')"
    }
    finally {
        Remove-MockRepo $repo
    }
}

Test "skill name mismatch in frontmatter reports skill name mismatch: sen-y" {
    $repo = New-MockRepo
    try {
        $json = @{
            name = "sen-method"
            version = "0.1.0"
        } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $repo "plugin.json") -Value $json -Encoding UTF8

        $skillDir = Join-Path $repo "skills/sen-y"
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
        $skillContent = @"
---
name: sen-x
description: test
---
# Skill
"@
        Set-Content -LiteralPath (Join-Path $skillDir "SKILL.md") -Value $skillContent -Encoding UTF8

        if (-not (Test-Path -LiteralPath $validateScript)) {
            throw "Validate-Repo.ps1 script not found at $validateScript"
        }
        $errors = @(& $validateScript -Root $repo)
        $hasMatch = $false
        foreach ($err in $errors) {
            if ($err -like "*skill name mismatch: sen-y*") {
                $hasMatch = $true
                break
            }
        }
        Assert-True $hasMatch "Expected 'skill name mismatch: sen-y' in errors: $($errors -join '; ')"
    }
    finally {
        Remove-MockRepo $repo
    }
}

Test "rules/AGENTS.md with 6001 bytes reports rules/AGENTS.md exceeds 6000 bytes" {
    $repo = New-MockRepo
    try {
        $json = @{
            name = "sen-method"
            version = "0.1.0"
        } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $repo "plugin.json") -Value $json -Encoding UTF8

        $rulesDir = Join-Path $repo "rules"
        New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
        $largeContent = New-Object string('A', 6001)
        [System.IO.File]::WriteAllText((Join-Path $rulesDir "AGENTS.md"), $largeContent, [System.Text.Encoding]::ASCII)

        if (-not (Test-Path -LiteralPath $validateScript)) {
            throw "Validate-Repo.ps1 script not found at $validateScript"
        }
        $errors = @(& $validateScript -Root $repo)
        $hasMatch = $false
        foreach ($err in $errors) {
            if ($err -like "*rules/AGENTS.md exceeds 6000 bytes*") {
                $hasMatch = $true
                break
            }
        }
        Assert-True $hasMatch "Expected 'rules/AGENTS.md exceeds 6000 bytes' in errors: $($errors -join '; ')"
    }
    finally {
        Remove-MockRepo $repo
    }
}

Test "personal data detection matches in skills/ and ignores exempt README" {
    $repo = New-MockRepo
    try {
        $json = @{
            name = "sen-method"
            version = "0.1.0"
        } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $repo "plugin.json") -Value $json -Encoding UTF8

        $skillDir = Join-Path $repo "skills/sen-test"
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
        $skillContent = @"
---
name: sen-test
description: test
---
Path: D:\TUNBH\Workspace\secret
"@
        Set-Content -LiteralPath (Join-Path $skillDir "SKILL.md") -Value $skillContent -Encoding UTF8

        $readmeContent = @"
# Sen Method
Author: Mr Bon Bon - tunbh.study@gmail.com
"@
        Set-Content -LiteralPath (Join-Path $repo "README.md") -Value $readmeContent -Encoding UTF8

        if (-not (Test-Path -LiteralPath $validateScript)) {
            throw "Validate-Repo.ps1 script not found at $validateScript"
        }
        $errors = @(& $validateScript -Root $repo)
        $hasMatch = $false
        $hasReadmeFalsePositive = $false
        foreach ($err in $errors) {
            if ($err -like "*personal data in*") {
                if ($err -like "*skills/sen-test*" -or $err -like "*skills\sen-test*") {
                    $hasMatch = $true
                }
                if ($err -like "*README*") {
                    $hasReadmeFalsePositive = $true
                }
            }
        }
        Assert-True $hasMatch "Expected 'personal data in' for skills/sen-test in errors: $($errors -join '; ')"
        Assert-True (-not $hasReadmeFalsePositive) "README.md must be exempt from personal data checks"
    }
    finally {
        Remove-MockRepo $repo
    }
}

Test "relative markdown link to non-existent file reports broken link" {
    $repo = New-MockRepo
    try {
        $json = @{
            name = "sen-method"
            version = "0.1.0"
        } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $repo "plugin.json") -Value $json -Encoding UTF8

        $readmeContent = @"
# Overview
See [Missing Guide](docs/missing-guide.md) for details.
"@
        Set-Content -LiteralPath (Join-Path $repo "README.md") -Value $readmeContent -Encoding UTF8

        if (-not (Test-Path -LiteralPath $validateScript)) {
            throw "Validate-Repo.ps1 script not found at $validateScript"
        }
        $errors = @(& $validateScript -Root $repo)
        $hasMatch = $false
        foreach ($err in $errors) {
            if ($err -like "*broken link*") {
                $hasMatch = $true
                break
            }
        }
        Assert-True $hasMatch "Expected 'broken link' in errors: $($errors -join '; ')"
    }
    finally {
        Remove-MockRepo $repo
    }
}

Test "minimal valid repository produces zero errors" {
    $repo = New-MockRepo
    try {
        $json = @{
            name = "sen-method"
            displayName = "Sen"
            version = "0.1.0"
        } | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $repo "plugin.json") -Value $json -Encoding UTF8

        $docsDir = Join-Path $repo "docs"
        New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $docsDir "guide.md") -Value "# Guide Content" -Encoding UTF8

        $readmeContent = @"
# Overview
See [Guide](docs/guide.md) for details.
Also see external [Google](https://google.com) and anchor [Section](#overview).
"@
        Set-Content -LiteralPath (Join-Path $repo "README.md") -Value $readmeContent -Encoding UTF8

        $skillDir = Join-Path $repo "skills/sen-setup"
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
        $skillContent = @"
---
name: sen-setup
description: Workspace setup
---
# Setup Skill
"@
        Set-Content -LiteralPath (Join-Path $skillDir "SKILL.md") -Value $skillContent -Encoding UTF8

        $rulesDir = Join-Path $repo "rules"
        New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rulesDir "AGENTS.md") -Value "Always follow instructions." -Encoding UTF8

        if (-not (Test-Path -LiteralPath $validateScript)) {
            throw "Validate-Repo.ps1 script not found at $validateScript"
        }
        $errors = @(& $validateScript -Root $repo)
        Assert-Equal 0 @($errors).Count "Minimal valid repo must have 0 errors, got: $($errors -join '; ')"
    }
    finally {
        Remove-MockRepo $repo
    }
}
