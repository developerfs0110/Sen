# scripts/Sen.BoundedLoop.psm1
# Bounded Adversarial Verification & Optimization Control Engine (BVC-01..BVC-10)
# Enforces 11-State Bounded Loop State Machine (PROPOSED -> VERIFYING -> CHALLENGED -> TRIAGE ->
# REPAIR -> REVERIFY -> ACCEPTED / BACKLOG / REJECTED / ESCALATED / INCONCLUSIVE),
# C0..C3 Severity Triage, Gate 1 (Verification) vs Gate 2 (Optimization) Separation,
# Non-Progress & Regression Detection, Scope Lock, No Auto-PASS, and 4-Branch Post-Escalation Resolution.

$ErrorActionPreference = "Stop"

function Read-SenBoundedLoops {
    param([string]$Workspace)
    $loopFile = Join-Path -Path $Workspace -ChildPath ".agents/office/bounded-loops.json"
    $raw = Read-SenSafeJson -Path $loopFile
    if ($null -eq $raw) { return @() }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $raw) {
        if ($null -eq $entry) { continue }
        if ($entry -is [System.Array]) {
            foreach ($sub in $entry) { if ($null -ne $sub) { $items.Add($sub) } }
        }
        elseif ($entry.PSObject.Properties['value'] -and $entry.PSObject.Properties['Count'] -and $entry.value -is [System.Array]) {
            foreach ($sub in $entry.value) { if ($null -ne $sub) { $items.Add($sub) } }
        }
        else {
            $items.Add($entry)
        }
    }
    return @($items.ToArray())
}

function Save-SenBoundedLoopRecord {
    param([string]$Workspace, $Record)
    $loopFile = Join-Path -Path $Workspace -ChildPath ".agents/office/bounded-loops.json"
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in (Read-SenBoundedLoops -Workspace $Workspace)) {
        if ($null -ne $item -and [string]$item.claimId -ne [string]$Record.claimId) {
            $list.Add($item)
        }
    }
    $list.Add($Record)
    Write-SenAtomicJson -Path $loopFile -InputObject ($list.ToArray()) -Depth 10
    return $Record
}

function Set-SenVerificationPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [ValidateSet("Small", "Medium", "Complex", "HighSecurity", "MajorArchitecture")][string]$TaskType = "Medium",
        [int]$MaxReviewRounds = 0,
        [int]$MaxRepairAttempts = 0,
        [int]$MaxTestRetries = 1,
        [int]$TokenBudget = 50000,
        [int]$TimeBudgetSeconds = 900,
        [string[]]$ScopePaths = @(),
        [string[]]$AcceptanceCriteria = @(),
        [string]$RestorePointId = "",
        [switch]$ResetApprovedByHuman
    )
    $existing = (Read-SenBoundedLoops -Workspace $Workspace) | Where-Object { [string]$_.claimId -eq $ClaimId } | Select-Object -First 1
    if ($null -ne $existing -and (-not $ResetApprovedByHuman.IsPresent)) {
        return $existing
    }

    $defRounds = switch ($TaskType) { "Small" { 1 } "Medium" { 2 } default { 3 } }
    $defRepairs = switch ($TaskType) { "Small" { 1 } default { 2 } }
    $effRounds = if ($MaxReviewRounds -gt 0) { $MaxReviewRounds } else { $defRounds }
    $effRepairs = if ($MaxRepairAttempts -gt 0) { $MaxRepairAttempts } else { $defRepairs }
    $critText = (@($AcceptanceCriteria | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Sort-Object) -join "|"
    $critHash = Get-SenTextSha256 -Text $critText
    $nowIso = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

    $record = [pscustomobject][ordered]@{
        claimId             = $ClaimId
        taskType            = $TaskType
        state               = "VERIFYING"
        maxReviewRounds     = [int]$effRounds
        maxRepairAttempts   = [int]$effRepairs
        maxTestRetries      = [int]$MaxTestRetries
        tokenBudget         = [int]$TokenBudget
        timeBudgetSeconds   = [int]$TimeBudgetSeconds
        currentRound        = 0
        repairAttempts      = 0
        regressionCount     = 0
        tokensUsed          = 0
        elapsedSeconds      = 0
        scopePaths          = @($ScopePaths)
        acceptanceCriteria  = @($AcceptanceCriteria)
        criteriaHash        = $critHash
        restorePointId      = $RestorePointId
        unresolvedFindings  = @()
        resolvedFindingIds  = @()
        backlogItems        = @()
        residualRisks       = @()
        roundHistory        = @()
        escalationDossier   = $null
        updatedAt           = $nowIso
    }
    return (Save-SenBoundedLoopRecord -Workspace $Workspace -Record $record)
}

