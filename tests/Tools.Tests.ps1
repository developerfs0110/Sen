# tests/Tools.Tests.ps1
# Pure ASCII unit tests for tool detection and install planning

. "$PSScriptRoot/Assert.ps1"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
$catalogPath = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/tools.json"

Import-Module -Name $senModule -Force

Test "Get-SenToolStatus returns ok when tool in PATH meets minVersion" {
    $runner = {
        param($cmd)
        if ($cmd -eq "node --version") { return "v20.11.0" }
        return $null
    }
    $status = Get-SenToolStatus -Id "node" -Catalog $catalogPath -Runner $runner
    Assert-Equal "node" $status.Id "Tool ID must match"
    Assert-Equal "ok" $status.Status "Status must be ok"
    Assert-Equal "20.11.0" $status.Version "Version must match cleaned version"
    Assert-Equal "PATH" $status.Source "Source must be PATH"
}

Test "Get-SenToolStatus returns outdated when tool in PATH is below minVersion" {
    $runner = {
        param($cmd)
        if ($cmd -eq "node --version") { return "v16.0.0" }
        return $null
    }
    $status = Get-SenToolStatus -Id "node" -Catalog $catalogPath -Runner $runner
    Assert-Equal "node" $status.Id "Tool ID must match"
    Assert-Equal "outdated" $status.Status "Status must be outdated"
    Assert-Equal "16.0.0" $status.Version "Version must match cleaned version"
    Assert-Equal "PATH" $status.Source "Source must be PATH"
}

Test "Get-SenToolStatus returns ok with Source nvm when missing in PATH but found in nvm list" {
    $runner = {
        param($cmd)
        if ($cmd -eq "node --version") { return $null }
        if ($cmd -eq "nvm list") {
            return "  16.14.0`n* 20.11.0 (Currently using 64-bit executable)`n  18.12.0"
        }
        return $null
    }
    $status = Get-SenToolStatus -Id "node" -Catalog $catalogPath -Runner $runner
    Assert-Equal "node" $status.Id "Tool ID must match"
    Assert-Equal "ok" $status.Status "Status must be ok"
    Assert-Equal "20.11.0" $status.Version "Version must match active nvm version"
    Assert-Equal "nvm" $status.Source "Source must be nvm"
}

Test "Get-SenToolStatus returns missing when tool is not found anywhere" {
    $runner = {
        param($cmd)
        return $null
    }
    $status = Get-SenToolStatus -Id "node" -Catalog $catalogPath -Runner $runner
    Assert-Equal "node" $status.Id "Tool ID must match"
    Assert-Equal "missing" $status.Status "Status must be missing"
    Assert-Equal $null $status.Version "Version should be null"
    Assert-Equal $null $status.Source "Source should be null"
}

Test "Get-SenToolStatus detects tool via extraPaths when missing in PATH" {
    $runner = {
        param($cmd)
        if ($cmd -eq "node --version") { return $null }
        if ($cmd -like "*node.exe*") { return "v20.11.0" }
        return $null
    }
    $pathChecker = {
        param($p)
        if ($p -like "*nodejs*node.exe") { return $true }
        return $false
    }
    $status = Get-SenToolStatus -Id "node" -Catalog $catalogPath -Runner $runner -PathChecker $pathChecker
    Assert-Equal "node" $status.Id "Tool ID must match"
    Assert-Equal "ok" $status.Status "Status must be ok"
    Assert-Equal "extraPath" $status.Source "Source must be extraPath"
}

Test "Get-SenInstallPlan returns single missing tool with winget install command" {
    $runner = {
        param($cmd)
        if ($cmd -eq "git --version") { return "git version 2.43.0.windows.1" }
        if ($cmd -eq "node --version") { return $null }
        return $null
    }
    $plan = Get-SenInstallPlan -Ids @("git", "node") -Required @("node") -Catalog $catalogPath -Platform "Windows" -Runner $runner
    Assert-Equal 1 $plan.Count "Plan should have exactly 1 tool"
    Assert-Equal "node" $plan[0].Id "Tool ID should be node"
    Assert-Equal "Node.js" $plan[0].DisplayName "DisplayName should match"
    Assert-Equal $true $plan[0].Required "Required should be true"
    Assert-True ($plan[0].Command.StartsWith("winget install")) "Command should start with winget install"
    Assert-True ($plan[0].Command -like "*OpenJS.NodeJS.LTS*") "Command should contain winget id"
}

Test "Get-SenInstallPlan generates brew command on macOS" {
    $runner = {
        param($cmd)
        return $null
    }
    $plan = Get-SenInstallPlan -Ids @("git") -Required @("git") -Catalog $catalogPath -Platform "macOS" -Runner $runner
    Assert-Equal 1 $plan.Count "Plan should have 1 tool"
    Assert-Equal "brew install git" $plan[0].Command "Command should be brew install git"
}

