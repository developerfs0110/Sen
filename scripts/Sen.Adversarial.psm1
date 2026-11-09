# scripts/Sen.Adversarial.psm1
# Adversarial Verification & Evidence Governance Engine (AV-01..AV-10)
# Implements 4-Role Separation (Proposer, Verifier, Adversary, Independent Judge),
# Falsification Plans, Executable Evidence Binding, Anti-Metric Gaming Locks, and Governance Negative Tests.

$ErrorActionPreference = "Stop"

function Get-SenFileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath
    )
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        return ""
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $FilePath).Path)
        $hashBytes = $sha256.ComputeHash($bytes)
        return ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-SenTextSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Text = ""
    )
    $normalized = ([string]$Text).Replace("`r`n", "`n").Trim()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hashBytes = $sha256.ComputeHash($bytes)
        return ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Read-SenJsonArray {
    param([string]$Path)
    $loaded = Read-SenSafeJson -Path $Path
    if ($null -eq $loaded) { return @() }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $loaded) {
        if ($null -eq $entry) { continue }
        if ($entry -is [System.Array]) {
            foreach ($nested in $entry) { if ($null -ne $nested) { $items.Add($nested) } }
        }
        elseif ($entry.PSObject.Properties['value'] -and $entry.PSObject.Properties['Count'] -and $entry.value -is [System.Array]) {
            foreach ($nested in $entry.value) { if ($null -ne $nested) { $items.Add($nested) } }
        }
        else {
            $items.Add($entry)
        }
    }
    return @($items.ToArray())
}