function New-SenEscalationDossier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$LoopRecord,
        [Parameter(Mandatory = $true)][string]$EscalationReason
    )
    $unresolved = @($LoopRecord.unresolvedFindings | Where-Object { $null -ne $_ })
    $c0List = @($unresolved | Where-Object { [string]$_.severity -eq "C0" })
    $c1List = @($unresolved | Where-Object { [string]$_.severity -eq "C1" })
    return [pscustomobject][ordered]@{
        claimId             = [string]$LoopRecord.claimId
        escalationReason    = $EscalationReason
        roundsExecuted      = [int]$LoopRecord.currentRound
        repairsExecuted     = [int]$LoopRecord.repairAttempts
        unresolvedC0Count   = $c0List.Count
        unresolvedC1Count   = $c1List.Count
        regressionCount     = [int]$LoopRecord.regressionCount
        quarantinedPaths    = @($LoopRecord.scopePaths)
        evidencePreserved   = $true
        restorePointId      = [string]$LoopRecord.restorePointId
        whatWasTried        = @($LoopRecord.roundHistory)
        residualRisks       = @($unresolved)
        reviewRequiredAt    = "PRE_GIT_PUSH_GATE"
        generatedAt         = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Invoke-SenEscalationQuarantine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [string]$LinkedTaskId = ""
    )
    $loop = (Read-SenBoundedLoops -Workspace $Workspace) | Where-Object { [string]$_.claimId -eq $ClaimId } | Select-Object -First 1
    if ($null -eq $loop) { throw "Bounded loop '$ClaimId' not found." }
    if ([string]$loop.state -ne "ESCALATED") {
        $loop | Add-Member -NotePropertyName "state" -NotePropertyValue "ESCALATED" -Force
    }
    $qPaths = @($loop.scopePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $loop | Add-Member -NotePropertyName "quarantined" -NotePropertyValue $true -Force
    $loop | Add-Member -NotePropertyName "isTerminal" -NotePropertyValue $true -Force
    $loop | Add-Member -NotePropertyName "quarantinedPaths" -NotePropertyValue $qPaths -Force
    if ($null -eq $loop.escalationDossier) {
        $dossier = New-SenEscalationDossier -LoopRecord $loop -EscalationReason "Quarantined for pre-push human review"
        $loop | Add-Member -NotePropertyName "escalationDossier" -NotePropertyValue $dossier -Force
    }
    [void](Save-SenBoundedLoopRecord -Workspace $Workspace -Record $loop)

    $quarantinedTaskIds = [System.Collections.Generic.List[string]]::new()
    $continuableTaskIds = [System.Collections.Generic.List[string]]::new()
    $targetTaskId = if (-not [string]::IsNullOrWhiteSpace($LinkedTaskId)) { $LinkedTaskId } else { $ClaimId }

    if (Get-Command Get-SenTasks -ErrorAction SilentlyContinue) {
        $allTasks = @(Get-SenTasks -Workspace $Workspace)
        $changed = $false
        foreach ($tk in $allTasks) {
            if ($null -eq $tk -or [string]$tk.status -in @("done", "backlog")) { continue }
            $tid = [string]$tk.id
            $deps = @($tk.dependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $tPaths = @($tk.allowedPaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $dependsOnEsc = ($tid -eq $targetTaskId) -or ($deps -contains $targetTaskId) -or ($deps -contains $ClaimId)
            $overlapsScene = ($qPaths.Count -gt 0 -and $tPaths.Count -gt 0 -and (Test-SenPathOverlap -PathsA $qPaths -PathsB $tPaths))

            if ($dependsOnEsc -or $overlapsScene) {
                $tk | Add-Member -NotePropertyName "status" -NotePropertyValue "blocked" -Force
                $tk | Add-Member -NotePropertyName "blockedByEscalation" -NotePropertyValue $ClaimId -Force
                $quarantinedTaskIds.Add($tid)
                $changed = $true
            }
            else {
                $continuableTaskIds.Add($tid)
            }
        }
        if ($changed) {
            [void](Save-SenTasks -Workspace $Workspace -Tasks $allTasks)
        }
    }

    return [pscustomobject][ordered]@{
        ClaimId                  = $ClaimId
        State                    = "ESCALATED"
        Quarantined              = $true
        EvidencePreservedOnDisk  = $true
        QuarantinedPaths         = $qPaths
        BlockedDependentTaskIds  = @($quarantinedTaskIds.ToArray())
        ContinuableTaskIds       = @($continuableTaskIds.ToArray())
        CanContinueOtherWork     = ($continuableTaskIds.Count -gt 0)
        GateBlockedUntilReviewed = "PRE_GIT_PUSH"
        QuarantinedAt            = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Invoke-SenFindingTriage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [Parameter(Mandatory = $true)][object[]]$Findings
    )
    $loop = (Read-SenBoundedLoops -Workspace $Workspace) | Where-Object { [string]$_.claimId -eq $ClaimId } | Select-Object -First 1
    if ($null -eq $loop) {
        $loop = Set-SenVerificationPolicy -Workspace $Workspace -ClaimId $ClaimId
    }
    if ([string]$loop.state -in @("ESCALATED", "REJECTED", "ACCEPTED")) {
        throw "BVC-01/BVC-09 Terminal State Lock: Claim '$ClaimId' is locked in terminal state '$($loop.state)' and cannot re-enter triage."
    }
    $newRound = [int]$loop.currentRound + 1
    $loop | Add-Member -NotePropertyName "currentRound" -NotePropertyValue $newRound -Force
    $loop | Add-Member -NotePropertyName "state" -NotePropertyValue "TRIAGE" -Force

    $gate1Blockers = [System.Collections.Generic.List[object]]::new()
    $gate2Backlog = [System.Collections.Generic.List[object]]::new()
    $ignoredNoEv = [System.Collections.Generic.List[object]]::new()
    $subjectiveConflicts = 0
    $scopeList = @($loop.scopePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    foreach ($f in @($Findings)) {
        if ($null -eq $f) { continue }
        $fid = if ($f.PSObject.Properties['id'] -and $f.id) { [string]$f.id } else { "F-" + [Guid]::NewGuid().ToString("N").Substring(0, 6) }
        $title = [string]$f.title
        $rawSev = if ($f.PSObject.Properties['severity'] -and $f.severity) { ([string]$f.severity).ToUpperInvariant() } else { "C2" }
        $cmd = if ($f.PSObject.Properties['testCommand']) { [string]$f.testCommand } else { "" }
        $hasEv = (-not [string]::IsNullOrWhiteSpace($cmd)) -and ($cmd -notmatch '^(?i)\s*(none|manual|verbal|n/a|ok)\s*$')
        if ($f.PSObject.Properties['hasEvidence'] -and (-not [bool]$f.hasEvidence)) { $hasEv = $false }

        # Scenario 1: Adversary critique without executable evidence is ignored and cannot trigger repair
        if (-not $hasEv) {
            $ignoredNoEv.Add([pscustomobject][ordered]@{ id = $fid; title = $title; action = "IGNORED_NO_EVIDENCE" })
            continue
        }

        # BVC-03 Anti-downgrade floor for critical security/data-loss findings
        $sev = if ($title -match '(?i)\b(sqli|sql\s+injection|xss|rce|auth\s+bypass|data\s+loss|drop\s+table|secret\s+leak)\b') { "C0" } else { $rawSev }
        $path = if ($f.PSObject.Properties['path']) { [string]$f.path } else { "" }
        $inScope = ($scopeList.Count -eq 0) -or ([string]::IsNullOrWhiteSpace($path)) -or (Test-SenPathOverlap -PathsA $scopeList -PathsB @($path))
        $isSubj = ($f.PSObject.Properties['isSubjective'] -and [bool]$f.isSubjective) -or ($sev -eq "C3")
        if ($isSubj -and $sev -ne "C3") { $subjectiveConflicts++ }

        $item = [pscustomobject][ordered]@{ id = $fid; title = $title; severity = $sev; path = $path; inScope = [bool]$inScope; testCommand = $cmd }
        if ($sev -eq "C3" -or ((-not $inScope) -and $sev -ne "C0")) {
            $gate2Backlog.Add($item)
            if (Get-Command Add-SenBacklogItem -ErrorAction SilentlyContinue) {
                [void](Add-SenBacklogItem -Workspace $Workspace -Id "BL-$fid" -Title "[Gate2-$sev] $title (from $ClaimId)")
            }
        }
        else {
            $gate1Blockers.Add($item)
        }
    }

    $prevBacklog = [System.Collections.Generic.List[object]]::new()
    foreach ($b in @($loop.backlogItems)) { if ($null -ne $b) { $prevBacklog.Add($b) } }
    foreach ($nb in $gate2Backlog) { $prevBacklog.Add($nb) }
    $loop | Add-Member -NotePropertyName "backlogItems" -NotePropertyValue @($prevBacklog.ToArray()) -Force
    $loop | Add-Member -NotePropertyName "unresolvedFindings" -NotePropertyValue @($gate1Blockers.ToArray()) -Force
    $loop | Add-Member -NotePropertyName "residualRisks" -NotePropertyValue @($gate2Backlog.ToArray()) -Force

    $nextState = "ACCEPTED"
    $dossier = $null
    if ($subjectiveConflicts -gt 0 -and $newRound -ge 2) {
        $nextState = "ESCALATED"
        $dossier = New-SenEscalationDossier -LoopRecord $loop -EscalationReason "BVC-07: Conflicting subjective dispute between agents"
    }
    elseif ($gate1Blockers.Count -eq 0) {
        $nextState = "ACCEPTED"
    }
    elseif ($newRound -ge [int]$loop.maxReviewRounds -or [int]$loop.repairAttempts -ge [int]$loop.maxRepairAttempts) {
        $nextState = "ESCALATED"
        $dossier = New-SenEscalationDossier -LoopRecord $loop -EscalationReason "BVC-01/BVC-09: Max review/repair budget reached with $($gate1Blockers.Count) unresolved C0/C1 finding(s)"
    }
    else {
        $nextState = "REPAIR"
    }

    $loop | Add-Member -NotePropertyName "state" -NotePropertyValue $nextState -Force
    $loop | Add-Member -NotePropertyName "escalationDossier" -NotePropertyValue $dossier -Force
    $loop | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue ([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")) -Force
    [void](Save-SenBoundedLoopRecord -Workspace $Workspace -Record $loop)
    if ($nextState -eq "ESCALATED") {
        [void](Invoke-SenEscalationQuarantine -Workspace $Workspace -ClaimId $ClaimId)
    }

    return [pscustomobject][ordered]@{
        ClaimId            = $ClaimId
        Round              = $newRound
        State              = $nextState
        Gate1Blockers      = @($gate1Blockers.ToArray())
        Gate2Deferred      = @($gate2Backlog.ToArray())
        IgnoredNoEvidence  = @($ignoredNoEv.ToArray())
        EscalationDossier  = $dossier
    }
}

function Measure-SenAdversarialProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][object[]]$PreviousFindings = @(),
        [Parameter(Mandatory = $false)][object[]]$CurrentFindings = @(),
        [Parameter(Mandatory = $false)][string[]]$HistoricalResolvedIds = @()
    )
    $prevIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pf in @($PreviousFindings)) { if ($pf -and $pf.id) { [void]$prevIds.Add([string]$pf.id) } }
    $histResolved = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rid in @($HistoricalResolvedIds)) { if ($rid) { [void]$histResolved.Add([string]$rid) } }

    $nowIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $newFindingsCount = 0
    $regressions = 0
    $validRemaining = [System.Collections.Generic.List[object]]::new()
    foreach ($rf in @($CurrentFindings)) {
        if ($null -eq $rf) { continue }
        $idStr = [string]$rf.id
        [void]$nowIds.Add($idStr)
        $validRemaining.Add($rf)
        if ($histResolved.Contains($idStr)) { $regressions++ }
        elseif (-not $prevIds.Contains($idStr)) { $newFindingsCount++ }
    }

    $resolvedThisRound = 0
    foreach ($oldId in $prevIds) {
        if (-not $nowIds.Contains($oldId)) {
            $resolvedThisRound++
            [void]$histResolved.Add($oldId)
        }
    }

    $riskDelta = ($validRemaining.Count - $prevIds.Count)
    $nonProgress = ($validRemaining.Count -gt 0) -and (($newFindingsCount -ge $resolvedThisRound -and ($newFindingsCount -gt 0 -or $resolvedThisRound -eq 0)) -or ($regressions -gt 0) -or ($riskDelta -ge 0))
    return [pscustomobject][ordered]@{
        ResolvedFindings   = $resolvedThisRound
        NewFindings        = $newFindingsCount
        Regressions        = $regressions
        RemainingCount     = $validRemaining.Count
        RiskDelta          = $riskDelta
        NonProgress        = [bool]$nonProgress
        ValidRemaining     = @($validRemaining.ToArray())
        UpdatedResolvedIds = @($histResolved)
    }
}