Test "Get-SenInstallPlan returns an array for 0, 1, and multiple items without unrolling" {
    $runnerAllOk = {
        param($cmd)
        if ($cmd -eq "git --version") { return "git version 2.43.0" }
        if ($cmd -eq "node --version") { return "v20.11.0" }
        return $null
    }
    $plan0 = Get-SenInstallPlan -Ids @("git", "node") -Catalog $catalogPath -Platform "Windows" -Runner $runnerAllOk
    Assert-True ($plan0 -is [array]) "Plan with 0 items must be an array"
    Assert-Equal 0 $plan0.Count "Plan with 0 items must have count 0"

    $runnerOneMissing = {
        param($cmd)
        if ($cmd -eq "git --version") { return "git version 2.43.0" }
        return $null
    }
    $plan1 = Get-SenInstallPlan -Ids @("git", "node") -Catalog $catalogPath -Platform "Windows" -Runner $runnerOneMissing
    Assert-True ($plan1 -is [array]) "Plan with 1 item must be an array"
    Assert-Equal 1 $plan1.Count "Plan with 1 item must have count 1"

    $runnerBothMissing = {
        param($cmd)
        return $null
    }
    $plan2 = Get-SenInstallPlan -Ids @("git", "node") -Catalog $catalogPath -Platform "Windows" -Runner $runnerBothMissing
    Assert-True ($plan2 -is [array]) "Plan with 2 items must be an array"
    Assert-Equal 2 $plan2.Count "Plan with 2 items must have count 2"
}

Test "Get-SenInstallPlan handles flutter with manualUrl on Windows and brew cask on macOS" {
    $runner = {
        param($cmd)
        return $null
    }
    $planWin = Get-SenInstallPlan -Ids @("flutter") -Catalog $catalogPath -Platform "Windows" -Runner $runner
    Assert-Equal 1 $planWin.Count "Flutter should be in plan on Windows"
    Assert-Equal $null $planWin[0].Command "Flutter command should be null on Windows since winget is null"
    Assert-Equal "https://docs.flutter.dev/get-started/install" $planWin[0].ManualUrl "ManualUrl must match flutter install docs"

    $planMac = Get-SenInstallPlan -Ids @("flutter") -Catalog $catalogPath -Platform "macOS" -Runner $runner
    Assert-Equal 1 $planMac.Count "Flutter should be in plan on macOS"
    Assert-Equal "brew install --cask flutter" $planMac[0].Command "Flutter command on macOS should use brew cask"
}

Test "Get-SenToolStatus returns missing when tool id is not in catalog" {
    $status = Get-SenToolStatus -Id "non-existent-tool" -Catalog $catalogPath
    Assert-Equal "non-existent-tool" $status.Id "Tool ID matches"
    Assert-Equal "missing" $status.Status "Status should be missing for unknown tool"
    Assert-Equal $null $status.Version "Version should be null"
}

Test "Get-SenToolStatus detects python and git correctly" {
    $runner = {
        param($cmd)
        if ($cmd -eq "python --version") { return "Python 3.12.1" }
        if ($cmd -eq "git --version") { return "git version 2.43.0.windows.1" }
        return $null
    }
    $pyStatus = Get-SenToolStatus -Id "python" -Catalog $catalogPath -Runner $runner
    Assert-Equal "python" $pyStatus.Id "Python ID"
    Assert-Equal "ok" $pyStatus.Status "Python status ok"
    Assert-Equal "3.12.1" $pyStatus.Version "Python version parsed"

    $gitStatus = Get-SenToolStatus -Id "git" -Catalog $catalogPath -Runner $runner
    Assert-Equal "git" $gitStatus.Id "Git ID"
    Assert-Equal "ok" $gitStatus.Status "Git status ok"
    Assert-Equal "2.43.0" $gitStatus.Version "Git version parsed"
}

Test "Get-SenToolStatus returns outdated when manager active version is below minVersion" {
    $runner = {
        param($cmd)
        if ($cmd -eq "node --version") { return $null }
        if ($cmd -eq "nvm list") {
            return "* 14.17.0`n  16.14.0"
        }
        return $null
    }
    $status = Get-SenToolStatus -Id "node" -Catalog $catalogPath -Runner $runner
    Assert-Equal "node" $status.Id "Tool ID must match"
    Assert-Equal "outdated" $status.Status "Status must be outdated when nvm version < 18.0.0"
    Assert-Equal "14.17.0" $status.Version "Version must match active version"
    Assert-Equal "nvm" $status.Source "Source must be nvm"
}

