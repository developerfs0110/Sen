# scripts/Sen.Orchestrator.psm1
# Pure ASCII PowerShell module for Sen Orchestrator, Task DAG, File Lock,
# Backlog, Restore Points, 3-Layer Memory, and Code Health Audit (v0.3.0+).

$ErrorActionPreference = "Stop"

function Save-SenTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)]
        [object[]]$Tasks
    )
    $payload = [ordered]@{
        version   = 1
        updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        tasks     = @($Tasks)
    }
    Write-SenAtomicJson -Path (Join-Path -Path $Workspace -ChildPath ".agents/office/tasks.json") -InputObject $payload -Depth 8
    return @($Tasks)
}

function Get-SenTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $obj = Read-SenSafeJson -Path (Join-Path -Path $Workspace -ChildPath ".agents/office/tasks.json")
    if ($null -eq $obj) { return @() }
    $list = if ($obj.PSObject.Properties.Name -contains "tasks") { @($obj.tasks) } elseif ($obj -is [array]) { @($obj) } else { @() }

    $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $list) {
        if ($t -and [string]$t.status -eq "done") {
            [void]$doneIds.Add([string]$t.id)
        }
    }
    $changed = $false
    foreach ($t in $list) {
        if (-not $t) { continue }
        $deps = @($t.dependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ([string]$t.status -eq "pending") {
            $allDone = $true
            foreach ($d in $deps) {
                if (-not $doneIds.Contains([string]$d)) { $allDone = $false; break }
            }
            if ($allDone) { $t.status = "ready"; $changed = $true }
        }
    }
    if ($changed) {
        [void](Save-SenTasks -Workspace $Workspace -Tasks $list)
    }
    return @($list)
}

function Clear-SenTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasksPath = Join-Path -Path $Workspace -ChildPath ".agents/office/tasks.json"
    if (Test-Path -LiteralPath $tasksPath) {
        Remove-Item -LiteralPath $tasksPath -Force -ErrorAction SilentlyContinue
    }
}