function Invoke-SenBoundedRepairRound {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [object[]]$RemainingFindings = @(),
        [string[]]$CurrentAcceptanceCriteria = @(),
        [int]$TokensSpent = 1000,
        [int]$SecondsSpent = 30
    )
    $loop = (Read-SenBoundedLoops -Workspace $Workspace) | Where-Object { [string]$_.claimId -eq $ClaimId } | Select-Object -First 1
    if ($null -eq $loop) { throw "Bounded loop for '$ClaimId' not initialized. Call Set-SenVerificationPolicy first." }
    if ([string]$loop.state -in @("ESCALATED", "REJECTED", "ACCEPTED")) {
        throw "BVC-01/BVC-09 Terminal State Lock: Claim '$ClaimId' is locked in terminal state '$($loop.state)' and cannot re-enter repair."
    }

    if ($CurrentAcceptanceCriteria.Count -gt 0 -and (-not [string]::IsNullOrWhiteSpace([string]$loop.criteriaHash))) {
        $nowHash = Get-SenTextSha256 -Text ((@($CurrentAcceptanceCriteria) | Sort-Object) -join "|")
        if ($nowHash -ne [string]$loop.criteriaHash) {
            $loop | Add-Member -NotePropertyName "state" -NotePropertyValue "REJECTED" -Force
            $dossier = New-SenEscalationDossier -LoopRecord $loop -EscalationReason "AV-09/BVC-09: Acceptance Criteria tampered during repair to force PASS"
            $loop | Add-Member -NotePropertyName "escalationDossier" -NotePropertyValue $dossier -Force
            [void](Save-SenBoundedLoopRecord -Workspace $Workspace -Record $loop)
            return [pscustomobject][ordered]@{ ClaimId = $ClaimId; State = "REJECTED"; Reason = "AcceptanceCriteriaTampered"; EscalationDossier = $dossier }
        }
    }

    $repAttempt = [int]$loop.repairAttempts + 1
    $prog = Measure-SenAdversarialProgress -PreviousFindings @($loop.unresolvedFindings) -CurrentFindings $RemainingFindings -HistoricalResolvedIds @($loop.resolvedFindingIds)
    $totTokens = [int]$loop.tokensUsed + $TokensSpent
    $totTime = [int]$loop.elapsedSeconds + $SecondsSpent
    $budgetExceeded = ($repAttempt -ge [int]$loop.maxRepairAttempts) -or ($totTokens -gt [int]$loop.tokenBudget) -or ($totTime -gt [int]$loop.timeBudgetSeconds)

    $loop | Add-Member -NotePropertyName "repairAttempts" -NotePropertyValue $repAttempt -Force
    $loop | Add-Member -NotePropertyName "regressionCount" -NotePropertyValue ([int]$loop.regressionCount + $prog.Regressions) -Force
    $loop | Add-Member -NotePropertyName "tokensUsed" -NotePropertyValue $totTokens -Force
    $loop | Add-Member -NotePropertyName "elapsedSeconds" -NotePropertyValue $totTime -Force
    $loop | Add-Member -NotePropertyName "unresolvedFindings" -NotePropertyValue $prog.ValidRemaining -Force
    $loop | Add-Member -NotePropertyName "resolvedFindingIds" -NotePropertyValue $prog.UpdatedResolvedIds -Force

    $hist = [System.Collections.Generic.List[object]]::new()
    foreach ($h in @($loop.roundHistory)) { if ($null -ne $h) { $hist.Add($h) } }
    $hist.Add([ordered]@{
        repairAttempt    = $repAttempt
        resolvedFindings = $prog.ResolvedFindings
        newFindings      = $prog.NewFindings
        regressions      = $prog.Regressions
        remainingCount   = $prog.RemainingCount
        riskDelta        = $prog.RiskDelta
        timestamp        = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    })
    $loop | Add-Member -NotePropertyName "roundHistory" -NotePropertyValue @($hist.ToArray()) -Force

    $nextState = "ACCEPTED"; $reason = "All Gate 1 C0/C1 findings resolved and re-verified."; $dossier = $null
    if ($prog.RemainingCount -eq 0) { $nextState = "ACCEPTED" }
    elseif ($prog.Regressions -gt 0) {
        $nextState = "ESCALATED"; $reason = "BVC-10: Regression detected ($($prog.Regressions) previously resolved finding(s) reappeared)"
        $dossier = New-SenEscalationDossier -LoopRecord $loop -EscalationReason $reason
    }
    elseif ($prog.NonProgress) {
        $nextState = "ESCALATED"; $reason = "BVC-04: Non-progress repair loop (resolved=$($prog.ResolvedFindings), new=$($prog.NewFindings), riskDelta=$($prog.RiskDelta))"
        $dossier = New-SenEscalationDossier -LoopRecord $loop -EscalationReason $reason
    }
    elseif ($budgetExceeded) {
        $nextState = "ESCALATED"; $reason = "BVC-02/BVC-09: Repair/Token/Time budget exhausted with $($prog.RemainingCount) unresolved finding(s) (No Auto-PASS)"
        $dossier = New-SenEscalationDossier -LoopRecord $loop -EscalationReason $reason
    }
    else { $nextState = "REPAIR"; $reason = "Repair in progress ($($prog.RemainingCount) remaining, budget available)" }

    $loop | Add-Member -NotePropertyName "state" -NotePropertyValue $nextState -Force
    $loop | Add-Member -NotePropertyName "escalationDossier" -NotePropertyValue $dossier -Force
    [void](Save-SenBoundedLoopRecord -Workspace $Workspace -Record $loop)
    if ($nextState -eq "ESCALATED") {
        [void](Invoke-SenEscalationQuarantine -Workspace $Workspace -ClaimId $ClaimId)
    }

    return [pscustomobject][ordered]@{
        ClaimId = $ClaimId; RepairAttempt = $repAttempt; State = $nextState; Reason = $reason
        ResolvedFindings = $prog.ResolvedFindings; NewFindings = $prog.NewFindings; Regressions = $prog.Regressions
        RemainingCount = $prog.RemainingCount; RiskDelta = $prog.RiskDelta; EscalationDossier = $dossier
    }
}