Test "Get-SenInstallPlan includes both missing and outdated tools with Required flags" {
    $runner = {
        param($cmd)
        if ($cmd -eq "git --version") { return "git version 2.43.0" }
        if ($cmd -eq "node --version") { return "v16.0.0" } # outdated
        if ($cmd -eq "python --version") { return $null }    # missing
        return $null
    }
    $plan = Get-SenInstallPlan -Ids @("git", "node", "python") -Required @("node") -Catalog $catalogPath -Platform "Windows" -Runner $runner
    Assert-Equal 2 $plan.Count "Plan should have 2 tools: node (outdated) and python (missing)"

    # node: required = true
    $nodeItem = $plan | Where-Object { $_.Id -eq "node" }
    Assert-True ($null -ne $nodeItem) "node must be in plan"
    Assert-Equal $true $nodeItem.Required "node should be marked Required=$true"
    Assert-Equal "outdated" $nodeItem.Status "node should have Status=outdated"
    Assert-Equal "16.0.0" $nodeItem.CurrentVersion "node should have CurrentVersion=16.0.0"

    # python: required = false
    $pythonItem = $plan | Where-Object { $_.Id -eq "python" }
    Assert-True ($null -ne $pythonItem) "python must be in plan"
    Assert-Equal $false $pythonItem.Required "python should be marked Required=$false"
    Assert-Equal "missing" $pythonItem.Status "python should have Status=missing"
    Assert-Equal $null $pythonItem.CurrentVersion "python CurrentVersion should be null"
}

Test "Get-SenToolCatalog and Get-SenToolStatus detect creative tools ffmpeg, imagemagick and blender" {
    $cat = Get-SenToolCatalog -CatalogPath $catalogPath
    foreach ($tid in @("ffmpeg", "imagemagick", "blender")) {
        $entry = @($cat | Where-Object { $_.id -eq $tid })[0]
        Assert-True ($null -ne $entry) "$tid must exist in tools.json"
        Assert-Equal $false ([bool]$entry.required) "$tid must be optional (required=false)"
    }

    $runner = {
        param($cmd)
        if ($cmd -match "ffmpeg") { return "ffmpeg version n6.1.1-full_build-www.gyan.dev Copyright (c) 2000-2024" }
        if ($cmd -match "magick") { return "Version: ImageMagick 7.1.1-38 Q16-HDRI x64" }
        if ($cmd -match "blender") { return "Blender 4.2.1" }
        return $null
    }

    $ff = Get-SenToolStatus -Id "ffmpeg" -Catalog $catalogPath -Runner $runner
    Assert-Equal "ok" $ff.Status "ffmpeg status must be ok"
    Assert-Equal "6.1.1" $ff.Version "ffmpeg version parsed cleanly"

    $im = Get-SenToolStatus -Id "imagemagick" -Catalog $catalogPath -Runner $runner
    Assert-Equal "ok" $im.Status "imagemagick status must be ok"
    Assert-Equal "7.1.1" $im.Version "imagemagick version parsed cleanly"

    $bl = Get-SenToolStatus -Id "blender" -Catalog $catalogPath -Runner $runner
    Assert-Equal "ok" $bl.Status "blender status must be ok"
    Assert-Equal "4.2.1" $bl.Version "blender version parsed cleanly"
}

Test "Get-SenInstallPlan builds winget and brew commands for creative tools ffmpeg, imagemagick and blender" {
    $missingRunner = { param($cmd) return $null }
    $planWin = Get-SenInstallPlan -Ids @("ffmpeg", "imagemagick", "blender") -Catalog $catalogPath -Platform "Windows" -Runner $missingRunner
    Assert-Equal 3 $planWin.Count "All 3 creative tools in Windows install plan"
    Assert-True ((@($planWin | Where-Object Id -eq "ffmpeg")[0].Command) -like "*Gyan.FFmpeg*") "ffmpeg winget id"
    Assert-True ((@($planWin | Where-Object Id -eq "imagemagick")[0].Command) -like "*ImageMagick.ImageMagick*") "imagemagick winget id"
    Assert-True ((@($planWin | Where-Object Id -eq "blender")[0].Command) -like "*BlenderFoundation.Blender*") "blender winget id"

    $planMac = Get-SenInstallPlan -Ids @("ffmpeg", "imagemagick", "blender") -Catalog $catalogPath -Platform "macOS" -Runner $missingRunner
    Assert-Equal 3 $planMac.Count "All 3 creative tools in macOS install plan"
    Assert-Equal "brew install ffmpeg" (@($planMac | Where-Object Id -eq "ffmpeg")[0].Command)
    Assert-Equal "brew install imagemagick" (@($planMac | Where-Object Id -eq "imagemagick")[0].Command)
    Assert-Equal "brew install --cask blender" (@($planMac | Where-Object Id -eq "blender")[0].Command)
}