function New-SenTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [int]$Tier = 2,
        [string]$RiskLevel = "medium",
        [string]$Module = "Core",
        [string]$Assignee = "dev_be",
        [string[]]$DependsOn = @(),
        [string[]]$AllowedPaths = @(),
        [string[]]$ForbiddenActions = @("delete_database", "force_push"),
        [bool]$ApprovalRequired = $false,
        [string[]]$AcceptanceCriteria = @(),
        [ValidateSet("auto", "backlog", "pending", "ready", "in_progress", "reviewing", "done", "blocked", "failed")]
        [string]$Status = "auto"
    )
    $tasks = [System.Collections.Generic.List[object]]::new()
    foreach ($existing in @(Get-SenTasks -Workspace $Workspace)) {
        if ($existing -and [string]$existing.id -ne $Id) {
            $tasks.Add($existing)
        }
    }

    $cleanDeps = @($DependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cleanPaths = @($AllowedPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cleanForbidden = @($ForbiddenActions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cleanCriteria = @($AcceptanceCriteria | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $resolvedStatus = $Status
    if ($resolvedStatus -eq "auto") {
        if ($cleanDeps.Count -eq 0) {
            $resolvedStatus = "ready"
        }
        else {
            $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($t in $tasks) {
                if ([string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) }
            }
            $allDepsDone = $true
            foreach ($d in $cleanDeps) {
                if (-not $doneIds.Contains([string]$d)) { $allDepsDone = $false; break }
            }
            $resolvedStatus = if ($allDepsDone) { "ready" } else { "pending" }
        }
    }

    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $newTask = [pscustomobject][ordered]@{
        id                 = $Id
        title              = $Title
        tier               = $Tier
        riskLevel          = $RiskLevel
        module             = $Module
        assignee           = $Assignee
        dependsOn          = $cleanDeps
        allowedPaths       = $cleanPaths
        forbiddenActions   = $cleanForbidden
        approvalRequired   = $ApprovalRequired
        acceptanceCriteria = $cleanCriteria
        status             = $resolvedStatus
        reworkCount        = 0
        evidence           = [pscustomobject][ordered]@{
            command    = ""
            exitCode   = $null
            reviewer   = ""
            verifiedAt = $null
            notes      = ""
        }
        createdAt          = $now
        updatedAt          = $now
    }
    $tasks.Add($newTask)
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks.ToArray())
    return $newTask
}

function Get-SenReadyTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $activeTasks = @($tasks | Where-Object { [string]$_.status -eq "in_progress" })
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($t in $tasks) {
        if ([string]$t.status -ne "ready") { continue }
        $conflictId = $null
        foreach ($act in $activeTasks) {
            if ([string]$act.id -eq [string]$t.id) { continue }
            if (Test-SenPathOverlap -PathsA @($t.allowedPaths) -PathsB @($act.allowedPaths)) {
                $conflictId = [string]$act.id
                break
            }
        }
        $results.Add([pscustomobject]@{
            Task             = $t
            Id               = [string]$t.id
            IsReady          = ($null -eq $conflictId)
            FileConflictWith = $conflictId
        })
    }
    return @($results.ToArray())
}

function Start-SenTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [string]$Assignee = ""
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $target) {
        return [pscustomobject]@{ Started = $false; Status = "not_found"; ConflictTaskId = $null; Reason = "Task '$Id' not found" }
    }

    $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $tasks) {
        if ([string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) }
    }
    $missingDeps = [System.Collections.Generic.List[string]]::new()
    foreach ($d in @($target.dependsOn)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$d) -and -not $doneIds.Contains([string]$d)) {
            $missingDeps.Add([string]$d)
        }
    }
    if ($missingDeps.Count -gt 0) {
        return [pscustomobject]@{
            Started        = $false
            Status         = "blocked_dependency"
            ConflictTaskId = $null
            Reason         = "Task '$Id' is waiting on dependencies: $($missingDeps -join ', ')"
        }
    }

    foreach ($t in $tasks) {
        if ([string]$t.id -eq $Id -or [string]$t.status -ne "in_progress") { continue }
        if (Test-SenPathOverlap -PathsA @($target.allowedPaths) -PathsB @($t.allowedPaths)) {
            return [pscustomobject]@{
                Started        = $false
                Status         = "blocked_file_lock"
                ConflictTaskId = [string]$t.id
                Reason         = "File lock conflict: '$Id' shares allowedPaths with active task '$($t.id)' ($($t.assignee))"
            }
        }
    }

    $target.status = "in_progress"
    if (-not [string]::IsNullOrWhiteSpace($Assignee)) {
        $target.assignee = $Assignee
    }
    $target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks)
    return [pscustomobject]@{
        Started        = $true
        Status         = "in_progress"
        ConflictTaskId = $null
        Task           = $target
        Reason         = $null
    }
}

function Submit-SenTaskForReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [string]$Notes = ""
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $target) {
        return [pscustomobject]@{ Submitted = $false; Reason = "Task '$Id' not found" }
    }
    $target.status = "reviewing"
    if (-not [string]::IsNullOrWhiteSpace($Notes) -and $target.evidence) {
        $target.evidence.notes = $Notes
    }
    $target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks)
    return [pscustomobject]@{ Submitted = $true; Status = "reviewing"; Task = $target }
}