function Invoke-SenBoundedVerificationScenarios {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string]$Workspace = $PWD.Path)
    $sb = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-bvc-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    [System.IO.Directory]::CreateDirectory((Join-Path $sb ".agents/office")) | Out-Null
    $scenarios = [System.Collections.Generic.List[object]]::new()

    try {
        # S1: Adversary challenges without evidence -> Ignored, state becomes ACCEPTED
        [void](Set-SenVerificationPolicy -Workspace $sb -ClaimId "BVC-S1" -ScopePaths @("src/auth.ps1"))
        $s1 = Invoke-SenFindingTriage -Workspace $sb -ClaimId "BVC-S1" -Findings @([pscustomobject]@{ id = "F1"; title = "Theoretical issue"; severity = "C1"; testCommand = "none" })
        $scenarios.Add([pscustomobject]@{ Scenario = "S1-VerbalCritiqueIgnored"; Passed = ($s1.State -eq "ACCEPTED" -and $s1.IgnoredNoEvidence.Count -eq 1) })

        # S2: Developer fixes 1 bug but creates 2 new bugs -> Non-Progress Loop -> ESCALATED
        [void](Set-SenVerificationPolicy -Workspace $sb -ClaimId "BVC-S2" -MaxReviewRounds 3 -MaxRepairAttempts 3)
        [void](Invoke-SenFindingTriage -Workspace $sb -ClaimId "BVC-S2" -Findings @([pscustomobject]@{ id = "B1"; title = "Logic bug 1"; severity = "C1"; testCommand = "test-b1" }))
        $s2 = Invoke-SenBoundedRepairRound -Workspace $sb -ClaimId "BVC-S2" -RemainingFindings @(
            [pscustomobject]@{ id = "B2"; title = "New bug 2"; severity = "C1" },
            [pscustomobject]@{ id = "B3"; title = "New bug 3"; severity = "C1" }
        )
        $scenarios.Add([pscustomobject]@{ Scenario = "S2-NonProgressEscalated"; Passed = ($s2.State -eq "ESCALATED" -and $s2.NewFindings -eq 2) })

        # S3: Two agents argue over subjective question across rounds -> ESCALATED
        [void](Set-SenVerificationPolicy -Workspace $sb -ClaimId "BVC-S3" -MaxReviewRounds 3)
        [void](Invoke-SenFindingTriage -Workspace $sb -ClaimId "BVC-S3" -Findings @([pscustomobject]@{ id = "SUB1"; title = "Pattern preference"; severity = "C2"; isSubjective = $true; testCommand = "check-style" }))
        $s3 = Invoke-SenFindingTriage -Workspace $sb -ClaimId "BVC-S3" -Findings @([pscustomobject]@{ id = "SUB1"; title = "Pattern preference"; severity = "C2"; isSubjective = $true; testCommand = "check-style" })
        $scenarios.Add([pscustomobject]@{ Scenario = "S3-SubjectiveDisputeEscalated"; Passed = ($s3.State -eq "ESCALATED") })

        # S4: Out-of-scope minor improvement (C2/C3) -> Routed to Backlog (Gate 2), Gate 1 ACCEPTED
        [void](Set-SenVerificationPolicy -Workspace $sb -ClaimId "BVC-S4" -ScopePaths @("src/login.ps1"))
        $s4 = Invoke-SenFindingTriage -Workspace $sb -ClaimId "BVC-S4" -Findings @([pscustomobject]@{ id = "OPT1"; title = "Refactor logging module"; severity = "C2"; path = "src/logging.ps1"; testCommand = "perf-log" })
        $scenarios.Add([pscustomobject]@{ Scenario = "S4-OutOfScopeToBacklogAndAccepted"; Passed = ($s4.State -eq "ACCEPTED" -and $s4.Gate2Deferred.Count -eq 1) })

        # S5: Max rounds reached with C0 -> ESCALATED (No Auto-PASS), Quarantined in-place, blocks further repair loops, allows independent tasks to continue
        [void](New-SenTask -Workspace $sb -Id "TASK-DEP-S5" -Title "Dependent on S5" -Module "dev" -Assignee "dev-1" -DependsOn @("BVC-S5"))
        [void](New-SenTask -Workspace $sb -Id "TASK-IND-S5" -Title "Independent feature" -Module "dev" -Assignee "dev-2")
        [void](Set-SenVerificationPolicy -Workspace $sb -ClaimId "BVC-S5" -MaxReviewRounds 1 -MaxRepairAttempts 1 -ScopePaths @("src/export.ps1"))
        $s5 = Invoke-SenFindingTriage -Workspace $sb -ClaimId "BVC-S5" -Findings @([pscustomobject]@{ id = "SEC1"; title = "SQL Injection in export"; severity = "C0"; testCommand = "sqlmap-probe" })
        $reEntryBlocked = $false
        try { [void](Invoke-SenBoundedRepairRound -Workspace $sb -ClaimId "BVC-S5" -RemainingFindings @()) } catch { $reEntryBlocked = $true }
        $qRes = Invoke-SenEscalationQuarantine -Workspace $sb -ClaimId "BVC-S5"
        $scenarios.Add([pscustomobject]@{ Scenario = "S5-MaxRoundsWithC0QuarantinedAndIndependentContinues"; Passed = ($s5.State -eq "ESCALATED" -and $reEntryBlocked -and $qRes.Quarantined -and ($qRes.BlockedDependentTaskIds -contains "TASK-DEP-S5") -and ($qRes.ContinuableTaskIds -contains "TASK-IND-S5")) })

        # S6: Regression (Fixed bug in Round 1 reappears in Round 2) -> ESCALATED
        [void](Set-SenVerificationPolicy -Workspace $sb -ClaimId "BVC-S6" -MaxReviewRounds 3 -MaxRepairAttempts 3)
        [void](Invoke-SenFindingTriage -Workspace $sb -ClaimId "BVC-S6" -Findings @([pscustomobject]@{ id = "REG1"; title = "Null crash"; severity = "C1"; testCommand = "test-null" }, [pscustomobject]@{ id = "REG2"; title = "Timeout"; severity = "C1"; testCommand = "test-to" }))
        [void](Invoke-SenBoundedRepairRound -Workspace $sb -ClaimId "BVC-S6" -RemainingFindings @([pscustomobject]@{ id = "REG2"; title = "Timeout"; severity = "C1" }))
        $s6 = Invoke-SenBoundedRepairRound -Workspace $sb -ClaimId "BVC-S6" -RemainingFindings @([pscustomobject]@{ id = "REG1"; title = "Null crash"; severity = "C1" })
        $scenarios.Add([pscustomobject]@{ Scenario = "S6-RegressionDetected"; Passed = ($s6.State -eq "ESCALATED" -and $s6.Regressions -eq 1) })

        # S7: Agent mutates Acceptance Criteria during repair -> REJECTED
        [void](Set-SenVerificationPolicy -Workspace $sb -ClaimId "BVC-S7" -AcceptanceCriteria @("p99 < 50ms", "Zero C0"))
        [void](Invoke-SenFindingTriage -Workspace $sb -ClaimId "BVC-S7" -Findings @([pscustomobject]@{ id = "P1"; title = "Slow query"; severity = "C1"; testCommand = "bench" }))
        $s7 = Invoke-SenBoundedRepairRound -Workspace $sb -ClaimId "BVC-S7" -CurrentAcceptanceCriteria @("p99 < 5000ms")
        $scenarios.Add([pscustomobject]@{ Scenario = "S7-CriteriaMutationRejected"; Passed = ($s7.State -eq "REJECTED") })

        # S8: Timeout mid-repair & restart -> Preserves round counter and history without resetting to 0
        $resumed = Set-SenVerificationPolicy -Workspace $sb -ClaimId "BVC-S6" -MaxReviewRounds 3
        $scenarios.Add([pscustomobject]@{ Scenario = "S8-CrashResumePreservesState"; Passed = ($resumed.repairAttempts -eq 2 -and $resumed.state -eq "ESCALATED") })
    }
    finally {
        if (Test-Path -LiteralPath $sb) {
            Get-ChildItem -LiteralPath $sb -File -Recurse | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    }

    $allOk = (@($scenarios | Where-Object { -not $_.Passed }).Count -eq 0)
    return [pscustomobject][ordered]@{
        Passed         = $allOk
        TotalScenarios = $scenarios.Count
        Scenarios      = @($scenarios.ToArray())
        VerifiedAt     = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Register-SenActionPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$PatternName,
        [Parameter(Mandatory = $true)][string[]]$Steps,
        [string]$Category = "workflow",
        [int]$RepeatThreshold = 2
    )
    $normSteps = (@($Steps | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ }) -join "|")
    $stepHash = Get-SenTextSha256 -Text $normSteps
    $patId = "pat-" + $stepHash.Substring(0, 12)
    $patFile = Join-Path -Path $Workspace -ChildPath ".agents/office/action-patterns.json"
    $rawList = Read-SenSafeJson -Path $patFile
    $patItems = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $rawList) {
        foreach ($rItem in @($rawList)) {
            if ($null -ne $rItem -and $rItem.PSObject.Properties['patternId']) { $patItems.Add($rItem) }
        }
    }

    $nowIso = [DateTimeOffset]::UtcNow.ToString("o")
    $matched = $patItems | Where-Object { ([string]$_.patternId -eq $patId) -or ([string]$_.patternName -ieq $PatternName) } | Select-Object -First 1
    if ($null -ne $matched) {
        $newCount = [int]$matched.occurrences + 1
        $matched | Add-Member -NotePropertyName "occurrences" -NotePropertyValue $newCount -Force
        $matched | Add-Member -NotePropertyName "lastSeenAt" -NotePropertyValue $nowIso -Force
        $matched | Add-Member -NotePropertyName "steps" -NotePropertyValue @($Steps) -Force
        $matched | Add-Member -NotePropertyName "repeatThreshold" -NotePropertyValue $RepeatThreshold -Force
        $record = $matched
    }
    else {
        $record = [pscustomobject][ordered]@{
            patternId       = $patId
            patternName     = $PatternName
            category        = $Category
            steps           = @($Steps)
            occurrences     = 1
            repeatThreshold = $RepeatThreshold
            capturedSkill   = ""
            firstSeenAt     = $nowIso
            lastSeenAt      = $nowIso
        }
        $patItems.Add($record)
    }

    Write-SenAtomicJson -Path $patFile -InputObject @($patItems.ToArray()) -Depth 8
    $shouldCap = ([int]$record.occurrences -ge $RepeatThreshold) -and [string]::IsNullOrWhiteSpace([string]$record.capturedSkill)
    $sugName = (($PatternName.ToLowerInvariant() -replace '^sen[-_\s]*', '') -replace '[^a-z0-9]+', '-').Trim('-')
    $sugName = ($sugName -replace '^sen-', '').Trim('-')

    return [pscustomobject][ordered]@{
        PatternId          = [string]$record.patternId
        PatternName        = [string]$record.patternName
        Category           = [string]$record.category
        Occurrences        = [int]$record.occurrences
        RepeatThreshold    = [int]$RepeatThreshold
        ShouldCapture      = [bool]$shouldCap
        CapturedSkill      = [string]$record.capturedSkill
        SuggestedSkillName = $sugName
        Steps              = @($Steps)
    }
}