function Get-SenCodeRevisionSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [string[]]$CodePaths = @()
    )
    $gitSha = "uncommitted"
    try {
        $gitOut = & git -C $Workspace rev-parse --short=12 HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$gitOut)) {
            $gitSha = ([string]$gitOut).Trim()
        }
    }
    catch { <# Fallback when workspace is not a git repository #> }

    $fileHashes = [ordered]@{}
    foreach ($relPath in @($CodePaths)) {
        if ([string]::IsNullOrWhiteSpace($relPath)) { continue }
        $fullPath = if ([System.IO.Path]::IsPathRooted($relPath)) { $relPath } else { Join-Path -Path $Workspace -ChildPath $relPath }
        $cleanKey = $relPath.Replace('\', '/')
        $fileHashes[$cleanKey] = Get-SenFileSha256 -FilePath $fullPath
    }
    $combinedRaw = $gitSha + "|" + (($fileHashes.Keys | ForEach-Object { "$_=$($fileHashes[$_])" }) -join ";")
    return [pscustomobject][ordered]@{
        gitCommit    = $gitSha
        revisionHash = Get-SenTextSha256 -Text $combinedRaw
        fileHashes   = $fileHashes
        capturedAt   = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function New-SenFalsificationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [Parameter(Mandatory = $true)][string]$Proposer,
        [Parameter(Mandatory = $true)][string]$CoreHypothesis,
        [Parameter(Mandatory = $true)][string[]]$FailureConditions,
        [Parameter(Mandatory = $true)][string[]]$Counterexamples,
        [Parameter(Mandatory = $true)][string[]]$BoundaryConditions,
        [Parameter(Mandatory = $true)][string[]]$AlternativeSolutions,
        [Parameter(Mandatory = $true)][string]$FalsificationTest,
        [Parameter(Mandatory = $true)][string[]]$AcceptanceCriteria
    )
    $plan = [pscustomobject][ordered]@{
        planId               = "FP-$ClaimId"
        claimId              = $ClaimId
        proposer             = $Proposer
        coreHypothesis       = $CoreHypothesis
        failureConditions    = @($FailureConditions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        counterexamples      = @($Counterexamples | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        boundaryConditions   = @($BoundaryConditions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        alternativeSolutions = @($AlternativeSolutions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        falsificationTest    = $FalsificationTest
        acceptanceCriteria   = @($AcceptanceCriteria | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        criteriaHash         = Get-SenTextSha256 -Text (($AcceptanceCriteria | Sort-Object) -join "|")
        createdAt            = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $validation = Test-SenFalsificationPlan -Plan $plan
    if (-not $validation.Valid) {
        throw "AV-04 Violation: Invalid Falsification Plan for '$ClaimId': $($validation.Errors -join '; ')"
    }
    $plansFile = Join-Path -Path $Workspace -ChildPath ".agents/office/falsification-plans.json"
    $existing = [System.Collections.Generic.List[object]]::new()
    foreach ($item in (Read-SenJsonArray -Path $plansFile)) {
        if ($null -ne $item -and [string]$item.claimId -ne $ClaimId) { $existing.Add($item) }
    }
    $existing.Add($plan)
    Write-SenAtomicJson -Path $plansFile -InputObject ($existing.ToArray()) -Depth 8
    return $plan
}

function Test-SenFalsificationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $trivialPattern = '^(?i)(none|n/a|na|null|ok|pass|todo|tbd|khong co|nothing)$'
    if ([string]::IsNullOrWhiteSpace([string]$Plan.coreHypothesis) -or [string]$Plan.coreHypothesis -match $trivialPattern) {
        $errors.Add("MissingOrTrivialCoreHypothesis")
    }
    if (@($Plan.failureConditions).Count -eq 0 -or (@($Plan.failureConditions | Where-Object { $_ -match $trivialPattern }).Count -gt 0)) {
        $errors.Add("MissingFailureConditions")
    }
    if (@($Plan.counterexamples).Count -eq 0 -or (@($Plan.counterexamples | Where-Object { $_ -match $trivialPattern }).Count -gt 0)) {
        $errors.Add("MissingCounterexamples")
    }
    if (@($Plan.boundaryConditions).Count -eq 0) {
        $errors.Add("MissingBoundaryConditions")
    }
    if (@($Plan.alternativeSolutions).Count -eq 0) {
        $errors.Add("MissingAlternativeSolutions")
    }
    if ([string]::IsNullOrWhiteSpace([string]$Plan.falsificationTest) -or [string]$Plan.falsificationTest -match $trivialPattern -or ([string]$Plan.falsificationTest).Length -lt 5) {
        $errors.Add("MissingExecutableFalsificationTest")
    }
    if (@($Plan.acceptanceCriteria).Count -eq 0) {
        $errors.Add("MissingAcceptanceCriteria")
    }
    return [pscustomobject][ordered]@{
        Valid  = ($errors.Count -eq 0)
        Errors = @($errors.ToArray())
    }
}

function Register-SenClaim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [Parameter(Mandatory = $true)][string]$Claim,
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$Proposer,
        [string[]]$CodePaths = @(),
        [string[]]$Tests = @(),
        [string[]]$Assumptions = @(),
        [string[]]$Limitations = @(),
        [string]$FalsificationPlanId = ""
    )
    $rev = Get-SenCodeRevisionSnapshot -Workspace $Workspace -CodePaths $CodePaths
    $record = [pscustomobject][ordered]@{
        claim_id             = $ClaimId
        claim                = $Claim
        scope                = $Scope
        status               = "INCONCLUSIVE"
        proposer             = $Proposer
        falsification_plan   = $FalsificationPlanId
        code_paths           = @($CodePaths)
        evidence             = @()
        counterexamples      = @()
        tests                = @($Tests)
        assumptions          = @($Assumptions)
        limitations          = @($Limitations)
        reviewer             = ""
        code_revision        = $rev.revisionHash
        git_commit           = $rev.gitCommit
        file_hashes          = $rev.fileHashes
        decision             = "INCONCLUSIVE"
        audit_trail          = @(
            [ordered]@{
                step      = "CLAIM_CREATED"
                actor     = $Proposer
                status    = "INCONCLUSIVE"
                timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        )
        updated_at           = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $claimsFile = Join-Path -Path $Workspace -ChildPath ".agents/office/claims.json"
    $existing = [System.Collections.Generic.List[object]]::new()
    foreach ($item in (Read-SenJsonArray -Path $claimsFile)) {
        if ($null -ne $item -and [string]$item.claim_id -ne $ClaimId) { $existing.Add($item) }
    }
    $existing.Add($record)
    Write-SenAtomicJson -Path $claimsFile -InputObject ($existing.ToArray()) -Depth 10
    return $record
}

function Invoke-SenExecutableEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [string]$Verifier = "verifier",
        [Parameter(Mandatory = $true)][string]$Command,
        [string]$EvidenceType = "executable_test",
        [string]$ArtifactPath = "",
        [scriptblock]$CommandRunner = $null
    )
    $trivialCmd = '^(?i)\s*(none|manual|ok|pass|true|echo\s+ok|verbal|fake)\s*$'
    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -match $trivialCmd) {
        throw "AV-06 Violation: Evidence command must be a real executable verification command, not '$Command'."
    }
    if ($null -eq $CommandRunner -and $Command -match '(?i)\b(Save-SenTasks|Write-SenAtomicJson|Sync-SenOfficeState\b[^|;&]*-UpdateSeal|Lock-SenQualityBaseline\b[^|;&]*-Force|Remove-Item\b[^|;&]*\.agents|\.agents[/\\]office)') {
        throw "AV-06 Violation: Evidence command cannot mutate Sen governance state: '$Command'."
    }
    $claimsFile = Join-Path -Path $Workspace -ChildPath ".agents/office/claims.json"
    $tasksFile = Join-Path -Path $Workspace -ChildPath ".agents/office/tasks.json"
    $preClaimsRaw = if (Test-Path -LiteralPath $claimsFile) { [System.IO.File]::ReadAllText($claimsFile) } else { "" }
    $preTasksRaw = if (Test-Path -LiteralPath $tasksFile) { [System.IO.File]::ReadAllText($tasksFile) } else { "" }
    $allClaims = [System.Collections.Generic.List[object]]::new()
    foreach ($c in (Read-SenJsonArray -Path $claimsFile)) { $allClaims.Add($c) }
    $target = $allClaims | Where-Object { [string]$_.claim_id -eq $ClaimId } | Select-Object -First 1
    if ($null -eq $target) {
        throw "Claim '$ClaimId' not found. Register the claim via Register-SenClaim first."
    }

    $exitCode = 1
    $outputText = ""
    try {
        if ($null -ne $CommandRunner) {
            $runRes = & $CommandRunner $Command
            $exitCode = if ($null -ne $runRes -and $runRes.PSObject.Properties['ExitCode']) { [int]$runRes.ExitCode } else { 0 }
            $outputText = if ($null -ne $runRes -and $runRes.PSObject.Properties['Output']) { [string]$runRes.Output } else { [string]$runRes }
        }
        else {
            $global:LASTEXITCODE = 0
            $sb = [scriptblock]::Create($Command)
            $rawOut = & $sb 2>&1
            $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            $outputText = ($rawOut | ForEach-Object { [string]$_ }) -join "`n"
            $postClaimsRaw = if (Test-Path -LiteralPath $claimsFile) { [System.IO.File]::ReadAllText($claimsFile) } else { "" }
            $postTasksRaw = if (Test-Path -LiteralPath $tasksFile) { [System.IO.File]::ReadAllText($tasksFile) } else { "" }
            if ($postClaimsRaw -ne $preClaimsRaw -or $postTasksRaw -ne $preTasksRaw) {
                throw "AV-06 Violation: Evidence command covertly modified Sen governance state."
            }
        }
    }
    catch {
        if ($_.Exception.Message -match "AV-06 Violation") { throw }
        $exitCode = 1
        $outputText = $_.Exception.Message
    }

    $rev = Get-SenCodeRevisionSnapshot -Workspace $Workspace -CodePaths @($target.code_paths)
    $evRecord = [pscustomobject][ordered]@{
        evidence_id   = "EV-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
        claim_id      = $ClaimId
        verifier      = $Verifier
        type          = $EvidenceType
        command       = $Command
        exit_code     = [int]$exitCode
        passed        = ([int]$exitCode -eq 0)
        output_hash   = Get-SenTextSha256 -Text $outputText
        output_sample = if ($outputText.Length -gt 400) { $outputText.Substring(0, 400) } else { $outputText }
        artifact      = $ArtifactPath
        code_revision = $rev.revisionHash
        file_hashes   = $rev.fileHashes
        timestamp     = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $evList = [System.Collections.Generic.List[object]]::new()
    foreach ($e in @($target.evidence)) { if ($null -ne $e) { $evList.Add($e) } }
    $evList.Add($evRecord)
    $target | Add-Member -NotePropertyName "evidence" -NotePropertyValue @($evList.ToArray()) -Force
    $target | Add-Member -NotePropertyName "code_revision" -NotePropertyValue $rev.revisionHash -Force
    $target | Add-Member -NotePropertyName "file_hashes" -NotePropertyValue $rev.fileHashes -Force

    $trail = [System.Collections.Generic.List[object]]::new()
    foreach ($t in @($target.audit_trail)) { if ($null -ne $t) { $trail.Add($t) } }
    $trail.Add([ordered]@{
        step        = "EVIDENCE_EXECUTED"
        actor       = $Verifier
        evidence_id = $evRecord.evidence_id
        exit_code   = $evRecord.exit_code
        timestamp   = $evRecord.timestamp
    })
    $target | Add-Member -NotePropertyName "audit_trail" -NotePropertyValue @($trail.ToArray()) -Force
    $target | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $evRecord.timestamp -Force
    Write-SenAtomicJson -Path $claimsFile -InputObject ($allClaims.ToArray()) -Depth 10
    return $evRecord
}

function Register-SenCounterexample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [Parameter(Mandatory = $true)][string]$Adversary,
        [Parameter(Mandatory = $true)][string]$Scenario,
        [Parameter(Mandatory = $true)][string]$TestCommand,
        [Parameter(Mandatory = $true)][string]$ExpectedOutcome,
        [scriptblock]$CommandRunner = $null
    )
    if ([string]::IsNullOrWhiteSpace($Scenario) -or $Scenario.Trim().Length -lt 10) {
        throw "AV-02 Violation: Counterexample scenario must describe a concrete failure mode (>= 10 chars)."
    }
    if ([string]::IsNullOrWhiteSpace($TestCommand) -or $TestCommand -match '^(?i)\s*(none|manual|verbal|n/a|ok)\s*$') {
        throw "AV-02 Violation: Adversary must provide an executable test command, not verbal critique '$TestCommand'."
    }
    $claimsFile = Join-Path -Path $Workspace -ChildPath ".agents/office/claims.json"
    $allClaims = [System.Collections.Generic.List[object]]::new()
    foreach ($c in (Read-SenJsonArray -Path $claimsFile)) { $allClaims.Add($c) }
    $target = $allClaims | Where-Object { [string]$_.claim_id -eq $ClaimId } | Select-Object -First 1
    if ($null -eq $target) {
        throw "Claim '$ClaimId' not found."
    }
    if ([string]$target.proposer -eq $Adversary) {
        throw "AV-01/AV-02 Violation: Proposer '$Adversary' cannot act as their own Adversary for '$ClaimId'."
    }

    $exitCode = 1
    $outputText = ""
    try {
        if ($null -ne $CommandRunner) {
            $res = & $CommandRunner $TestCommand
            $exitCode = if ($null -ne $res -and $res.PSObject.Properties['ExitCode']) { [int]$res.ExitCode } else { 0 }
            $outputText = if ($null -ne $res -and $res.PSObject.Properties['Output']) { [string]$res.Output } else { [string]$res }
        }
        else {
            $sb = [scriptblock]::Create($TestCommand)
            $rawOut = & $sb 2>&1
            $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            $outputText = ($rawOut | ForEach-Object { [string]$_ }) -join "`n"
        }
    }
    catch {
        $exitCode = 1
        $outputText = $_.Exception.Message
    }

    $survived = ([int]$exitCode -eq 0)
    $ceRecord = [pscustomobject][ordered]@{
        counterexample_id = "CE-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
        claim_id          = $ClaimId
        adversary         = $Adversary
        scenario          = $Scenario
        test_command      = $TestCommand
        expected_outcome  = $ExpectedOutcome
        exit_code         = [int]$exitCode
        survived          = [bool]$survived
        refuted_claim     = (-not $survived)
        output_hash       = Get-SenTextSha256 -Text $outputText
        timestamp         = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $ceList = [System.Collections.Generic.List[object]]::new()
    foreach ($c in @($target.counterexamples)) { if ($null -ne $c) { $ceList.Add($c) } }
    $ceList.Add($ceRecord)
    $target | Add-Member -NotePropertyName "counterexamples" -NotePropertyValue @($ceList.ToArray()) -Force
    if (-not $survived) {
        $target | Add-Member -NotePropertyName "status" -NotePropertyValue "REJECTED" -Force
        $target | Add-Member -NotePropertyName "decision" -NotePropertyValue "REJECTED" -Force
    }
    $trail = [System.Collections.Generic.List[object]]::new()
    foreach ($t in @($target.audit_trail)) { if ($null -ne $t) { $trail.Add($t) } }
    $trail.Add([ordered]@{
        step              = "ADVERSARIAL_CHALLENGE"
        actor             = $Adversary
        counterexample_id = $ceRecord.counterexample_id
        survived          = $survived
        timestamp         = $ceRecord.timestamp
    })
    $target | Add-Member -NotePropertyName "audit_trail" -NotePropertyValue @($trail.ToArray()) -Force
    $target | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $ceRecord.timestamp -Force
    Write-SenAtomicJson -Path $claimsFile -InputObject ($allClaims.ToArray()) -Depth 10
    return $ceRecord
}

function Get-SenBlindReviewPackage {
    [CmdletBinding()]
    [Alias("Build-SenBlindReviewPackage")]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId
    )
    $claimsFile = Join-Path -Path $Workspace -ChildPath ".agents/office/claims.json"
    $allClaims = Read-SenJsonArray -Path $claimsFile
    $claim = $allClaims | Where-Object { [string]$_.claim_id -eq $ClaimId } | Select-Object -First 1
    if ($null -eq $claim) {
        throw "Claim '$ClaimId' not found."
    }
    $plansFile = Join-Path -Path $Workspace -ChildPath ".agents/office/falsification-plans.json"
    $plan = (Read-SenJsonArray -Path $plansFile) | Where-Object { [string]$_.claimId -eq $ClaimId } | Select-Object -First 1
    $codePaths = @($claim.code_paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $liveRev = Get-SenCodeRevisionSnapshot -Workspace $Workspace -CodePaths $codePaths
    $revisionMatches = ([string]$claim.code_revision -eq [string]$liveRev.revisionHash)

    $evItems = @($claim.evidence | Where-Object { $null -ne $_ -and $_.PSObject.Properties['evidence_id'] })
    $ceItems = @($claim.counterexamples | Where-Object { $null -ne $_ -and $_.PSObject.Properties['counterexample_id'] })
    $assumpItems = @($claim.assumptions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $limitItems = @($claim.limitations | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    return [pscustomobject][ordered]@{
        claimId                = $ClaimId
        scope                  = [string]$claim.scope
        proposerIdentity       = [string]$claim.proposer
        strippedProposerFields = @("selfVerdict", "proposerNarrative", "persuasionSummary", "subjectiveConfidence")
        falsificationPlan      = if ($null -ne $plan) {
            [ordered]@{
                failureConditions  = @($plan.failureConditions)
                boundaryConditions = @($plan.boundaryConditions)
                falsificationTest  = [string]$plan.falsificationTest
                acceptanceCriteria = @($plan.acceptanceCriteria)
                criteriaHash       = [string]$plan.criteriaHash
            }
        } else { $null }
        codePaths              = $codePaths
        recordedRevision       = [string]$claim.code_revision
        liveRevision           = [string]$liveRev.revisionHash
        evidenceFresh          = [bool]$revisionMatches
        executableEvidence     = $evItems
        counterexampleResults  = $ceItems
        declaredAssumptions    = $assumpItems
        declaredLimitations    = $limitItems
        generatedAt            = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Invoke-SenIndependentVerdict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [Parameter(Mandatory = $true)][string]$Reviewer,
        [ValidateSet("Tier1", "Tier2", "Tier3")][string]$RiskTier = "Tier2"
    )
    $pkg = Get-SenBlindReviewPackage -Workspace $Workspace -ClaimId $ClaimId
    $reasons = [System.Collections.Generic.List[string]]::new()
    $verdict = "INCONCLUSIVE"

    if ([string]::IsNullOrWhiteSpace($Reviewer) -or $Reviewer -eq $pkg.proposerIdentity) {
        $reasons.Add("AV-01: Self-approval forbidden (Proposer '$($pkg.proposerIdentity)' == Reviewer '$Reviewer')")
        $verdict = "REJECTED"
    }
    elseif (-not $pkg.evidenceFresh) {
        $reasons.Add("AV-06: Code changed after evidence capture (recorded=$($pkg.recordedRevision), live=$($pkg.liveRevision))")
        $verdict = "INCONCLUSIVE"
    }
    elseif (@($pkg.executableEvidence).Count -eq 0) {
        $reasons.Add("AV-05/AV-06: No executable evidence recorded; INCONCLUSIVE cannot be promoted to VERIFIED")
        $verdict = "INCONCLUSIVE"
    }
    else {
        $failedEv = @($pkg.executableEvidence | Where-Object { [int]$_.exit_code -ne 0 })
        $refutedCe = @($pkg.counterexampleResults | Where-Object { [bool]$_.refuted_claim -eq $true })
        if ($failedEv.Count -gt 0 -or $refutedCe.Count -gt 0) {
            $reasons.Add("AV-02/AV-06: Failed evidence ($($failedEv.Count)) or refuted by counterexample ($($refutedCe.Count))")
            $verdict = "REJECTED"
        }
        elseif (($RiskTier -eq "Tier2" -or $RiskTier -eq "Tier3") -and @($pkg.counterexampleResults).Count -eq 0) {
            $reasons.Add("AV-02: Tier2/Tier3 requires at least 1 executable adversarial counterexample test")
            $verdict = "INCONCLUSIVE"
        }
        elseif ($RiskTier -eq "Tier3" -and $null -eq $pkg.falsificationPlan) {
            $reasons.Add("AV-04: Tier3 requires a valid Falsification Plan")
            $verdict = "INCONCLUSIVE"
        }
        elseif (@($pkg.declaredLimitations).Count -gt 0) {
            $reasons.Add("AV-05: Verified within scope but has $($pkg.declaredLimitations.Count) declared limitation(s)")
            $verdict = "CONDITIONAL"
        }
        else {
            $reasons.Add("All evidence passed, counterexamples survived, and blind independent review succeeded")
            $verdict = "VERIFIED"
        }
    }

    $claimsFile = Join-Path -Path $Workspace -ChildPath ".agents/office/claims.json"
    $allClaims = [System.Collections.Generic.List[object]]::new()
    foreach ($c in (Read-SenJsonArray -Path $claimsFile)) { $allClaims.Add($c) }
    $target = $allClaims | Where-Object { [string]$_.claim_id -eq $ClaimId } | Select-Object -First 1
    if ($null -ne $target) {
        $nowIso = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $target | Add-Member -NotePropertyName "reviewer" -NotePropertyValue $Reviewer -Force
        $target | Add-Member -NotePropertyName "status" -NotePropertyValue $verdict -Force
        $target | Add-Member -NotePropertyName "decision" -NotePropertyValue $verdict -Force
        $trail = [System.Collections.Generic.List[object]]::new()
        foreach ($t in @($target.audit_trail)) { if ($null -ne $t) { $trail.Add($t) } }
        $trail.Add([ordered]@{
            step      = "INDEPENDENT_DECISION"
            actor     = $Reviewer
            verdict   = $verdict
            reasons   = @($reasons.ToArray())
            timestamp = $nowIso
        })
        $target | Add-Member -NotePropertyName "audit_trail" -NotePropertyValue @($trail.ToArray()) -Force
        $target | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $nowIso -Force
        Write-SenAtomicJson -Path $claimsFile -InputObject ($allClaims.ToArray()) -Depth 10
    }

    return [pscustomobject][ordered]@{
        ClaimId     = $ClaimId
        Proposer    = $pkg.proposerIdentity
        Reviewer    = $Reviewer
        RiskTier    = $RiskTier
        Verdict     = $verdict
        Reasons     = @($reasons.ToArray())
        BlindReview = $true
        DecidedAt   = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Lock-SenQualityBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace
    )
    $testsDir = Join-Path -Path $Workspace -ChildPath "tests"
    $perFileAssertions = [ordered]@{}
    $totalAssertions = 0
    if (Test-Path -LiteralPath $testsDir) {
        foreach ($tf in @(Get-ChildItem -LiteralPath $testsDir -Filter "*.Tests.ps1" -File | Sort-Object Name)) {
            $txt = [System.IO.File]::ReadAllText($tf.FullName, [System.Text.Encoding]::UTF8)
            $cnt = @([regex]::Matches($txt, '\bAssert-[A-Za-z]+\b')).Count
            $perFileAssertions[$tf.Name] = $cnt
            $totalAssertions += $cnt
        }
    }

    $taskCriteriaHashes = [ordered]@{}
    if (Get-Command Get-SenTasks -ErrorAction SilentlyContinue) {
        foreach ($tk in @(Get-SenTasks -Workspace $Workspace)) {
            if ($null -ne $tk -and $tk.id) {
                $critText = (@($tk.acceptanceCriteria) | Sort-Object) -join "|"
                $taskCriteriaHashes[[string]$tk.id] = Get-SenTextSha256 -Text $critText
            }
        }
    }

    $baseline = [pscustomobject][ordered]@{
        workspace          = $Workspace
        totalTestFiles     = $perFileAssertions.Keys.Count
        totalAssertions    = $totalAssertions
        perFileAssertions  = $perFileAssertions
        taskCriteriaHashes = $taskCriteriaHashes
        lockedAt           = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $basePath = Join-Path -Path $Workspace -ChildPath ".agents/office/quality-baseline.json"
    Write-SenAtomicJson -Path $basePath -InputObject $baseline -Depth 8
    return $baseline
}

function Test-SenAntiMetricGaming {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [switch]$AllowApprovedCriteriaChange,
        [string]$ApprovingReviewer = ""
    )
    $basePath = Join-Path -Path $Workspace -ChildPath ".agents/office/quality-baseline.json"
    $baseline = Read-SenSafeJson -Path $basePath
    if ($null -eq $baseline) {
        return [pscustomobject][ordered]@{ Passed = $true; Violations = @(); HasBaseline = $false }
    }
    $violations = [System.Collections.Generic.List[string]]::new()
    $testsDir = Join-Path -Path $Workspace -ChildPath "tests"

    if ($null -ne $baseline.perFileAssertions) {
        foreach ($prop in $baseline.perFileAssertions.PSObject.Properties) {
            $fileName = [string]$prop.Name
            $minCnt = [int]$prop.Value
            $filePath = Join-Path -Path $testsDir -ChildPath $fileName
            if (-not (Test-Path -LiteralPath $filePath)) {
                $violations.Add("AV-08: Test file '$fileName' was deleted (expected >= $minCnt assertions)")
            }
            else {
                $txt = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)
                $nowCnt = @([regex]::Matches($txt, '\bAssert-[A-Za-z]+\b')).Count
                if ($nowCnt -lt $minCnt) {
                    $violations.Add("AV-08: Test dilution in '$fileName' (assertions dropped from $minCnt to $nowCnt)")
                }
            }
        }
    }

    if ($null -ne $baseline.taskCriteriaHashes -and (Get-Command Get-SenTasks -ErrorAction SilentlyContinue)) {
        $tasksById = @{}
        foreach ($t in @(Get-SenTasks -Workspace $Workspace)) { if ($t -and $t.id) { $tasksById[[string]$t.id] = $t } }
        foreach ($prop in $baseline.taskCriteriaHashes.PSObject.Properties) {
            $tid = [string]$prop.Name
            if (-not $tasksById.ContainsKey($tid)) { continue }
            $tk = $tasksById[$tid]
            $nowHash = Get-SenTextSha256 -Text ((@($tk.acceptanceCriteria) | Sort-Object) -join "|")
            $approved = ($AllowApprovedCriteriaChange.IsPresent -and (-not [string]::IsNullOrWhiteSpace($ApprovingReviewer)) -and ($ApprovingReviewer -ne [string]$tk.assignee))
            if (($nowHash -ne [string]$prop.Value) -and (-not $approved)) {
                $violations.Add("AV-09: Acceptance criteria modified for task '$tid' without independent reviewer approval")
            }
        }
    }

    return [pscustomobject][ordered]@{
        Passed      = ($violations.Count -eq 0)
        Violations  = @($violations.ToArray())
        HasBaseline = $true
        CheckedAt   = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}

function Invoke-SenGovernanceNegativeTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$Workspace = $PWD.Path
    )
    $sbRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-gov-neg-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    [System.IO.Directory]::CreateDirectory((Join-Path $sbRoot "tests")) | Out-Null
    [System.IO.Directory]::CreateDirectory((Join-Path $sbRoot "src")) | Out-Null
    $results = [System.Collections.Generic.List[object]]::new()

    try {
        $codeFile = Join-Path $sbRoot "src/app.ps1"
        [System.IO.File]::WriteAllText($codeFile, "function Invoke-Demo { return 42 }`n", [System.Text.Encoding]::UTF8)
        $testFile = Join-Path $sbRoot "tests/Demo.Tests.ps1"
        [System.IO.File]::WriteAllText($testFile, "Assert-Equal 42 42`nAssert-True `$true`n", [System.Text.Encoding]::UTF8)

        # 1. AV-01 Negative Test: Self-approval must be REJECTED
        [void](Register-SenClaim -Workspace $sbRoot -ClaimId "CLAIM-NEG-01" -Claim "Self approval probe" -Scope "Tier2" -Proposer "agent-a" -CodePaths @("src/app.ps1"))
        $vSelf = Invoke-SenIndependentVerdict -Workspace $sbRoot -ClaimId "CLAIM-NEG-01" -Reviewer "agent-a" -RiskTier "Tier1"
        $results.Add([pscustomobject][ordered]@{ RuleId = "AV-01"; Enforcement = "Invoke-SenIndependentVerdict"; NegativeTest = "SelfApprovalBlocked"; Passed = ($vSelf.Verdict -eq "REJECTED"); Evidence = $vSelf.Reasons -join "; " })

        # 2. AV-02 Negative Test: Verbal counterexample without command must throw
        $av02Blocked = $false
        try { [void](Register-SenCounterexample -Workspace $sbRoot -ClaimId "CLAIM-NEG-01" -Adversary "agent-b" -Scenario "Valid scenario description" -TestCommand "verbal" -ExpectedOutcome "fail") } catch { $av02Blocked = $true }
        $results.Add([pscustomobject][ordered]@{ RuleId = "AV-02"; Enforcement = "Register-SenCounterexample"; NegativeTest = "VerbalCritiqueBlocked"; Passed = $av02Blocked; Evidence = "Blocked verbal counterexample" })

        # 3. AV-04 Negative Test: Empty falsification test must throw
        $av04Blocked = $false
        try { [void](New-SenFalsificationPlan -Workspace $sbRoot -ClaimId "CLAIM-NEG-01" -Proposer "agent-a" -CoreHypothesis "H" -FailureConditions @("none") -Counterexamples @("C") -BoundaryConditions @("B") -AlternativeSolutions @("A") -FalsificationTest "none" -AcceptanceCriteria @("AC")) } catch { $av04Blocked = $true }
        $results.Add([pscustomobject][ordered]@{ RuleId = "AV-04"; Enforcement = "New-SenFalsificationPlan"; NegativeTest = "TrivialFalsificationPlanBlocked"; Passed = $av04Blocked; Evidence = "Blocked trivial falsification plan" })

        # 4. AV-05 & AV-06 Negative Test: Code edit after evidence invalidates VERIFIED back to INCONCLUSIVE
        [void](Invoke-SenExecutableEvidence -Workspace $sbRoot -ClaimId "CLAIM-NEG-01" -Verifier "agent-v" -Command "exit 0" -CommandRunner { param($c) [pscustomobject]@{ ExitCode = 0; Output = "OK" } })
        [void](Register-SenCounterexample -Workspace $sbRoot -ClaimId "CLAIM-NEG-01" -Adversary "agent-b" -Scenario "Boundary zero input check" -TestCommand "exit 0" -ExpectedOutcome "Survives zero" -CommandRunner { param($c) [pscustomobject]@{ ExitCode = 0; Output = "OK" } })
        $vPass = Invoke-SenIndependentVerdict -Workspace $sbRoot -ClaimId "CLAIM-NEG-01" -Reviewer "agent-judge" -RiskTier "Tier2"
        [System.IO.File]::WriteAllText($codeFile, "function Invoke-Demo { return 99 }`n", [System.Text.Encoding]::UTF8)
        $vStale = Invoke-SenIndependentVerdict -Workspace $sbRoot -ClaimId "CLAIM-NEG-01" -Reviewer "agent-judge" -RiskTier "Tier2"
        $results.Add([pscustomobject][ordered]@{ RuleId = "AV-05/AV-06"; Enforcement = "Get-SenBlindReviewPackage"; NegativeTest = "CodeTamperInvalidatesEvidence"; Passed = ($vPass.Verdict -eq "VERIFIED" -and $vStale.Verdict -eq "INCONCLUSIVE"); Evidence = "Pre=$($vPass.Verdict)->Post=$($vStale.Verdict)" })

        # 5. AV-08 & AV-09 Negative Test: Test dilution and criteria lowering blocked
        [void](New-SenTask -Workspace $sbRoot -Id "TASK-NEG-1" -Title "Neg test" -Module "dev" -Assignee "agent-a" -AcceptanceCriteria @("Must pass 100%"))
        [void](Lock-SenQualityBaseline -Workspace $sbRoot)
        [System.IO.File]::WriteAllText($testFile, "Assert-Equal 42 42`n", [System.Text.Encoding]::UTF8)
        $tasks = @(Get-SenTasks -Workspace $sbRoot); $tasks[0].acceptanceCriteria = @("Lowered standard"); [void](Save-SenTasks -Workspace $sbRoot -Tasks $tasks)
        $amg = Test-SenAntiMetricGaming -Workspace $sbRoot
        $results.Add([pscustomobject][ordered]@{ RuleId = "AV-08/AV-09"; Enforcement = "Test-SenAntiMetricGaming"; NegativeTest = "TestDilutionAndCriteriaTamperBlocked"; Passed = (-not $amg.Passed -and $amg.Violations.Count -ge 2); Evidence = ($amg.Violations -join " | ") })
    }
    finally {
        if (Test-Path -LiteralPath $sbRoot) { Remove-Item -LiteralPath $sbRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $allPassed = (@($results | Where-Object { -not $_.Passed }).Count -eq 0)
    $audit = [pscustomobject][ordered]@{
        Passed      = $allPassed
        TotalChecks = $results.Count
        Results     = @($results.ToArray())
        AuditedAt   = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    if (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office")) {
        Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/governance-audit.json") -InputObject $audit -Depth 8
    }
    return $audit
}

function Invoke-SenDialecticalAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [string]$ProjectPath = "",
        [switch]$RequireIndependentReviewer,
        [scriptblock]$IndependentProbe = $null
    )
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath } else { $Workspace }
    $specsDir = Join-Path -Path $Workspace -ChildPath "docs/superpowers/specs"
    $hasDialecticalSpec = $false
    if (Test-Path -LiteralPath $specsDir) {
        $specFiles = @(Get-ChildItem -LiteralPath $specsDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 })
        foreach ($specFile in $specFiles) {
            $specText = [System.IO.File]::ReadAllText($specFile.FullName, [System.Text.Encoding]::UTF8)
            $hasThesis = ($specText -match '(?i)(Best-of-the-Best|Resource Cost|T.i nguy.n)')
            $hasAntithesis = ($specText -match '(?i)(Critique|Ph.n bi.n|Counterexample|Falsif|Adversarial)')
            if ($hasThesis -and $hasAntithesis) { $hasDialecticalSpec = $true }
        }
    }

    $codeHealth = Measure-SenCodeHealth -Path $targetDir
    $vnLaw = Invoke-SenVnLawScan -Path $targetDir
    $evidenceValidity = if (Get-Command Test-SenEvidenceValidity -ErrorAction SilentlyContinue) {
        Test-SenEvidenceValidity -Workspace $Workspace
    } else {
        [pscustomobject]@{ AllValid = $false; StaleCount = 1 }
    }
    $hungCheck = if (Get-Command Test-SenHungTasks -ErrorAction SilentlyContinue) {
        Test-SenHungTasks -Workspace $Workspace
    } else {
        [pscustomobject]@{ Healthy = $false; StaleTaskIds = @("MISSING_HUNG_CHECK"); HungProcessIds = @() }
    }
    $antiGaming = Test-SenAntiMetricGaming -Workspace $Workspace

    $activeTasks = @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" })
    $invalidEvidenceTasks = @($activeTasks | Where-Object {
        $isDone = ([string]$_.status -eq "done")
        $cmdText = if ($_.evidence) { [string]$_.evidence.command } else { "" }
        $exitVal = if ($_.evidence -and $null -ne $_.evidence.exitCode) { [int]$_.evidence.exitCode } else { -1 }
        $isFakeCmd = ($cmdText -notmatch '[A-Za-z0-9]{3,}') -or ($cmdText -match '(?i)^(manual|none|ok|pass|fake|verbal|subagent-verified|verified-in-session|session-verified|hook-telemetry|subagent-report|subagent-closed)$')
        $isPlaceholderCmd = ($RequireIndependentReviewer.IsPresent -and ($cmdText -match '(?i)^(todo-verified|subagent-verified)$'))
        ((-not $isDone) -and $RequireIndependentReviewer.IsPresent) -or ($isDone -and ($null -eq $_.evidence -or $exitVal -ne 0 -or $isFakeCmd -or $isPlaceholderCmd))
    })

    $selfReviewedTasks = @($activeTasks | Where-Object {
        $isDone = ([string]$_.status -eq "done")
        $assignee = [string]$_.assignee
        $reviewer = if ($_.evidence) { [string]$_.evidence.reviewer } else { "" }
        $sameActor = ($assignee -and $reviewer -and ($assignee -eq $reviewer) -and ($assignee -ne "pm" -or $RequireIndependentReviewer.IsPresent))
        ((-not $isDone) -and $RequireIndependentReviewer.IsPresent) -or ($isDone -and $sameActor)
    })

    $probePassed = if ($null -ne $IndependentProbe) { [bool](& $IndependentProbe) } else { $true }
    $v1Passed = [bool]($hasDialecticalSpec -or -not (Test-Path -LiteralPath $specsDir))
    $v2Passed = [bool]($codeHealth.Healthy -and $antiGaming.Passed)
    $v3Passed = ($invalidEvidenceTasks.Count -eq 0) -and [bool]$evidenceValidity.AllValid -and $probePassed
    $v4Passed = [bool]$vnLaw.CompliantCodeLevel -and ($vnLaw.Verdict -in @("PASS", "NOT_APPLICABLE"))
    $v5Passed = [bool]$hungCheck.Healthy
    $v6Passed = ($selfReviewedTasks.Count -eq 0) -and $probePassed

    $vectors = @(
        [pscustomobject]@{ Id = "V1-DIALECTICAL-SPEC"; Passed = $v1Passed; Detail = "Proposer:SpecAndFalsification" },
        [pscustomobject]@{ Id = "V2-BOUNDARY-HEALTH"; Passed = $v2Passed; Detail = "Quantitative:Score=$($codeHealth.Score);AntiGaming=$($antiGaming.Passed)" },
        [pscustomobject]@{ Id = "V3-SOCRATIC-EVIDENCE"; Passed = $v3Passed; Detail = "Verifier:Invalid=$($invalidEvidenceTasks.Count);Stale=$($evidenceValidity.StaleCount)" },
        [pscustomobject]@{ Id = "V4-LEGAL-PARTITION"; Passed = $v4Passed; Detail = "Legal:RedFlags=$($vnLaw.CodeRedFlags.Count)" },
        [pscustomobject]@{ Id = "V5-RUNTIME-LIVENESS"; Passed = $v5Passed; Detail = "Adversary:Hung=$($hungCheck.StaleTaskIds.Count + $hungCheck.HungProcessIds.Count)" },
        [pscustomobject]@{ Id = "V6-INDEPENDENT-REVIEW"; Passed = $v6Passed; Detail = "IndependentJudge:SelfReview=$($selfReviewedTasks.Count)" }
    )
    $passedCount = @($vectors | Where-Object { $_.Passed }).Count
    $allPassed = ($passedCount -eq $vectors.Count)
    $verdict4State = if ($allPassed) { "VERIFIED" } elseif (-not $v6Passed -or -not $v3Passed -or -not $antiGaming.Passed) { "REJECTED" } else { "INCONCLUSIVE" }

    $independentReview = [pscustomobject][ordered]@{
        AgentA_Proposer     = [bool]$v1Passed
        AgentB_FaultFinder  = [bool]($v5Passed -and $v3Passed)
        AgentC_Quantitative = [bool]($v2Passed -and $v4Passed)
        AgentD_Decision     = $(if ($allPassed) { "APPROVED" } else { "REJECTED" })
        Verdict             = $verdict4State
    }
    $result = [pscustomobject][ordered]@{
        Workspace         = $Workspace
        Passed            = $allPassed
        Verdict           = $verdict4State
        Score             = [int][Math]::Round(($passedCount * 100.0) / $vectors.Count)
        Vectors           = $vectors
        IndependentReview = $independentReview
        AntiMetricGaming  = $antiGaming
        verifiedAt        = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    if (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office")) {
        Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/dialectical-audit.json") -InputObject $result -Depth 8
    }
    return $result
}

$senBoundedLoopPath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.BoundedLoop.psm1"
if (Test-Path -LiteralPath $senBoundedLoopPath) {
    Import-Module -Name $senBoundedLoopPath -Global -Force
}

Export-ModuleMember -Function Get-SenFileSha256, Get-SenTextSha256, Get-SenCodeRevisionSnapshot, New-SenFalsificationPlan, Test-SenFalsificationPlan, Register-SenClaim, Invoke-SenExecutableEvidence, Register-SenCounterexample, Get-SenBlindReviewPackage, Invoke-SenIndependentVerdict, Lock-SenQualityBaseline, Test-SenAntiMetricGaming, Invoke-SenGovernanceNegativeTest, Invoke-SenDialecticalAudit
