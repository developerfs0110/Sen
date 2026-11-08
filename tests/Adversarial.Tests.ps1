# tests/Adversarial.Tests.ps1
# Comprehensive unit and negative tests for Sen.Adversarial.psm1 (AV-01..AV-10)

. "$PSScriptRoot/Assert.ps1"

$senModulePath = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
Import-Module -Name $senModulePath -Force

function New-AdversarialTestWorkspace {
    $ws = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-adv-test-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    [System.IO.Directory]::CreateDirectory((Join-Path $ws "src")) | Out-Null
    [System.IO.Directory]::CreateDirectory((Join-Path $ws "tests")) | Out-Null
    [System.IO.Directory]::CreateDirectory((Join-Path $ws ".agents/office")) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $ws "src/engine.ps1"), "function Get-Answer { return 42 }`n[void](Get-Answer)`n", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $ws "tests/Engine.Tests.ps1"), "Assert-Equal 42 42`nAssert-True `$true`nAssert-NotNull 'ok'`n", [System.Text.Encoding]::UTF8)
    return $ws
}

Test "AV-04: New-SenFalsificationPlan and Test-SenFalsificationPlan enforce 7-part Falsification Plan and reject trivial inputs" {
    $ws = New-AdversarialTestWorkspace
    try {
        $threwOnTrivial = $false
        try {
            [void](New-SenFalsificationPlan -Workspace $ws -ClaimId "CLAIM-001" -Proposer "agent-proposer" `
                -CoreHypothesis "Caching reduces latency" `
                -FailureConditions @("none") `
                -Counterexamples @("Cache stampede under concurrent cold start") `
                -BoundaryConditions @("Empty cache", "10000 concurrent requests") `
                -AlternativeSolutions @("In-memory LRU vs Redis") `
                -FalsificationTest "none" `
                -AcceptanceCriteria @("p95 < 50ms"))
        }
        catch {
            $threwOnTrivial = $true
        }
        Assert-True $threwOnTrivial "New-SenFalsificationPlan must throw when FailureConditions or FalsificationTest is 'none'"

        $validPlan = New-SenFalsificationPlan -Workspace $ws -ClaimId "CLAIM-001" -Proposer "agent-proposer" `
            -CoreHypothesis "Lock-free read path prevents thread contention" `
            -FailureConditions @("Stale read exceeds 100ms window", "Write starvation under heavy load") `
            -Counterexamples @("Simultaneous writer and 50 readers on same key") `
            -BoundaryConditions @("Zero keys", "Payload > 1MB", "Network partition") `
            -AlternativeSolutions @("Mutex lock (rejected: high contention)", "ReadWriteLockSlim (selected)") `
            -FalsificationTest "Invoke-ConcurrencyStressTest -Readers 50 -Writers 4" `
            -AcceptanceCriteria @("Zero race conditions", "p99 latency < 20ms")

        Assert-Equal "FP-CLAIM-001" $validPlan.planId "Plan ID must follow FP-<ClaimId>"
        Assert-True ($validPlan.criteriaHash.Length -eq 64) "Must compute SHA256 criteriaHash for AV-09 lock"
        $check = Test-SenFalsificationPlan -Plan $validPlan
        Assert-True $check.Valid "Valid falsification plan must pass Test-SenFalsificationPlan"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "AV-01, AV-02, AV-03, AV-05, AV-06, AV-10: Full lifecycle of Claim, Executable Evidence, Counterexample, Blind Review, and 4-State Independent Verdict" {
    $ws = New-AdversarialTestWorkspace
    try {
        $fHash = Get-SenFileSha256 -FilePath (Join-Path $ws "src/engine.ps1")
        $tHash = Get-SenTextSha256 -Text "hello"
        $revSnap = Get-SenCodeRevisionSnapshot -Workspace $ws -CodePaths @("src/engine.ps1")
        Assert-True ($fHash.Length -eq 64) "Get-SenFileSha256 must return 64-char SHA256 hex"
        Assert-True ($tHash.Length -eq 64) "Get-SenTextSha256 must return 64-char SHA256 hex"
        Assert-True ($revSnap.revisionHash.Length -eq 64) "Get-SenCodeRevisionSnapshot must compute revisionHash"

        $plan = New-SenFalsificationPlan -Workspace $ws -ClaimId "CLAIM-100" -Proposer "agent-a" `
            -CoreHypothesis "Engine returns deterministic answer" `
            -FailureConditions @("Non-deterministic output on repeated calls") `
            -Counterexamples @("Concurrent invocation with null input") `
            -BoundaryConditions @("Null input", "MaxInt input") `
            -AlternativeSolutions @("Static constant vs computed value") `
            -FalsificationTest "powershell -Command exit 0" `
            -AcceptanceCriteria @("ExitCode == 0", "Deterministic output")

        $claim = Register-SenClaim -Workspace $ws -ClaimId "CLAIM-100" -Claim "Engine is deterministic" `
            -Scope "Tier3" -Proposer "agent-a" -CodePaths @("src/engine.ps1") `
            -Tests @("tests/Engine.Tests.ps1") -Assumptions @("PowerShell 5.1+ runtime") `
            -FalsificationPlanId $plan.planId

        # AV-05: Default state must be INCONCLUSIVE, never VERIFIED
        Assert-Equal "INCONCLUSIVE" $claim.status "New claim must start as INCONCLUSIVE (AV-05)"

        # AV-05: Without evidence, Independent Judge must keep it INCONCLUSIVE
        $vNoEv = Invoke-SenIndependentVerdict -Workspace $ws -ClaimId "CLAIM-100" -Reviewer "agent-judge" -RiskTier "Tier3"
        Assert-Equal "INCONCLUSIVE" $vNoEv.Verdict "Claim without executable evidence must remain INCONCLUSIVE"

        # AV-01: Self-approval (Proposer == Reviewer) must be REJECTED
        $vSelf = Invoke-SenIndependentVerdict -Workspace $ws -ClaimId "CLAIM-100" -Reviewer "agent-a" -RiskTier "Tier3"
        Assert-Equal "REJECTED" $vSelf.Verdict "Self-approval by Proposer must be REJECTED (AV-01)"

        # AV-06: Fake verbal command in Invoke-SenExecutableEvidence must throw
        $fakeEvBlocked = $false
        try {
            [void](Invoke-SenExecutableEvidence -Workspace $ws -ClaimId "CLAIM-100" -Verifier "agent-verifier" -Command "manual")
        }
        catch {
            $fakeEvBlocked = $true
        }
        Assert-True $fakeEvBlocked "Invoke-SenExecutableEvidence must block verbal/manual command strings"

        # Execute real evidence
        $ev = Invoke-SenExecutableEvidence -Workspace $ws -ClaimId "CLAIM-100" -Verifier "agent-verifier" `
            -Command "Write-Output 'verified-42'" `
            -CommandRunner { param($c) [pscustomobject]@{ ExitCode = 0; Output = "verified-42" } }
        Assert-Equal 0 $ev.exit_code "Executable evidence must record ExitCode 0"
        Assert-True $ev.passed "Executable evidence must mark passed = true"

        # AV-02: Counterexample challenge by independent Adversary
        $ce = Register-SenCounterexample -Workspace $ws -ClaimId "CLAIM-100" -Adversary "agent-adversary" `
            -Scenario "Null parameter boundary invocation" `
            -TestCommand "Invoke-NullBoundaryCheck" `
            -ExpectedOutcome "Handles null gracefully with exit 0" `
            -CommandRunner { param($c) [pscustomobject]@{ ExitCode = 0; Output = "survived-null" } }
        Assert-True $ce.survived "Counterexample with ExitCode 0 must mark survived = true"

        # AV-03: Blind Review Package strips Proposer subjective fields
        $blindPkg = Get-SenBlindReviewPackage -Workspace $ws -ClaimId "CLAIM-100"
        Assert-True $blindPkg.evidenceFresh "Evidence must be fresh before any code edits"
        Assert-True ($blindPkg.strippedProposerFields -contains "selfVerdict") "Blind Review must strip Proposer selfVerdict"

        # Independent Judge issues VERIFIED verdict
        $vPass = Invoke-SenIndependentVerdict -Workspace $ws -ClaimId "CLAIM-100" -Reviewer "agent-judge" -RiskTier "Tier3"
        Assert-Equal "VERIFIED" $vPass.Verdict "Independent Judge must return VERIFIED when all evidence, falsification plan, and counterexamples pass"

        # AV-06: Modifying source file after VERIFIED must invalidate evidence back to INCONCLUSIVE
        [System.IO.File]::WriteAllText((Join-Path $ws "src/engine.ps1"), "function Get-Answer { return 0 }`n", [System.Text.Encoding]::UTF8)
        $vAfterEdit = Invoke-SenIndependentVerdict -Workspace $ws -ClaimId "CLAIM-100" -Reviewer "agent-judge" -RiskTier "Tier3"
        Assert-Equal "INCONCLUSIVE" $vAfterEdit.Verdict "Code modification after evidence capture must invalidate VERIFIED back to INCONCLUSIVE (AV-06)"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "AV-08, AV-09, AV-07: Lock-SenQualityBaseline, Test-SenAntiMetricGaming, and Invoke-SenGovernanceNegativeTest block test dilution and criteria lowering" {
    $ws = New-AdversarialTestWorkspace
    try {
        [void](New-SenTask -Workspace $ws -Id "TASK-AMG-01" -Title "Security Gate" -Module "dev" -Assignee "dev-1" -AcceptanceCriteria @("Zero SQLi", "100% unit test pass"))
        $base = Lock-SenQualityBaseline -Workspace $ws
        Assert-Equal 1 $base.totalTestFiles "Baseline must lock 1 test file"
        Assert-Equal 3 $base.totalAssertions "Baseline must lock 3 assertions in Engine.Tests.ps1"

        $cleanCheck = Test-SenAntiMetricGaming -Workspace $ws
        Assert-True $cleanCheck.Passed "Unmodified workspace must pass Test-SenAntiMetricGaming"

        # Simulate AV-08 Test Dilution (dropping from 3 assertions to 1 assertion)
        [System.IO.File]::WriteAllText((Join-Path $ws "tests/Engine.Tests.ps1"), "Assert-Equal 42 42`n", [System.Text.Encoding]::UTF8)
        # Simulate AV-09 Criteria Lowering
        $tasks = @(Get-SenTasks -Workspace $ws)
        $tasks[0].acceptanceCriteria = @("Just compile")
        [void](Save-SenTasks -Workspace $ws -Tasks $tasks)

        $tamperCheck = Test-SenAntiMetricGaming -Workspace $ws
        Assert-True (-not $tamperCheck.Passed) "Test-SenAntiMetricGaming must fail when assertions drop or criteria are modified"
        Assert-Equal 2 $tamperCheck.Violations.Count "Must detect both AV-08 and AV-09 violations"

        # Run full sandboxed Negative Test Suite (AV-07)
        $negAudit = Invoke-SenGovernanceNegativeTest -Workspace $ws
        Assert-True $negAudit.Passed "All 5 Governance Negative Tests (AV-01..AV-09) must pass"
        Assert-Equal 5 $negAudit.TotalChecks "Must execute 5 negative test suites"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "BVC-01..BVC-10 & Quarantine-and-Continue: Set-SenVerificationPolicy, Invoke-SenFindingTriage, Invoke-SenBoundedRepairRound, New-SenEscalationDossier, Invoke-SenEscalationQuarantine, and all 8 Bounded Verification Scenarios" {
    $ws = New-AdversarialTestWorkspace
    try {
        [void](New-SenTask -Workspace $ws -Id "TASK-DEP-01" -Title "Depends on BVC-01" -Module "dev" -Assignee "dev-1" -DependsOn @("CLAIM-BVC-01"))
        [void](New-SenTask -Workspace $ws -Id "TASK-IND-01" -Title "Independent module" -Module "dev" -Assignee "dev-2" -AllowedPaths @("src/independent.ps1"))
        $rp = New-SenRestorePoint -Workspace $ws -Files @("src/engine.ps1") -Label "pre-bvc"
        $pol = Set-SenVerificationPolicy -Workspace $ws -ClaimId "CLAIM-BVC-01" -TaskType "Complex" `
            -ScopePaths @("src/engine.ps1") -AcceptanceCriteria @("Zero SQLi", "p95 < 30ms") -RestorePointId $rp.Id
        Assert-Equal "VERIFYING" $pol.state "Initial bounded loop state must be VERIFYING"
        Assert-Equal 3 $pol.maxReviewRounds "Complex task must default to 3 review rounds"
        Assert-Equal 2 $pol.maxRepairAttempts "Complex task must default to 2 repair attempts"

        # Triage mixed findings: C0 in-scope + C3 style + Out-of-scope C2 + Verbal without evidence
        $triage = Invoke-SenFindingTriage -Workspace $ws -ClaimId "CLAIM-BVC-01" -Findings @(
            [pscustomobject]@{ id = "F-C0"; title = "SQL Injection in query"; severity = "C2"; path = "src/engine.ps1"; testCommand = "Invoke-SqlMapProbe" },
            [pscustomobject]@{ id = "F-C3"; title = "Rename variable x to count"; severity = "C3"; path = "src/engine.ps1"; testCommand = "Invoke-Linter" },
            [pscustomobject]@{ id = "F-OOS"; title = "Optimize unrelated module"; severity = "C2"; path = "src/other.ps1"; testCommand = "Invoke-Perf" },
            [pscustomobject]@{ id = "F-NOEV"; title = "Unproven theoretical flaw"; severity = "C1"; path = "src/engine.ps1"; testCommand = "none" }
        )
        Assert-Equal "REPAIR" $triage.State "Must transition to REPAIR when C0/C1 blocker exists and budget remains"
        Assert-Equal 1 $triage.Gate1Blockers.Count "Only in-scope C0 must block Gate 1"
        Assert-Equal "C0" $triage.Gate1Blockers[0].severity "Anti-downgrade floor must elevate SQL Injection from C2 to C0"
        Assert-Equal 2 $triage.Gate2Deferred.Count "C3 and Out-of-Scope C2 must be deferred to Gate 2 Backlog"
        Assert-Equal 1 $triage.IgnoredNoEvidence.Count "Finding without executable evidence must be ignored"

        # Simulate Repair Attempt 1 that fails to resolve F-C0 (Non-progress -> ESCALATED & Quarantined in place)
        [System.IO.File]::WriteAllText((Join-Path $ws "src/engine.ps1"), "function Get-Answer { return 'scene-preserved' }`n", [System.Text.Encoding]::UTF8)
        $rep1 = Invoke-SenBoundedRepairRound -Workspace $ws -ClaimId "CLAIM-BVC-01" -RemainingFindings @(
            [pscustomobject]@{ id = "F-C0"; title = "SQL Injection in query"; severity = "C0" }
        )
        Assert-Equal "ESCALATED" $rep1.State "Zero progress on C0 finding must escalate immediately"
        Assert-True ($null -ne $rep1.EscalationDossier) "Escalated state must produce an EscalationDossier via New-SenEscalationDossier"
        Assert-Equal "PRE_GIT_PUSH_GATE" $rep1.EscalationDossier.reviewRequiredAt "Escalation review is deferred to PRE_GIT_PUSH_GATE so independent work continues"

        # Verify Terminal Lock (cannot re-enter repair/triage once ESCALATED -> zero outer loop!)
        $outerLoopBlocked = $false
        try { [void](Invoke-SenBoundedRepairRound -Workspace $ws -ClaimId "CLAIM-BVC-01" -RemainingFindings @()) } catch { $outerLoopBlocked = $true }
        Assert-True $outerLoopBlocked "ESCALATED state must be terminal and block any further repair loops"

        # Verify Quarantine-and-Continue: scene preserved on disk, dependent task blocked, independent task continues!
        $qStatus = Invoke-SenEscalationQuarantine -Workspace $ws -ClaimId "CLAIM-BVC-01"
        Assert-True $qStatus.Quarantined "Claim must be quarantined in place"
        Assert-True $qStatus.CanContinueOtherWork "Must allow independent tasks to continue automatically"
        Assert-True ($qStatus.BlockedDependentTaskIds -contains "TASK-DEP-01") "Dependent task must be quarantined"
        Assert-True ($qStatus.ContinuableTaskIds -contains "TASK-IND-01") "Independent task must remain continuable"
        $sceneCode = [System.IO.File]::ReadAllText((Join-Path $ws "src/engine.ps1"), [System.Text.Encoding]::UTF8)
        Assert-True ($sceneCode -match "scene-preserved") "Crime scene on disk must be preserved intact (no destructive auto-rollback)"

        # Complete the independent task automatically, then verify Pre-Push Gate stops for human review of ESCALATED
        [void](Start-SenTask -Workspace $ws -Id "TASK-IND-01")
        [void](Submit-SenTaskForReview -Workspace $ws -Id "TASK-IND-01")
        [void](Complete-SenTaskReview -Workspace $ws -Id "TASK-IND-01" -Passed $true -Reviewer "qa-judge" -EvidenceCommand "Invoke-IndTest" -ExitCode 0)
        $pushGate = Invoke-SenCiPushLoop -RepoPath $ws -SkipPush
        Assert-True (-not $pushGate.LocalPassed) "Invoke-SenCiPushLoop must stop before git push when quarantined ESCALATED claims exist"

        # Run all 8 Special Scenarios from Section 6 + direct Measure-SenAdversarialProgress check
        $progCheck = Measure-SenAdversarialProgress -PreviousFindings @([pscustomobject]@{ id = "A" }) -CurrentFindings @([pscustomobject]@{ id = "B" }, [pscustomobject]@{ id = "C" })
        Assert-True $progCheck.NonProgress "Measure-SenAdversarialProgress must flag NonProgress when new findings exceed resolved findings"
        $all8 = Invoke-SenBoundedVerificationScenarios -Workspace $ws
        Assert-True $all8.Passed "All 8 Bounded Adversarial Verification Scenarios must pass"
        Assert-Equal 8 $all8.TotalScenarios "Must verify all 8 scenarios"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Zero-Trust Physical Gate & GAP-01..04: Install-SenGitHooks, Sync-SenOfficeState, SHA256/TTL Evidence, Stack/TTL Lessons, and Auto-Clarification" {
    $ws = New-AdversarialTestWorkspace
    try {
        # 1. GAP-02: Register-SenEvidence computes subjectHash (SHA-256) and Test-SenEvidenceValidity catches SHA256_MISMATCH & TTL_EXPIRED
        $evHash = Register-SenEvidence -Workspace $ws -EvidenceId "EV-HASH-01" -SubjectPath "src/engine.ps1" -TTLMinutes 60 -Command "Invoke-Unit" -ExitCode 0
        Assert-True (-not [string]::IsNullOrWhiteSpace($evHash.subjectHash)) "Register-SenEvidence must compute SHA-256 subjectHash"
        $origTime = (Get-Item -LiteralPath (Join-Path $ws "src/engine.ps1")).LastWriteTimeUtc
        [System.IO.File]::WriteAllText((Join-Path $ws "src/engine.ps1"), "function Get-Answer { return 999 }`n", [System.Text.Encoding]::UTF8)
        (Get-Item -LiteralPath (Join-Path $ws "src/engine.ps1")).LastWriteTimeUtc = $origTime.AddMinutes(-10)
        $valHash = Test-SenEvidenceValidity -Workspace $ws
        Assert-True ($valHash.StaleEvidenceIds -contains "EV-HASH-01") "Test-SenEvidenceValidity must detect SHA-256 tampering even if timestamp is backdated"
        Assert-Equal "SHA256_MISMATCH" $valHash.StaleReasons["EV-HASH-01"] "Reason must be SHA256_MISMATCH"

        [void](Register-SenEvidence -Workspace $ws -EvidenceId "EV-TTL-01" -SubjectPath "src/engine.ps1" -TTLMinutes -5 -Command "Invoke-Unit" -ExitCode 0)
        $valTtl = Test-SenEvidenceValidity -Workspace $ws
        Assert-True ($valTtl.StaleEvidenceIds -contains "EV-TTL-01") "Test-SenEvidenceValidity must detect expired TTLMinutes"
        Assert-Equal "TTL_EXPIRED" $valTtl.StaleReasons["EV-TTL-01"] "Reason must be TTL_EXPIRED"

        # 2. GAP-03: Get-SenExecutionLessons filters out expired lessons and filters by -Stack
        [void](Add-SenExecutionLesson -Workspace $ws -Category "db" -Problem "P1" -Solution "S1" -Stack "all")
        [void](Add-SenExecutionLesson -Workspace $ws -Category "ui" -Problem "P2" -Solution "S2" -Stack "react")
        [void](Add-SenExecutionLesson -Workspace $ws -Category "api" -Problem "P3" -Solution "S3" -Stack "fastapi")
        [void](Add-SenExecutionLesson -Workspace $ws -Category "old" -Problem "P4" -Solution "S4" -Stack "react" -ExpiresAt "2020-01-01T00:00:00Z")
        $reactLessons = @(Get-SenExecutionLessons -Workspace $ws -Stack "react")
        Assert-Equal 2 $reactLessons.Count "Get-SenExecutionLessons -Stack react must return 'all' + 'react' and exclude expired/fastapi"
        $allWithExp = @(Get-SenExecutionLessons -Workspace $ws -IncludeExpired)
        Assert-Equal 4 $allWithExp.Count "Get-SenExecutionLessons -IncludeExpired must include expired lessons"

        # 3. GAP-04: Register-SenRequirement auto-flags TODO / TBD / ??? in title as NEEDS_CLARIFICATION
        $reqTodo = Register-SenRequirement -Workspace $ws -Id "REQ-TODO-01" -Title "Support OAuth2 provider TBD ???"
        Assert-Equal "NEEDS_CLARIFICATION" $reqTodo.Requirement.status "Title with TBD/TODO/??? must auto-set status to NEEDS_CLARIFICATION"

        # 4. Attack 1 Defense: Install-SenGitHooks installs physical pre-commit and pre-push hooks
        [System.IO.Directory]::CreateDirectory((Join-Path $ws ".git")) | Out-Null
        $hookRes = Install-SenGitHooks -Workspace $ws -Force
        Assert-True $hookRes.Installed "Install-SenGitHooks must succeed when .git exists"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".git/hooks/pre-commit")) "pre-commit hook must exist on disk"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".git/hooks/pre-push")) "pre-push hook must exist on disk"

        # 5. Attack 3 & 5 Defense: Sync-SenOfficeState prunes stale items, seals state, and detects direct tampering
        $sync1 = Sync-SenOfficeState -Workspace $ws -PruneStale -UpdateSeal
        Assert-True $sync1.Synced "Initial Sync-SenOfficeState -UpdateSeal must be synced"
        Assert-Equal 1 $sync1.PrunedLessons "Must prune the 1 expired lesson"
        Assert-True (Test-Path -LiteralPath $sync1.SealPath) "state-seal.json must be created"

        # Tamper directly with .agents/office/requirements.json without updating seal
        $reqFile = Join-Path $ws ".agents/office/requirements.json"
        $rawReq = [System.IO.File]::ReadAllText($reqFile, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($reqFile, ($rawReq.Replace("NEEDS_CLARIFICATION", "Verified")), [System.Text.Encoding]::UTF8)
        $sync2 = Sync-SenOfficeState -Workspace $ws -VerifySeal
        Assert-True $sync2.Tampered "Sync-SenOfficeState -VerifySeal must detect direct JSON tampering"
        Assert-True ($sync2.TamperedFiles -contains "requirements.json") "TamperedFiles must identify requirements.json"
        Assert-True ($sync2.RemediationCommand -match "Sync-SenOfficeState") "Must return 1-line RemediationCommand"

        $gateTampered = Test-SenDeliveryGate -Workspace $ws -EnforcePhysicalDiff
        Assert-True (-not $gateTampered.Passed) "Test-SenDeliveryGate must fail when state-seal.json detects tampering"
        Assert-True ($gateTampered.RemediationCommands.Count -gt 0) "Test-SenDeliveryGate must provide 1-line RemediationCommands on failure"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Cross-Session Skill Capture & Pattern Automation: Register-SenActionPattern and New-SenCapturedSkill" {
    $ws = New-AdversarialTestWorkspace
    try {
        $steps = @("Run database schema diff", "Apply migration script", "Verify foreign key constraints")
        $p1 = Register-SenActionPattern -Workspace $ws -PatternName "sen-db-migration-flow" -Steps $steps -Category "workflow" -RepeatThreshold 2
        Assert-Equal 1 $p1.Occurrences "First pattern execution must have Occurrences = 1"
        Assert-True (-not $p1.ShouldCapture) "ShouldCapture must be false before reaching RepeatThreshold"
        Assert-Equal "db-migration-flow" $p1.SuggestedSkillName "SuggestedSkillName must strip reserved 'sen-' prefix"

        $p2 = Register-SenActionPattern -Workspace $ws -PatternName "sen-db-migration-flow" -Steps $steps -Category "workflow" -RepeatThreshold 2
        Assert-Equal 2 $p2.Occurrences "Second pattern execution must increment Occurrences to 2"
        Assert-True $p2.ShouldCapture "ShouldCapture must be true when Occurrences >= RepeatThreshold and not yet captured"

        $blockedPrefix = $false
        try {
            [void](New-SenCapturedSkill -Workspace $ws -SkillName "sen-forbidden-name" -Description "Should fail" -Steps $steps)
        }
        catch {
            $blockedPrefix = $true
        }
        Assert-True $blockedPrefix "New-SenCapturedSkill must block reserved 'sen-' prefix by default"

        $cap = New-SenCapturedSkill -Workspace $ws -SkillName $p2.SuggestedSkillName -Description "Automates DB migration diff, apply, and FK verification." -Steps $steps -Commands @("Write-Output 'migrated'") -PatternId $p2.PatternId
        Assert-True $cap.Created "New-SenCapturedSkill must report Created = true"
        Assert-True (Test-Path -LiteralPath $cap.SkillPath) "SKILL.md must be created in .agents/skills/<name>/SKILL.md"
        Assert-True (Test-Path -LiteralPath $cap.ScriptPs1Path) "0-token PowerShell runner scripts/run.ps1 must be created"
        Assert-True (Test-Path -LiteralPath $cap.ScriptShPath) "0-token POSIX runner scripts/run.sh must be created"

        $p3 = Register-SenActionPattern -Workspace $ws -PatternName "sen-db-migration-flow" -Steps $steps -Category "workflow" -RepeatThreshold 2
        Assert-Equal 3 $p3.Occurrences "Third pattern execution must increment Occurrences to 3"
        Assert-Equal "db-migration-flow" $p3.CapturedSkill "Pattern record must remember CapturedSkill"
        Assert-True (-not $p3.ShouldCapture) "ShouldCapture must become false after skill is captured"

        [void](New-SenTask -Workspace $ws -Id "TASK-PIPE-1" -Title "Post-code pipeline test task" -Status "reviewing")
        [void](Complete-SenTaskReview -Workspace $ws -Id "TASK-PIPE-1" -Passed $true -Reviewer "qa" -EvidenceCommand "tests/run.ps1" -ExitCode 0)
        $pipe = Invoke-SenPostCodePipeline -Workspace $ws -CodePath (Join-Path $ws "src") -TaskId "TASK-PIPE-1" -SubjectPath (Join-Path $ws "src/engine.ps1")
        Assert-True $pipe.Passed "Invoke-SenPostCodePipeline must pass on clean verified workspace"
        Assert-True $pipe.ReadyToPush "Invoke-SenPostCodePipeline must report ReadyToPush = true when all 6 steps pass"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}
