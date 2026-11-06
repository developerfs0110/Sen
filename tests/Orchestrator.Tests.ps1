# tests/Orchestrator.Tests.ps1
# Unit & integration tests for Sen v0.3.0 Orchestrator, Task Manager (DAG + File Lock),
# Risk Scoring, Delivery Gate, Recovery, Quality Metrics, Backlog, Restore Point & 3-Layer Memory (ASCII-only)

. "$PSScriptRoot/Assert.ps1"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
Import-Module $senModule -Force

$guardScript = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/guard.ps1"

function New-OrchTestWorkspace {
    $p = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-orch-" + [Guid]::NewGuid().ToString("N").Substring(0, 10))
    [System.IO.Directory]::CreateDirectory($p) | Out-Null
    return $p
}

Test "Get-SenTaskRiskScore classifies shared component and 3+ files as Tier 2 and Auth/DB as Tier 3" {
    $r1 = Get-SenTaskRiskScore -Request "Update button padding" -FileCount 1
    Assert-Equal 1 $r1.Tier "Simple 1-file UI change should be Tier 1"

    $r2 = Get-SenTaskRiskScore -Request "Update button component" -FileCount 1 -SharedComponent
    Assert-Equal 2 $r2.Tier "Shared component blast radius should elevate 1-file change to Tier 2"

    $r3 = Get-SenTaskRiskScore -Request "Add Google OAuth login, just do it" -FileCount 1
    Assert-Equal 3 $r3.Tier "Auth risk must stay Tier 3 even with 'just do it' override"
    Assert-True $r3.HardFloorTier3 "HardFloorTier3 must be true for Auth"
}

