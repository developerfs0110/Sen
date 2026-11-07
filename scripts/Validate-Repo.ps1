# scripts/Validate-Repo.ps1
# ASCII-only repository validation script for PowerShell 5.1+

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$Root = "."
)

$resolvedRoot = $null
try {
    $resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
}
catch {
    Write-Error "Invalid root path: $Root"
    if ($MyInvocation.InvocationName -ne '.') {
        exit 1
    }
    return @("Invalid root path: $Root")
}

$errors = [System.Collections.Generic.List[string]]::new()

# 1. Validate plugin.json
$pluginPath = Join-Path -Path $resolvedRoot -ChildPath "plugin.json"
if (Test-Path -LiteralPath $pluginPath) {
    try {
        $raw = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8
        $obj = ConvertFrom-Json -InputObject $raw
        $allowedFields = @(
            "name",
            "description",
            "logo",
            "suggestedPrompts",
            "displayName",
            "version",
            "author",
            "homepage",
            "repository",
            "disabled"
        )
        foreach ($prop in $obj.PSObject.Properties.Name) {
            if ($prop -notin $allowedFields) {
                $errors.Add("unknown plugin.json field: $prop")
            }
        }

        # Check required values per Global Constraints
        if ($obj.name -ne "sen-method") {
            $errors.Add("plugin.json name must be sen-method")
        }
        if ($obj.displayName -ne "Sen") {
            $errors.Add("plugin.json displayName must be Sen")
        }

        $expectedAuthor = "Mr B" + [char]0x00F2 + "n Bon"
        $actualAuthor = $null
        if ($obj.author -is [string]) {
            $actualAuthor = $obj.author
        }
        elseif ($obj.author -and $obj.author.name) {
            $actualAuthor = $obj.author.name
        }
        if ($actualAuthor -ne $expectedAuthor) {
            $errors.Add("plugin.json author.name must be $expectedAuthor")
        }
    }
    catch {
        $errors.Add("invalid plugin.json: $($_.Exception.Message)")
    }
}

# 2. Validate skills
$skillsDir = Join-Path -Path $resolvedRoot -ChildPath "skills"
if (Test-Path -LiteralPath $skillsDir) {
    $skillFolders = Get-ChildItem -LiteralPath $skillsDir -Directory
    foreach ($folder in $skillFolders) {
        $folderName = $folder.Name
        if (-not $folderName.StartsWith("sen-")) {
            $errors.Add("skill name must start with sen-: $folderName")
        }
        $skillMd = Join-Path -Path $folder.FullName -ChildPath "SKILL.md"
        if (Test-Path -LiteralPath $skillMd) {
            $skillContent = Get-Content -LiteralPath $skillMd -Raw -Encoding UTF8
            if ($skillContent -match "(?s)^---\s*\r?\n(.*?)\r?\n---") {
                $fm = $matches[1]
                if ($fm -match "(?m)^name:\s*([^\r\n#]+)") {
                    $fmName = $matches[1].Trim()
                    $fmName = $fmName.Trim(@([char]34, [char]39))
                    if ($fmName -ne $folderName) {
                        $errors.Add("skill name mismatch: $folderName (frontmatter has '$fmName')")
                    }
                }
            }
        }
    }
}

# 3. Validate rules/AGENTS.md size limit and line count
$agentsMd = Join-Path -Path $resolvedRoot -ChildPath "rules/AGENTS.md"
if (Test-Path -LiteralPath $agentsMd) {
    $fInfo = Get-Item -LiteralPath $agentsMd
    if ($fInfo.Length -gt 6000) {
        $errors.Add("rules/AGENTS.md exceeds 6000 bytes ($($fInfo.Length) bytes)")
    }
    $lines = @(Get-Content -LiteralPath $agentsMd)
    if ($lines.Count -gt 99) {
        $errors.Add("rules/AGENTS.md exceeds 99 lines ($($lines.Count) lines)")
    }
}

# 4. Validate personal data in rules/, skills/, templates/, scripts/, and INSTALL.md
$scanDirs = @("rules", "skills", "templates", "scripts")
$scanFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($d in $scanDirs) {
    $dp = Join-Path -Path $resolvedRoot -ChildPath $d
    if (Test-Path -LiteralPath $dp) {
        $items = Get-ChildItem -LiteralPath $dp -File -Recurse
        foreach ($it in $items) {
            $scanFiles.Add($it)
        }
    }
}
$installPath = Join-Path -Path $resolvedRoot -ChildPath "INSTALL.md"
if (Test-Path -LiteralPath $installPath) {
    $scanFiles.Add((Get-Item -LiteralPath $installPath))
}

$personalDataPattern = 'TUNBH[\\/]Workspace|[a-z]:[\\/]TUNBH'
foreach ($f in $scanFiles) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($text)) { continue }
    if ($text -match $personalDataPattern) {
        $rel = $f.FullName.Substring($resolvedRoot.Length).TrimStart("\/")
        $errors.Add("personal data in $rel")
    }
}