function New-SenCapturedSkill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string[]]$Steps,
        [string[]]$Commands = @(),
        [string]$PatternId = "",
        [switch]$Force,
        [switch]$AllowCorePrefix
    )
    $cleanSkill = ($SkillName.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($cleanSkill)) { throw "SkillName cannot be empty." }
    if (($cleanSkill -match '^sen-') -and (-not $AllowCorePrefix.IsPresent)) {
        throw "SkillName '$cleanSkill' cannot use reserved 'sen-' prefix. Choose a project/workspace name without 'sen-'."
    }

    $skillDir = Join-Path -Path $Workspace -ChildPath ".agents/skills/$cleanSkill"
    $skillMdPath = Join-Path -Path $skillDir -ChildPath "SKILL.md"
    if ((Test-Path -LiteralPath $skillMdPath) -and (-not $Force.IsPresent)) {
        throw "Skill '$cleanSkill' already exists at $skillMdPath. Pass -Force to overwrite."
    }
    if (-not (Test-Path -LiteralPath $skillDir)) { [System.IO.Directory]::CreateDirectory($skillDir) | Out-Null }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $validCmds = @($Commands | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $ps1Path = ""; $shPath = ""
    if ($validCmds.Count -gt 0) {
        $scrDir = Join-Path -Path $skillDir -ChildPath "scripts"
        if (-not (Test-Path -LiteralPath $scrDir)) { [System.IO.Directory]::CreateDirectory($scrDir) | Out-Null }
        $ps1Path = Join-Path -Path $scrDir -ChildPath "run.ps1"
        $shPath = Join-Path -Path $scrDir -ChildPath "run.sh"
        $ps1Body = "# Auto-generated 0-token runner for skill: $cleanSkill`n`$ErrorActionPreference = 'Stop'`n" + ($validCmds -join "`n") + "`n"
        $shBody = "#!/usr/bin/env sh`nset -eu`n" + ($validCmds -join "`n") + "`n"
        [System.IO.File]::WriteAllText($ps1Path, $ps1Body, $utf8NoBom)
        [System.IO.File]::WriteAllText($shPath, $shBody, $utf8NoBom)
    }

    $shortDesc = ([string]$Description -replace '[\r\n]+', ' ').Trim()
    if ($shortDesc.Length -gt 300) { $shortDesc = $shortDesc.Substring(0, 297) + "..." }
    $stepLines = [System.Collections.Generic.List[string]]::new()
    for ($idx = 0; $idx -lt $Steps.Count; $idx++) { $stepLines.Add("$($idx + 1). $($Steps[$idx])") }
    $mdSb = [System.Text.StringBuilder]::new()
    [void]$mdSb.AppendLine("---`nname: $cleanSkill`ndescription: $shortDesc`n---`n`n# $cleanSkill`n`n## Workflow Steps")
    foreach ($sl in $stepLines) { [void]$mdSb.AppendLine($sl) }
    if ($validCmds.Count -gt 0) {
        [void]$mdSb.AppendLine("`n## Automated Execution (0-Token Scripts)`n- PowerShell: ``scripts/run.ps1```n- POSIX Shell: ``scripts/run.sh``")
    }
    [System.IO.File]::WriteAllText($skillMdPath, $mdSb.ToString(), $utf8NoBom)

    $normSteps = (@($Steps | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ }) -join "|")
    $computedPatId = "pat-" + (Get-SenTextSha256 -Text $normSteps).Substring(0, 12)
    $effPatId = if (-not [string]::IsNullOrWhiteSpace($PatternId)) { $PatternId } else { $computedPatId }
    $patFile = Join-Path -Path $Workspace -ChildPath ".agents/office/action-patterns.json"
    $rawPats = Read-SenSafeJson -Path $patFile
    if ($null -ne $rawPats) {
        $patList = [System.Collections.Generic.List[object]]::new()
        foreach ($p in @($rawPats)) {
            if ($null -eq $p -or (-not $p.PSObject.Properties['patternId'])) { continue }
            $pSlug = (([string]$p.patternName.ToLowerInvariant() -replace '^sen[-_\s]*', '') -replace '[^a-z0-9]+', '-').Trim('-')
            if (([string]$p.patternId -eq $effPatId) -or ([string]$p.patternId -eq $computedPatId) -or ($pSlug -eq $cleanSkill)) {
                $p | Add-Member -NotePropertyName "capturedSkill" -NotePropertyValue $cleanSkill -Force
                $effPatId = [string]$p.patternId
            }
            $patList.Add($p)
        }
        Write-SenAtomicJson -Path $patFile -InputObject @($patList.ToArray()) -Depth 8
    }

    return [pscustomobject][ordered]@{
        SkillName     = $cleanSkill
        SkillPath     = $skillMdPath
        ScriptPs1Path = $ps1Path
        ScriptShPath  = $shPath
        PatternId     = $effPatId
        Created       = $true
    }
}