function Complete-SenTaskReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [bool]$Passed,
        [string]$Reviewer = "tester",
        [string]$EvidenceCommand = "",
        [int]$ExitCode = 0,
        [string]$Notes = ""
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $target) {
        return [pscustomobject]@{ Completed = $false; Status = "not_found"; Reason = "Task '$Id' not found" }
    }

    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    if ($Passed) {
        if ([string]::IsNullOrWhiteSpace($EvidenceCommand) -or $ExitCode -ne 0) {
            return [pscustomobject]@{
                Completed = $false
                Status    = [string]$target.status
                Reason    = "Integration & Testing gate requires a non-empty EvidenceCommand and ExitCode = 0 to mark '$Id' done."
            }
        }
        $target.status = "done"
        $target.evidence = [pscustomobject][ordered]@{
            command    = $EvidenceCommand
            exitCode   = $ExitCode
            reviewer   = $Reviewer
            verifiedAt = $now
            notes      = $Notes
        }
        $target.updatedAt = $now
        [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks)
        [void](Get-SenTasks -Workspace $Workspace)
        return [pscustomobject]@{ Completed = $true; Status = "done"; Task = $target; Reason = $null }
    }
    else {
        $target.reworkCount = [int]$target.reworkCount + 1
        $target.status = "in_progress"
        $target.evidence = [pscustomobject][ordered]@{
            command    = $EvidenceCommand
            exitCode   = $ExitCode
            reviewer   = $Reviewer
            verifiedAt = $now
            notes      = $Notes
        }
        $target.updatedAt = $now
        [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks)
        return [pscustomobject]@{
            Completed   = $false
            Status      = "in_progress"
            ReworkCount = [int]$target.reworkCount
            Task        = $target
            Reason      = "Review failed; returned to in_progress for rework (#$($target.reworkCount))."
        }
    }
}

function Test-SenDeliveryGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [string]$ProjectPath = "",
        [switch]$CheckCodeHealth,
        [switch]$CheckVnLaw
    )
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath } else { $Workspace }
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $active = @($tasks | Where-Object { [string]$_.status -ne "backlog" })
    $incomplete = [System.Collections.Generic.List[string]]::new()
    $doneCount = 0
    foreach ($t in $active) {
        $hasValidEvidence = ($null -ne $t.evidence) -and (-not [string]::IsNullOrWhiteSpace([string]$t.evidence.command)) -and ([int]$t.evidence.exitCode -eq 0)
        if ([string]$t.status -eq "done" -and $hasValidEvidence) { $doneCount++ }
        else { $incomplete.Add([string]$t.id) }
    }
    $reasons = [System.Collections.Generic.List[string]]::new()
    $allowed = ($incomplete.Count -eq 0)
    if (-not $allowed) {
        $reasons.Add("Incomplete or unverified tasks ($($incomplete -join ', '))")
    }
    $codeHealthObj = $null
    if ($CheckCodeHealth.IsPresent -and (Get-Command Measure-SenCodeHealth -ErrorAction SilentlyContinue)) {
        $codeHealthObj = Measure-SenCodeHealth -Path $targetDir
        if (-not $codeHealthObj.Healthy) {
            $allowed = $false
            $reasons.Add("Clean Code check failed (Score=$($codeHealthObj.Score))")
        }
    }
    $vnLawObj = $null
    if ($CheckVnLaw.IsPresent -and (Get-Command Invoke-SenVnLawScan -ErrorAction SilentlyContinue)) {
        $vnLawObj = Invoke-SenVnLawScan -Path $targetDir
        if (-not $vnLawObj.CompliantCodeLevel) {
            $allowed = $false
            $codes = @($vnLawObj.CodeRedFlags | ForEach-Object { $_.Code }) -join ', '
            $reasons.Add("Vietnam Law code red flags ($codes)")
        }
    }
    if ($allowed) {
        $reason = if ($active.Count -eq 0) { "No active tasks registered." } else { "All $($active.Count) active task(s) verified and done." }
    }
    else {
        $reason = "Delivery blocked: " + ($reasons -join "; ") + "."
    }
    return [pscustomobject]@{
        Allowed       = $allowed
        TotalActive   = $active.Count
        DoneCount     = $doneCount
        IncompleteIds = @($incomplete.ToArray())
        CodeHealth    = $codeHealthObj
        VnLawScan     = $vnLawObj
        Reason        = $reason
    }
}