Test "Task Manager DAG auto-promotes pending task to ready only when dependencies are done" {
    $ws = New-OrchTestWorkspace
    try {
        $t1 = New-SenTask -Workspace $ws -Id "T-1" -Title "Design schema" -Tier 3 -Assignee "arch" -AllowedPaths @("docs/specs/")
        $t2 = New-SenTask -Workspace $ws -Id "T-2" -Title "Implement API" -Tier 3 -Assignee "dev_be" -DependsOn @("T-1") -AllowedPaths @("src/api/")

        Assert-Equal "ready" $t1.status "T-1 without dependencies starts as ready"
        Assert-Equal "pending" $t2.status "T-2 with unfinished dependency T-1 starts as pending"

        $tryStartT2 = Start-SenTask -Workspace $ws -Id "T-2"
        Assert-True (-not $tryStartT2.Started) "T-2 must not start before T-1 is done"
        Assert-Equal "blocked_dependency" $tryStartT2.Status "Status should be blocked_dependency"

        $s1 = Start-SenTask -Workspace $ws -Id "T-1"
        Assert-True $s1.Started "T-1 should start"
        [void](Submit-SenTaskForReview -Workspace $ws -Id "T-1")

        # Attempt to complete without evidence command must fail
        $badRev = Complete-SenTaskReview -Workspace $ws -Id "T-1" -Passed $true -EvidenceCommand "" -ExitCode 0
        Assert-True (-not $badRev.Completed) "Review pass without EvidenceCommand must be rejected"

        $goodRev = Complete-SenTaskReview -Workspace $ws -Id "T-1" -Passed $true -Reviewer "tester" -EvidenceCommand "tests/run.ps1" -ExitCode 0
        Assert-True $goodRev.Completed "T-1 review with valid evidence should complete"

        $all = @(Get-SenTasks -Workspace $ws)
        $t2Updated = $all | Where-Object { $_.id -eq "T-2" } | Select-Object -First 1
        Assert-Equal "ready" $t2Updated.status "T-2 must auto-promote to ready once T-1 is done"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Task Manager File Lock prevents two Developers from modifying overlapping allowedPaths concurrently" {
    $ws = New-OrchTestWorkspace
    try {
        [void](New-SenTask -Workspace $ws -Id "DEV-A" -Title "Refactor auth service" -Assignee "dev_fe" -AllowedPaths @("src/services/auth.ts", "src/ui/"))
        [void](New-SenTask -Workspace $ws -Id "DEV-B" -Title "Update auth token handler" -Assignee "dev_be" -AllowedPaths @("src/services/"))
        [void](New-SenTask -Workspace $ws -Id "DEV-C" -Title "Build billing page" -Assignee "dev_be" -AllowedPaths @("src/billing/"))

        $startA = Start-SenTask -Workspace $ws -Id "DEV-A"
        Assert-True $startA.Started "DEV-A should start and acquire lock on src/services/auth.ts"

        $readyList = @(Get-SenReadyTasks -Workspace $ws)
        $bReady = $readyList | Where-Object { $_.Id -eq "DEV-B" } | Select-Object -First 1
        $cReady = $readyList | Where-Object { $_.Id -eq "DEV-C" } | Select-Object -First 1
        Assert-True (-not $bReady.IsReady) "DEV-B overlaps src/services/ with DEV-A and must be marked not ready"
        Assert-Equal "DEV-A" $bReady.FileConflictWith "DEV-B conflict should point to DEV-A"
        Assert-True $cReady.IsReady "DEV-C touches disjoint src/billing/ and must be ready"

        $startB = Start-SenTask -Workspace $ws -Id "DEV-B"
        Assert-True (-not $startB.Started) "Start-SenTask must block DEV-B due to file lock conflict"
        Assert-Equal "blocked_file_lock" $startB.Status "Status must be blocked_file_lock"

        $startC = Start-SenTask -Workspace $ws -Id "DEV-C"
        Assert-True $startC.Started "DEV-C should start in parallel without file conflict"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Rework tracking, Quality Metrics, Recovery State, and Delivery Gate work end-to-end" {
    $ws = New-OrchTestWorkspace
    try {
        [void](New-SenTask -Workspace $ws -Id "M-1" -Title "Core module" -AllowedPaths @("src/core/"))
        [void](Add-SenBacklogItem -Workspace $ws -Id "BL-1" -Title "Future idea" -Priority "P2")

        [void](Start-SenTask -Workspace $ws -Id "M-1")

        # Recovery state while M-1 is in_progress
        $rec1 = Get-SenRecoveryState -Workspace $ws
        Assert-True $rec1.needsRecovery "Recovery state should flag active in_progress task"
        Assert-Equal 1 $rec1.inProgressIds.Count "Should report 1 in_progress task"

        # Delivery gate must block while M-1 is not done
        $gate1 = Test-SenDeliveryGate -Workspace $ws
        Assert-True (-not $gate1.Allowed) "Delivery gate must block when M-1 is still in_progress"

        # Fail review once -> reworkCount increments to 1
        [void](Submit-SenTaskForReview -Workspace $ws -Id "M-1")
        $failRev = Complete-SenTaskReview -Workspace $ws -Id "M-1" -Passed $false -Reviewer "sec" -Notes "Missing input validation"
        Assert-Equal 1 $failRev.ReworkCount "ReworkCount should be 1 after failed review"

        # Pass review on second attempt
        [void](Submit-SenTaskForReview -Workspace $ws -Id "M-1")
        [void](Complete-SenTaskReview -Workspace $ws -Id "M-1" -Passed $true -Reviewer "tester" -EvidenceCommand "tests/run.ps1" -ExitCode 0)

        # Delivery gate now allows (backlog item BL-1 does not block active delivery)
        $gate2 = Test-SenDeliveryGate -Workspace $ws
        Assert-True $gate2.Allowed "Delivery gate should allow once all active tasks are done with verified evidence"

        $metrics = Get-SenQualityMetrics -Workspace $ws
        Assert-Equal 100 $metrics.taskSuccessRatePct "Success rate should be 100%"
        Assert-Equal 0 $metrics.firstPassRatePct "First-pass rate should be 0% because M-1 had 1 rework"
        Assert-Equal 100 $metrics.reworkRatePct "Rework rate should be 100%"
        Assert-Equal 1 $metrics.backlogTasks "Backlog count should be 1"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws "docs/TODO.md")) "Add-SenBacklogItem must create docs/TODO.md"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "New-SenRestorePoint and Restore-SenRestorePoint safely revert modified and newly created files" {
    $ws = New-OrchTestWorkspace
    try {
        $f1 = Join-Path $ws "app.txt"
        $f2 = Join-Path $ws "newfile.txt"
        [System.IO.File]::WriteAllText($f1, "original-v1", [System.Text.UTF8Encoding]::new($false))

        $rp = New-SenRestorePoint -Workspace $ws -Files @("app.txt", "newfile.txt") -Label "before-refactor"
        Assert-True (-not [string]::IsNullOrWhiteSpace($rp.Id)) "Restore point ID must be returned"

        # Modify f1 and create f2
        [System.IO.File]::WriteAllText($f1, "corrupted-v2", [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($f2, "unwanted-file", [System.Text.UTF8Encoding]::new($false))

        $restored = Restore-SenRestorePoint -Workspace $ws -Id $rp.Id
        Assert-True $restored.Restored "Restore-SenRestorePoint should succeed"
        Assert-Equal "original-v1" ([System.IO.File]::ReadAllText($f1)) "app.txt must be restored to original-v1"
        Assert-True (-not (Test-Path -LiteralPath $f2)) "newfile.txt that did not exist before must be removed on restore"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "3-Layer Memory stores and retrieves execution lessons and memory snapshot" {
    $ws = New-OrchTestWorkspace
    try {
        [void](Add-SenExecutionLesson -Workspace $ws -Category "PowerShell" -Problem "ExecutionPolicy blocked module load" -RootCause "Default Windows policy" -Solution "Use -ExecutionPolicy Bypass")
        $snap = Get-SenMemorySnapshot -Workspace $ws
        Assert-Equal 1 $snap.executionMemory.lessonCount "Should have 1 execution lesson recorded"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "guard.ps1 blocks direct write to .git/config and enforces Execution Contract allowedPaths when enabled" {
    $ws = New-OrchTestWorkspace
    try {
        [void](New-SenTask -Workspace $ws -Id "T-LOCKED" -Title "Edit UI only" -AllowedPaths @("src/ui/"))
        [void](Start-SenTask -Workspace $ws -Id "T-LOCKED")

        # 1. Test .git/config protection
        $gitCfgPayload = @{
            workspacePaths = @($ws)
            toolCall       = @{
                name = "write_file"
                args = @{ Path = (Join-Path $ws ".git/config") }
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $outGit = $gitCfgPayload | powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript | ConvertFrom-Json
        Assert-Equal "deny" $outGit.decision "guard.ps1 must block direct writes to .git/config"

        # 2. Test Execution Contract allowedPaths enforcement
        $outsideContractPayload = @{
            workspacePaths   = @($ws)
            enforceTaskPaths = $true
            toolCall         = @{
                name = "edit_file"
                args = @{ Path = (Join-Path $ws "src/db/schema.sql") }
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $outContract = $outsideContractPayload | powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript | ConvertFrom-Json
        Assert-Equal "deny" $outContract.decision "guard.ps1 must block file write outside active task allowedPaths when enforceTaskPaths is true"

        $insideContractPayload = @{
            workspacePaths   = @($ws)
            enforceTaskPaths = $true
            toolCall         = @{
                name = "edit_file"
                args = @{ Path = (Join-Path $ws "src/ui/Button.tsx") }
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $outAllowed = $insideContractPayload | powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript | ConvertFrom-Json
        Assert-Equal "ask" $outAllowed.decision "guard.ps1 must allow file write inside active task allowedPaths"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}