# 5. Validate broken relative markdown links
$mdFiles = Get-ChildItem -LiteralPath $resolvedRoot -Filter "*.md" -File -Recurse | Where-Object {
    $_.FullName -notmatch '[\\/](\.git|\.superpowers|\.gemini|\.agents|\.sen-restore|\.sen-backup)[\\/]'
}
foreach ($md in $mdFiles) {
    $rawMd = Get-Content -LiteralPath $md.FullName -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($rawMd)) { continue }

    $cleanMd = [regex]::Replace($rawMd, '(?s)```.*?```', '')
    $cleanMd = [regex]::Replace($cleanMd, '`.*?`', '')

    $linkMatches = [regex]::Matches($cleanMd, '\[(.*?)\]\((.*?)\)')
    foreach ($lm in $linkMatches) {
        $inner = $lm.Groups[2].Value.Trim()
        if ([string]::IsNullOrEmpty($inner)) { continue }

        $url = $null
        if ($inner -match '^<([^>]+)>') {
            $url = $matches[1].Trim()
        }
        else {
            $tokens = $inner -split '\s+'
            $url = $tokens[0].Trim().Trim(@([char]34, [char]39))
        }

        if ([string]::IsNullOrEmpty($url)) { continue }
        if ($url -match '^(?i)(https?|ftp|mailto):') { continue }
        if ($url.StartsWith("#")) { continue }

        $pathOnly = $url.Split('#')[0].Split('?')[0].Trim()
        if ([string]::IsNullOrEmpty($pathOnly)) { continue }

        try {
            $pathOnly = [System.Uri]::UnescapeDataString($pathOnly)
        }
        catch { <# Keep raw pathOnly if percent-encoding is literal #> }

        $targetFullPath = $null
        if ($pathOnly.StartsWith("/") -or $pathOnly.StartsWith("\")) {
            $targetFullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($resolvedRoot, $pathOnly.TrimStart("/\")))
        }
        else {
            $targetFullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($md.DirectoryName, $pathOnly))
        }

        if (-not (Test-Path -LiteralPath $targetFullPath)) {
            $relSource = $md.FullName.Substring($resolvedRoot.Length).TrimStart("\/")
            $errors.Add("broken link in ${relSource}: target '$url' not found")
        }
    }
}

# 6. Validate ASCII-only encoding in .ps1 and .psm1 files
$psFiles = Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse | Where-Object {
    ($_.Extension -eq ".ps1" -or $_.Extension -eq ".psm1") -and
    ($_.FullName -notmatch '[\\/](\.git|\.superpowers|\.gemini|\.agents|\.sen-restore|\.sen-backup)[\\/]')
}
foreach ($psf in $psFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($psf.FullName)
    foreach ($b in $bytes) {
        if ($b -ge 128) {
            $rel = $psf.FullName.Substring($resolvedRoot.Length).TrimStart("\/")
            $errors.Add("non-ASCII character in $rel")
            break
        }
    }
}

# 7. Validate README.md and README.vi.md stay synchronized when both exist
$readmeMain = Join-Path -Path $resolvedRoot -ChildPath "README.md"
$readmeVi   = Join-Path -Path $resolvedRoot -ChildPath "README.vi.md"
if ((Test-Path -LiteralPath $readmeMain) -and (Test-Path -LiteralPath $readmeVi)) {
    $tMain = ([System.IO.File]::ReadAllText($readmeMain, [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Trim()
    $tVi   = ([System.IO.File]::ReadAllText($readmeVi, [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Trim()
    if ($tMain -ne $tVi) {
        $errors.Add("README.md and README.vi.md are out of sync")
    }
}

# 8. Validate 5-Layer Zero-Amnesia Capability Parity when Sen module and manifest are present
$senModPath = Join-Path -Path $resolvedRoot -ChildPath "scripts/Sen.psm1"
$senManifestPath = Join-Path -Path $resolvedRoot -ChildPath "scripts/process-manifest.json"
if ((Test-Path -LiteralPath $senModPath) -and (Test-Path -LiteralPath $senManifestPath)) {
    Import-Module -Name $senModPath -Global -Force -ErrorAction SilentlyContinue
    if (Get-Command -Name "Test-SenCapabilityParity" -ErrorAction SilentlyContinue) {
        $parity = Test-SenCapabilityParity -SenRoot $resolvedRoot
        if (-not $parity.Passed) {
            foreach ($mi in @($parity.MissingItems)) {
                $errors.Add("capability parity gap: $mi")
            }
        }
    }
}

$isDotSourced = ($MyInvocation.InvocationName -eq '.')

if ($errors.Count -gt 0) {
    Write-Output $errors
    if (-not $isDotSourced) {
        exit 1
    }
}
else {
    if (-not $isDotSourced) {
        exit 0
    }
}