function Get-SenRecoveryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $inProgress = @($tasks | Where-Object { [string]$_.status -eq "in_progress" } | ForEach-Object { [string]$_.id })
    $reviewing  = @($tasks | Where-Object { [string]$_.status -eq "reviewing" } | ForEach-Object { [string]$_.id })
    $ready      = @($tasks | Where-Object { [string]$_.status -eq "ready" } | ForEach-Object { [string]$_.id })
    $pending    = @($tasks | Where-Object { [string]$_.status -eq "pending" } | ForEach-Object { [string]$_.id })
    $done       = @($tasks | Where-Object { [string]$_.status -eq "done" } | ForEach-Object { [string]$_.id })
    $backlog    = @($tasks | Where-Object { [string]$_.status -eq "backlog" } | ForEach-Object { [string]$_.id })
    $failed     = @($tasks | Where-Object { [string]$_.status -eq "failed" } | ForEach-Object { [string]$_.id })

    return [pscustomobject][ordered]@{
        needsRecovery = [bool](($inProgress.Count + $reviewing.Count + $failed.Count) -gt 0)
        totalTasks    = $tasks.Count
        doneIds       = $done
        inProgressIds = $inProgress
        reviewingIds  = $reviewing
        readyIds      = $ready
        pendingIds    = $pending
        failedIds     = $failed
        backlogIds    = $backlog
    }
}

function Get-SenQualityMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $active = @($tasks | Where-Object { [string]$_.status -ne "backlog" })
    $backlog = @($tasks | Where-Object { [string]$_.status -eq "backlog" })
    $done = @($active | Where-Object { [string]$_.status -eq "done" })
    $inProg = @($active | Where-Object { [string]$_.status -in @("in_progress", "reviewing") })
    $ready = @($active | Where-Object { [string]$_.status -in @("ready", "pending") })

    $totalActive = $active.Count
    $doneCount = $done.Count
    $firstPassCount = @($done | Where-Object { [int]$_.reworkCount -eq 0 }).Count
    $reworkedCount = @($active | Where-Object { [int]$_.reworkCount -gt 0 }).Count
    $verifiedPassCount = @($done | Where-Object { $null -ne $_.evidence -and [int]$_.evidence.exitCode -eq 0 }).Count

    $successPct = if ($totalActive -gt 0) { [int][Math]::Round(($doneCount * 100.0) / $totalActive) } else { 100 }
    $firstPassPct = if ($doneCount -gt 0) { [int][Math]::Round(($firstPassCount * 100.0) / $doneCount) } else { 100 }
    $reworkPct = if ($totalActive -gt 0) { [int][Math]::Round(($reworkedCount * 100.0) / $totalActive) } else { 0 }
    $testPassPct = if ($doneCount -gt 0) { [int][Math]::Round(($verifiedPassCount * 100.0) / $doneCount) } else { 100 }

    return [pscustomobject][ordered]@{
        totalTasks         = $tasks.Count
        activeTasks        = $totalActive
        doneTasks          = $doneCount
        inProgressTasks    = $inProg.Count
        readyTasks         = $ready.Count
        backlogTasks       = $backlog.Count
        taskSuccessRatePct = $successPct
        firstPassRatePct   = $firstPassPct
        reworkRatePct      = $reworkPct
        testPassRatePct    = $testPassPct
    }
}

