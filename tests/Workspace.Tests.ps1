# tests/Workspace.Tests.ps1
# Pure ASCII unit tests for Sen.psm1 and templates

. "$PSScriptRoot/Assert.ps1"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
$templatesDir = Join-Path -Path $PSScriptRoot -ChildPath "../templates"
$workspaceTemplateDir = Join-Path -Path $templatesDir -ChildPath "workspace"

# Import Sen module
Import-Module -Name $senModule -Force

function New-MockTempDir {
    param([string]$Suffix = "")
    $guid = [System.Guid]::NewGuid().ToString("N")
    $name = if ($Suffix) { "sen_ws_${guid}_${Suffix}" } else { "sen_ws_${guid}" }
    $tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $name
    if (-not (Test-Path -LiteralPath $tempDir)) {
        [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null
    }
    return $tempDir
}

function Remove-MockTempDir {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Get-SenDriveCandidates filters non-writable and small drives and sorts descending" {
    $mockSource = {
        @(
            [pscustomobject]@{ Root = "C:\"; FreeGB = 10.0; Writable = $true },
            [pscustomobject]@{ Root = "D:\"; FreeGB = 200.0; Writable = $true },
            [pscustomobject]@{ Root = "E:\"; FreeGB = 500.0; Writable = $false },
            [pscustomobject]@{ Root = "F:\"; FreeGB = 0.5; Writable = $true }
        )
    }

    $candidates = @(Get-SenDriveCandidates -DriveSource $mockSource)
    Assert-Equal 2 $candidates.Count "Expected exactly 2 valid candidates"

    # Must be sorted FreeGB descending: D (200) then C (10)
    Assert-Equal "D:\" $candidates[0].Root "First candidate must be D:\"
    Assert-Equal 200.0 $candidates[0].FreeGB "First candidate FreeGB must be 200"
    Assert-Equal $true $candidates[0].Writable "First candidate must be Writable"

    Assert-Equal "C:\" $candidates[1].Root "Second candidate must be C:\"
    Assert-Equal 10.0 $candidates[1].FreeGB "Second candidate FreeGB must be 10"
    Assert-Equal $true $candidates[1].Writable "Second candidate must be Writable"
}

Test "Get-SenDriveCandidates returns empty array when no drives qualify" {
    $mockSource = {
        @(
            [pscustomobject]@{ Root = "E:\"; FreeGB = 500.0; Writable = $false },
            [pscustomobject]@{ Root = "F:\"; FreeGB = 0.8; Writable = $true }
        )
    }

    $candidates = @(Get-SenDriveCandidates -DriveSource $mockSource)
    Assert-Equal 0 $candidates.Count "Expected 0 candidates when none qualify"
}

Test "New-SenWorkspace creates 6 directories on empty folder with unicode name and skips on second call" {
    # Build 'Du an Thu' using char codes for ASCII compliance
    $vnName = -join @(
        [char]0x0044, # D
        [char]0x1EF1, # u with dot below and horn
        [char]0x0020, # space
        [char]0x00E1, # a with acute
        [char]0x006E, # n
        [char]0x0020, # space
        [char]0x0054, # T
        [char]0x0068, # h
        [char]0x1EED  # u with hook above and horn
    )

    $parentDir = New-MockTempDir
    $targetDir = Join-Path -Path $parentDir -ChildPath $vnName

    try {
        # First call: empty directory should create all 6 folders
        $res1 = New-SenWorkspace -Path $targetDir -TemplateRoot $workspaceTemplateDir
        Assert-Equal 6 $res1.Created.Count "First call should create 6 directories"
        Assert-Equal 0 $res1.Skipped.Count "First call should skip 0 directories"

        # Verify all 6 exist
        $expectedFolders = @(
            ".agents/rules",
            ".agents/plugins",
            ".agents/skills",
            "Code",
            "Templates",
            "docs"
        )
        foreach ($folder in $expectedFolders) {
            $fullPath = Join-Path -Path $targetDir -ChildPath ($folder -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            Assert-True (Test-Path -LiteralPath $fullPath) "Directory should exist: $folder"
        }

        # Second call: should skip all 6 folders and create 0
        $res2 = New-SenWorkspace -Path $targetDir -TemplateRoot $workspaceTemplateDir
        Assert-Equal 0 $res2.Created.Count "Second call should create 0 directories"
        Assert-Equal 6 $res2.Skipped.Count "Second call should skip 6 directories"
    }
    finally {
        Remove-MockTempDir $parentDir
    }
}

Test "New-SenWorkspace does not overwrite existing safety.md file" {
    $parentDir = New-MockTempDir
    try {
        $safetyDir = Join-Path -Path $parentDir -ChildPath (Join-Path ".agents" "rules")
        [System.IO.Directory]::CreateDirectory($safetyDir) | Out-Null
        $safetyFile = Join-Path -Path $safetyDir -ChildPath "safety.md"
        [System.IO.File]::WriteAllText($safetyFile, "X")

        $res = New-SenWorkspace -Path $parentDir -TemplateRoot $workspaceTemplateDir
        Assert-True ($res.Skipped -contains ".agents/rules") ".agents/rules should be skipped"

        $content = [System.IO.File]::ReadAllText($safetyFile)
        Assert-Equal "X" $content "safety.md content must remain X"
    }
    finally {
        Remove-MockTempDir $parentDir
    }
}

Test "New-SenFileFromTemplate substitutes placeholder and refuses to overwrite" {
    $tempDir = New-MockTempDir
    try {
        $tplPath = Join-Path -Path $tempDir -ChildPath "test.template.md"
        [System.IO.File]::WriteAllText($tplPath, "Root path is {{WORKSPACE_ROOT}}.")

        $destPath = Join-Path -Path $tempDir -ChildPath "output.md"

        # First run creates file and replaces placeholder
        $created = New-SenFileFromTemplate -Template $tplPath -Destination $destPath -Values @{
            WORKSPACE_ROOT = "E:\Sen Work"
        }
        Assert-Equal $true $created "New-SenFileFromTemplate should return true on initial create"

        $content = [System.IO.File]::ReadAllText($destPath)
        Assert-Equal "Root path is E:\Sen Work." $content "Content should have placeholder substituted"

        # Second run should return false and leave file untouched
        $second = New-SenFileFromTemplate -Template $tplPath -Destination $destPath -Values @{
            WORKSPACE_ROOT = "CHANGED"
        }
        Assert-Equal $false $second "New-SenFileFromTemplate should return false when destination exists"

        $contentAfter = [System.IO.File]::ReadAllText($destPath)
        Assert-Equal "Root path is E:\Sen Work." $contentAfter "Content should not be modified on second run"
    }
    finally {
        Remove-MockTempDir $tempDir
    }
}

Test "New-SenFileFromTemplate writes UTF-8 without BOM" {
    $tempDir = New-MockTempDir
    try {
        $tplPath = Join-Path -Path $tempDir -ChildPath "unicode.template.md"
        # Write unicode string to template
        $utf8Text = "Name: {{NAME}} - " + [char]0x1EF1 # Vietnamese character
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($tplPath, $utf8Text, $utf8NoBom)

        $destPath = Join-Path -Path $tempDir -ChildPath "unicode.output.md"
        $created = New-SenFileFromTemplate -Template $tplPath -Destination $destPath -Values @{
            NAME = "Sen"
        }
        Assert-Equal $true $created "File should be created"

        # Check raw bytes for absence of UTF-8 BOM (0xEF, 0xBB, 0xBF)
        $bytes = [System.IO.File]::ReadAllBytes($destPath)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        Assert-Equal $false $hasBom "File should not contain UTF-8 BOM"

        # Read text to ensure valid decoding
        $readText = [System.IO.File]::ReadAllText($destPath, [System.Text.Encoding]::UTF8)
        $expectedText = "Name: Sen - " + [char]0x1EF1
        Assert-Equal $expectedText $readText "File content should match expected text"
    }
    finally {
        Remove-MockTempDir $tempDir
    }
}
