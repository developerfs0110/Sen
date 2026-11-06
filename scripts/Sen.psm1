# scripts/Sen.psm1
# Pure ASCII PowerShell module for Sen workspace and drive helpers

function Test-SenDriveWritable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )
    if ([string]::IsNullOrEmpty($Root)) { return $false }
    $cleanRoot = $Root
    if ($cleanRoot -match '^[a-zA-Z]:$') {
        $cleanRoot = $cleanRoot + "\"
    }
    $testFile = Join-Path -Path $cleanRoot -ChildPath ".sen-write-test"
    try {
        [System.IO.File]::WriteAllText($testFile, "sen-probe")
        if (Test-Path -LiteralPath $testFile) {
            Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        }
        return $true
    }
    catch {
        return $false
    }
}

function Get-SenDriveCandidates {
    [CmdletBinding()]
    param(
        [Parameter(DontShow = $true)]
        [scriptblock]$DriveSource = $null
    )

    if ($null -eq $DriveSource) {
        $DriveSource = {
            $items = [System.Collections.Generic.List[object]]::new()
            try {
                $drives = [System.IO.DriveInfo]::GetDrives()
                foreach ($d in $drives) {
                    try {
                        if (-not $d.IsReady) { continue }
                        $r = $d.RootDirectory.FullName
                        $freeBytes = $d.AvailableFreeSpace
                        $freeGB = [double]($freeBytes / 1GB)
                        $writable = Test-SenDriveWritable -Root $r
                        $items.Add([pscustomobject]@{
                            Root = $r
                            FreeGB = $freeGB
                            Writable = $writable
                        })
                    }
                    catch { }
                }
            }
            catch { }
            return $items
        }
    }

    $raw = & $DriveSource
    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $raw) {
        if ($null -eq $item) { continue }

        $root = $null
        if ($item.PSObject.Properties['Root']) {
            $root = [string]$item.Root
        }
        elseif ($item.PSObject.Properties['RootDirectory']) {
            $root = [string]$item.RootDirectory.FullName
        }
        elseif ($item.PSObject.Properties['Name']) {
            $root = [string]$item.Name
        }
        else {
            $root = [string]$item
        }

        $freeGB = 0.0
        if ($item.PSObject.Properties['FreeGB'] -and $null -ne $item.FreeGB) {
            $freeGB = [double]$item.FreeGB
        }
        elseif ($item.PSObject.Properties['AvailableFreeSpace'] -and $null -ne $item.AvailableFreeSpace) {
            $freeGB = [double]($item.AvailableFreeSpace / 1GB)
        }
        elseif ($item.PSObject.Properties['TotalFreeSpace'] -and $null -ne $item.TotalFreeSpace) {
            $freeGB = [double]($item.TotalFreeSpace / 1GB)
        }

        $writable = $false
        if ($item.PSObject.Properties['Writable'] -and $null -ne $item.Writable) {
            $writable = [bool]$item.Writable
        }
        else {
            $writable = Test-SenDriveWritable -Root $root
        }

        if ($writable -and $freeGB -gt 1.0) {
            $candidates.Add([pscustomobject]@{
                Root = $root
                FreeGB = [double][Math]::Round($freeGB, 2)
                Writable = [bool]$writable
            })
        }
    }

    $sorted = $candidates | Sort-Object -Property FreeGB -Descending
    return @($sorted)
}

function New-SenWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$TemplateRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    }

    $wsSource = $null
    if (Test-Path -LiteralPath (Join-Path $TemplateRoot "workspace")) {
        $wsSource = (Resolve-Path -LiteralPath (Join-Path $TemplateRoot "workspace")).Path
    }
    elseif (Test-Path -LiteralPath $TemplateRoot) {
        $wsSource = (Resolve-Path -LiteralPath $TemplateRoot).Path
    }

    $standardRelDirs = @(
        ".agents/rules",
        ".agents/plugins",
        ".agents/skills",
        "Code",
        "Templates",
        "docs"
    )

    $relDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $standardRelDirs) {
        $relDirs.Add($d)
    }

    if ($wsSource -and (Test-Path -LiteralPath $wsSource)) {
        $files = Get-ChildItem -LiteralPath $wsSource -File -Recurse
        foreach ($f in $files) {
            $parentDir = $f.DirectoryName
            $rel = $parentDir.Substring($wsSource.Length).TrimStart("\/")
            $normalizedRel = $rel -replace '\\', '/'
            if ($normalizedRel -and -not $relDirs.Contains($normalizedRel)) {
                $relDirs.Add($normalizedRel)
            }
        }
    }

    $created = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()

    foreach ($rel in $relDirs) {
        $targetSubDir = Join-Path -Path $Path -ChildPath ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $targetSubDir) {
            $skipped.Add($rel)
        }
        else {
            [System.IO.Directory]::CreateDirectory($targetSubDir) | Out-Null
            $created.Add($rel)
        }

        if ($wsSource) {
            $srcDir = Join-Path -Path $wsSource -ChildPath ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (Test-Path -LiteralPath $srcDir) {
                $filesInSrc = Get-ChildItem -LiteralPath $srcDir -File
                foreach ($sf in $filesInSrc) {
                    $targetFile = Join-Path -Path $targetSubDir -ChildPath $sf.Name
                    if (-not (Test-Path -LiteralPath $targetFile)) {
                        Copy-Item -LiteralPath $sf.FullName -Destination $targetFile -Force
                    }
                }
            }
        }
    }

    return [pscustomobject]@{
        Created = [string[]]$created.ToArray()
        Skipped = [string[]]$skipped.ToArray()
    }
}

function New-SenFileFromTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,
        [Parameter(Mandatory = $true)]
        [string]$Destination,
        [Parameter(Mandatory = $false)]
        [hashtable]$Values = @{}
    )

    if (Test-Path -LiteralPath $Destination) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Template)) {
        throw "Template not found: $Template"
    }

    $templateResolved = (Resolve-Path -LiteralPath $Template).Path
    $content = [System.IO.File]::ReadAllText($templateResolved, [System.Text.Encoding]::UTF8)

    if ($null -ne $Values) {
        foreach ($key in $Values.Keys) {
            $placeholder = "{{" + $key + "}}"
            $val = if ($null -eq $Values[$key]) { "" } else { [string]$Values[$key] }
            $content = $content.Replace($placeholder, $val)
        }
    }

    $destDir = [System.IO.Path]::GetDirectoryName($Destination)
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        [System.IO.Directory]::CreateDirectory($destDir) | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Destination, $content, $utf8NoBom)

    return $true
}

Export-ModuleMember -Function Get-SenDriveCandidates, New-SenWorkspace, New-SenFileFromTemplate