function Add-SenBacklogItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Priority = "P1",
        [string]$Details = "",
        [string]$Module = "Backlog"
    )
    $task = New-SenTask -Workspace $Workspace -Id $Id -Title $Title -Tier 2 -RiskLevel "medium" -Module $Module -Assignee "pm" -Status "backlog"

    $docsDir = Join-Path -Path $Workspace -ChildPath "docs"
    if (-not (Test-Path -LiteralPath $docsDir)) {
        [System.IO.Directory]::CreateDirectory($docsDir) | Out-Null
    }
    $todoPath = Join-Path -Path $docsDir -ChildPath "TODO.md"
    $existingText = if (Test-Path -LiteralPath $todoPath) {
        [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $todoPath).Path, [System.Text.Encoding]::UTF8)
    }
    else {
        "# Project Backlog (TODO)`n`n"
    }

    if ($existingText -notmatch [regex]::Escape($Id)) {
        $entryLine = "- [ ] **${Id} (${Priority}): ${Title}**"
        if (-not [string]::IsNullOrWhiteSpace($Details)) {
            $entryLine += "`n  - " + $Details.Trim()
        }
        $updatedText = $existingText.TrimEnd() + "`n`n" + $entryLine + "`n"
        [System.IO.File]::WriteAllText($todoPath, $updatedText, [System.Text.UTF8Encoding]::new($false))
    }

    return [pscustomobject]@{
        Id       = $Id
        Title    = $Title
        Priority = $Priority
        TodoPath = $todoPath
        Task     = $task
    }
}

function New-SenRestorePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string[]]$Files,
        [string]$Label = "pre-edit"
    )
    $resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('\', '/')
    $restoreRoot = Join-Path -Path $resolvedWs -ChildPath ".agents/.sen-restore"
    $ts = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
    $id = "rp-$ts-" + ([Guid]::NewGuid().ToString("N").Substring(0, 6))
    $rpDir = Join-Path -Path $restoreRoot -ChildPath $id
    $filesDir = Join-Path -Path $rpDir -ChildPath "files"
    [System.IO.Directory]::CreateDirectory($filesDir) | Out-Null

    $entries = [System.Collections.Generic.List[object]]::new()
    $idx = 0
    foreach ($f in $Files) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        $fullPath = if ([System.IO.Path]::IsPathRooted($f)) { [System.IO.Path]::GetFullPath($f) } else { [System.IO.Path]::GetFullPath((Join-Path $resolvedWs $f)) }
        $relPath = if ($fullPath.StartsWith($resolvedWs, [System.StringComparison]::OrdinalIgnoreCase)) {
            $fullPath.Substring($resolvedWs.Length).TrimStart('\', '/')
        }
        else {
            [System.IO.Path]::GetFileName($fullPath)
        }
        $existed = Test-Path -LiteralPath $fullPath -PathType Leaf
        $storedName = "f_$idx.bak"
        if ($existed) {
            Copy-Item -LiteralPath $fullPath -Destination (Join-Path $filesDir $storedName) -Force
        }
        $entries.Add([ordered]@{
            relPath    = $relPath
            fullPath   = $fullPath
            existed    = [bool]$existed
            storedName = $storedName
        })
        $idx++
    }

    $manifest = [ordered]@{
        id        = $id
        label     = $Label
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        entries   = @($entries.ToArray())
    }
    Write-SenAtomicJson -Path (Join-Path -Path $rpDir -ChildPath "manifest.json") -InputObject $manifest -Depth 6
    return [pscustomobject]@{
        Id        = $id
        Label     = $Label
        Directory = $rpDir
        FileCount = $entries.Count
    }
}