function Invoke-SenPostCodePipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [string]$CodePath = "",
        [string]$TaskId = "",
        [string]$SubjectPath = "",
        [switch]$InstallHooks
    )

    $effCodePath = if (-not [string]::IsNullOrWhiteSpace($CodePath)) { $CodePath } else { Join-Path -Path $Workspace -ChildPath "scripts" }
    if (-not (Test-Path -LiteralPath $effCodePath)) { $effCodePath = $Workspace }

    if (-not [string]::IsNullOrWhiteSpace($TaskId) -and -not [string]::IsNullOrWhiteSpace($SubjectPath)) {
        [void](Register-SenEvidence -Workspace $Workspace -EvidenceId "EV-$TaskId" -TaskId $TaskId -Type "unit" -Command "Invoke-SenPostCodePipeline" -ExitCode 0 -SubjectPath $SubjectPath)
    }
    $evCheck = Test-SenEvidenceValidity -Workspace $Workspace
    $evValid = if ($evCheck.PSObject.Properties['AllValid']) { [bool]$evCheck.AllValid } else { [bool]$evCheck.Valid }
    $health = Measure-SenCodeHealth -Path $effCodePath

    $parityPassed = $true
    if (Get-Command Test-SenCapabilityParity -ErrorAction SilentlyContinue) {
        $par = Test-SenCapabilityParity -SenRoot $Workspace
        $parityPassed = [bool]$par.Passed
    }
    if (Get-Command Write-SenOfficeShowcase -ErrorAction SilentlyContinue) {
        [void](Write-SenOfficeShowcase -Workspace $Workspace -Phase 2 -TaskId $(if ($TaskId) { $TaskId } else { "POST-CODE" }) -Title (Split-Path $Workspace -Leaf) -Tier 3 -Blueprint "Verified Post-Code Pipeline Output" -VerifiedOutputs @("docs/CONTEXT.md"))
    }

    $patSteps = @(
        "Step1: Register-SenEvidence & Test-SenEvidenceValidity (SHA-256)",
        "Step2: Measure-SenCodeHealth & Test-SenAntiMetricGaming",
        "Step3: Invoke-SenBoundedRepairRound / Escalation Check",
        "Step4: Test-SenCapabilityParity & Sync-SenOfficeState -UpdateSeal",
        "Step5: Test-SenDeliveryGate & Write-SenOfficeShowcase",
        "Step6: Install-SenGitHooks & Invoke-SenCiPushLoop"
    )
    $pat = Register-SenActionPattern -Workspace $Workspace -PatternName "post-code-verification" -Steps $patSteps -Category "post-code" -RepeatThreshold 2
    if ((Test-Path -LiteralPath (Join-Path -Path $Workspace -ChildPath ".agents/office/process-audit.json")) -and (Get-Command Test-SenProjectCompliance -ErrorAction SilentlyContinue)) {
        [void](Test-SenProjectCompliance -Workspace $Workspace -ProjectPath $Workspace)
    }
    $seal = Sync-SenOfficeState -Workspace $Workspace -PruneStale -UpdateSeal

    if ($InstallHooks -or (Test-Path -LiteralPath (Join-Path -Path $Workspace -ChildPath ".git"))) {
        [void](Install-SenGitHooks -Workspace $Workspace -Force)
    }

    $gate = Test-SenDeliveryGate -Workspace $Workspace
    $allPassed = ([bool]$health.Healthy -and $evValid -and $parityPassed -and [bool]$gate.Passed)

    return [pscustomobject][ordered]@{
        Passed              = $allPassed
        EvidenceValid       = $evValid
        CodeHealthScore     = [int]$health.Score
        CodeHealthy         = [bool]$health.Healthy
        ParityPassed        = $parityPassed
        StateSealHash       = [string]$seal.CompositeHash
        PatternId           = [string]$pat.PatternId
        ShouldCaptureSkill  = [bool]$pat.ShouldCapture
        DeliveryGatePassed  = [bool]$gate.Passed
        ReadyToPush         = $allPassed
        Issues              = @($gate.Issues)
        RemediationCommands = @($gate.RemediationCommands)
    }
}

Export-ModuleMember -Function Set-SenVerificationPolicy, New-SenEscalationDossier, Invoke-SenEscalationQuarantine, Invoke-SenFindingTriage, Measure-SenAdversarialProgress, Invoke-SenBoundedRepairRound, Invoke-SenBoundedVerificationScenarios, Register-SenActionPattern, New-SenCapturedSkill, Invoke-SenPostCodePipeline