function Restore-SenRestorePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [string]$Id = ""
    )
    $resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('\', '/')
    $restoreRoot = Join-Path -Path $resolvedWs -ChildPath ".agents/.sen-restore"
    if (-not (Test-Path -LiteralPath $restoreRoot)) {
        return [pscustomobject]@{ Restored = $false; Id = $null; Error = "No restore points found" }
    }
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $cand = Join-Path -Path $restoreRoot -ChildPath $Id
        if (Test-Path -LiteralPath $cand) { Get-Item -LiteralPath $cand } else { $null }
    }
    else {
        Get-ChildItem -LiteralPath $restoreRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    }
    if ($null -eq $targetDir) {
        return [pscustomobject]@{ Restored = $false; Id = $Id; Error = "Restore point not found" }
    }
    $manifest = Read-SenSafeJson -Path (Join-Path -Path $targetDir.FullName -ChildPath "manifest.json")
    if ($null -eq $manifest) {
        return [pscustomobject]@{ Restored = $false; Id = $targetDir.Name; Error = "Manifest missing" }
    }
    $filesDir = Join-Path -Path $targetDir.FullName -ChildPath "files"
    $restoredCount = 0

    foreach ($e in @($manifest.entries)) {
        $destPath = Join-Path -Path $resolvedWs -ChildPath ([string]$e.relPath)
        if ([bool]$e.existed) {
            $srcBak = Join-Path -Path $filesDir -ChildPath ([string]$e.storedName)
            if (Test-Path -LiteralPath $srcBak) {
                $parent = Split-Path -Parent $destPath
                if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
                }
                Copy-Item -LiteralPath $srcBak -Destination $destPath -Force
                $restoredCount++
            }
        }
        else {
            if (Test-Path -LiteralPath $destPath) {
                Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
                $restoredCount++
            }
        }
    }
    return [pscustomobject]@{
        Restored      = $true
        Id            = [string]$manifest.id
        RestoredCount = $restoredCount
        Error         = $null
    }
}

function Add-SenExecutionLesson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [Parameter(Mandatory = $true)]
        [string]$Problem,
        [Parameter(Mandatory = $true)]
        [string]$Solution,
        [string]$RootCause = "",
        [bool]$VerifiedByUser = $true
    )
    $lessonsPath = Join-Path -Path $Workspace -ChildPath ".agents/office/lessons.json"
    $existing = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(Read-SenSafeJson -Path $lessonsPath)) {
        if ($item) { $existing.Add($item) }
    }
    $entry = [pscustomobject][ordered]@{
        id             = "LES-" + ([DateTime]::UtcNow.ToString("yyyyMMddHHmmss")) + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 4))
        category       = $Category
        problem        = $Problem
        rootCause      = $RootCause
        solution       = $Solution
        verifiedByUser = $VerifiedByUser
        createdAt      = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $existing.Add($entry)
    Write-SenAtomicJson -Path $lessonsPath -InputObject @($existing.ToArray()) -Depth 5
    return $entry
}

function Get-SenExecutionLessons {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $loaded = Read-SenSafeJson -Path (Join-Path -Path $Workspace -ChildPath ".agents/office/lessons.json")
    if ($null -eq $loaded) { return @() }
    return @($loaded)
}

function Get-SenMemorySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $lessons = @(Get-SenExecutionLessons -Workspace $Workspace)
    return [pscustomobject][ordered]@{
        userMemory      = [ordered]@{
            present = (Test-Path -LiteralPath (Join-Path $Workspace ".agents/profile.md"))
            path    = ".agents/profile.md"
        }
        projectMemory   = [ordered]@{
            hasAgentsMd  = (Test-Path -LiteralPath (Join-Path $Workspace "AGENTS.md"))
            hasContextMd = (Test-Path -LiteralPath (Join-Path $Workspace "docs/CONTEXT.md"))
            hasTodoMd    = (Test-Path -LiteralPath (Join-Path $Workspace "docs/TODO.md"))
        }
        executionMemory = [ordered]@{
            lessonCount = $lessons.Count
            lessons     = $lessons
        }
    }
}

Export-ModuleMember -Function Save-SenTasks, Get-SenTasks, Clear-SenTasks, New-SenTask, Get-SenReadyTasks, Start-SenTask, Submit-SenTaskForReview, Complete-SenTaskReview, Test-SenDeliveryGate, Get-SenRecoveryState, Get-SenQualityMetrics, Add-SenBacklogItem, New-SenRestorePoint, Restore-SenRestorePoint, Add-SenExecutionLesson, Get-SenExecutionLessons, Get-SenMemorySnapshot

