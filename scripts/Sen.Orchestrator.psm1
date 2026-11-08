# scripts/Sen.Orchestrator.psm1
# Pure ASCII PowerShell module for Sen Orchestrator, Task DAG, File Lock,
# Backlog, Restore Points, 3-Layer Memory, and Code Health Audit (v0.3.0+).

$ErrorActionPreference = "Stop"

function Save-SenTasks {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][Alias("WorkspacePath", "Path")][string]$Workspace, [AllowEmptyCollection()][Parameter(Mandatory = $true)][object[]]$Tasks, [switch]$Internal)
  $tasksPath = Join-Path -Path $Workspace -ChildPath ".agents/office/tasks.json"
  $mtxName = "Local\SenTasksMutex_" + [Math]::Abs($tasksPath.ToLowerInvariant().GetHashCode())
  $mtx = [System.Threading.Mutex]::new($false, $mtxName)
  $hasLock = $false
  try {
    try { $hasLock = $mtx.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $hasLock = $true }
    $finalList = [System.Collections.Generic.List[object]]::new()
    $diskObj = if (-not $Internal -and (Test-Path -LiteralPath $tasksPath)) { Read-SenSafeJson -Path $tasksPath } else { $null }
    $diskArr = if ($null -ne $diskObj -and $diskObj.PSObject.Properties.Name -contains "tasks") { @($diskObj.tasks) } else { @() }
    $diskMap = @{}; $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dt in $diskArr) { if ($dt -and $dt.id) { $diskMap[[string]$dt.id] = $dt } }
    foreach ($t in $Tasks) {
      if (-not $t) { continue }
      $tid = [string]$t.id; [void]$seenIds.Add($tid)
      $tRev = if ($t.PSObject.Properties.Name -contains "_rev") { [int]$t._rev } else { 1 }
      $dt = if ($diskMap.ContainsKey($tid)) { $diskMap[$tid] } else { $null }
      $dRev = if ($null -ne $dt -and $dt.PSObject.Properties.Name -contains "_rev") { [int]$dt._rev } else { 0 }
      if ($null -ne $dt -and $dRev -gt $tRev) { $finalList.Add($dt); continue }
      $newRev = if ($null -ne $dt -and [string]$t.status -ne [string]$dt.status) { $dRev + 1 } else { $tRev }
      $t | Add-Member -NotePropertyName "_rev" -NotePropertyValue $newRev -Force
      $finalList.Add($t)
    }
    foreach ($dk in $diskMap.Keys) { if (-not $seenIds.Contains($dk)) { $finalList.Add($diskMap[$dk]) } }
    $payload = [ordered]@{ version = 1; updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); tasks = @($finalList.ToArray()) }
    Write-SenAtomicJson -Path $tasksPath -InputObject $payload -Depth 8
    return @($finalList.ToArray())
  }
  finally {
    if ($hasLock) { try { $mtx.ReleaseMutex() } catch { <# Ignore mutex release error #> } }
    $mtx.Dispose()
  }
}

function Get-SenTasks {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
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
      if ($allDone) {
        $t.status = "ready"
        $curRev = if ($t.PSObject.Properties.Name -contains "_rev") { [int]$t._rev } else { 1 }
        $t | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
        $changed = $true
      }
    }
  }
  if ($changed) {
    [void](Save-SenTasks -Workspace $Workspace -Tasks $list -Internal)
  }
  return @($list)
}

function Clear-SenTasks {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
  $tasksPath = Join-Path -Path $Workspace -ChildPath ".agents/office/tasks.json"
  if (Test-Path -LiteralPath $tasksPath) { Remove-Item -LiteralPath $tasksPath -Force -ErrorAction SilentlyContinue }
}

function New-SenTask {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
    [Parameter(Mandatory = $false)][string]$Id = "",
    [Parameter(Mandatory = $true)][string]$Title,
    [int]$Tier = 2, [string]$RiskLevel = "medium", [string]$Module = "Core", [string]$Assignee = "dev_be",
    [string[]]$DependsOn = @(), [Alias("Files")][string[]]$AllowedPaths = @(),
    [string[]]$ForbiddenActions = @("delete_database", "force_push"),
    [bool]$ApprovalRequired = $false, [string[]]$AcceptanceCriteria = @(),
    [ValidateSet("auto", "backlog", "pending", "ready", "todo", "in_progress", "reviewing", "done", "blocked", "failed")]
    [string]$Status = "auto"
  )
  if ([string]::IsNullOrWhiteSpace($Id)) { $Id = "TASK-" + [DateTime]::UtcNow.ToString("HHmmss") }
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
    id = $Id; title = $Title; tier = $Tier; riskLevel = $RiskLevel; module = $Module; assignee = $Assignee
    dependsOn = $cleanDeps; allowedPaths = $cleanPaths; forbiddenActions = $cleanForbidden
    approvalRequired = $ApprovalRequired; acceptanceCriteria = $cleanCriteria; status = $resolvedStatus; reworkCount = 0
    evidence = [pscustomobject][ordered]@{ command = ""; exitCode = $null; reviewer = ""; verifiedAt = $null; notes = "" }
    createdAt = $now; updatedAt = $now; _rev = 1
  }
  $tasks.Add($newTask)
  [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks.ToArray() -Internal)
  return $newTask
}

function Get-SenReadyTasks {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
  $tasks = @(Get-SenTasks -Workspace $Workspace)
  $activeTasks = @($tasks | Where-Object { [string]$_.status -eq "in_progress" })
  $results = [System.Collections.Generic.List[object]]::new()
  foreach ($t in $tasks) {
    if ([string]$t.status -notin @("ready", "todo")) { continue }
    $conflictId = $null
    foreach ($act in $activeTasks) {
      if ([string]$act.id -eq [string]$t.id) { continue }
      if (Test-SenPathOverlap -PathsA @($t.allowedPaths) -PathsB @($act.allowedPaths)) { $conflictId = [string]$act.id; break }
    }
    $results.Add([pscustomobject]@{ Task = $t; Id = [string]$t.id; IsReady = ($null -eq $conflictId); FileConflictWith = $conflictId })
  }
  return @($results.ToArray())
}

function Start-SenTask {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
    [Parameter(Mandatory = $true)][string]$Id, [Alias("Actor")][string]$Assignee = "", [Alias("Notes")][string]$Note = ""
  )
  $tasks = @(Get-SenTasks -Workspace $Workspace)
  $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
  if ($null -eq $target) { return [pscustomobject]@{ Started = $false; Status = "not_found"; ConflictTaskId = $null; Reason = "Task '$Id' not found" } }
  $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($t in $tasks) { if ([string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) } }
  $missingDeps = [System.Collections.Generic.List[string]]::new()
  foreach ($d in @($target.dependsOn)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$d) -and -not $doneIds.Contains([string]$d)) { $missingDeps.Add([string]$d) }
  }
  if ($missingDeps.Count -gt 0) {
    return [pscustomobject]@{ Started = $false; Status = "blocked_dependency"; ConflictTaskId = $null; Reason = "Task '$Id' is waiting on dependencies: $($missingDeps -join ', ')" }
  }
  foreach ($t in $tasks) {
    if ([string]$t.id -eq $Id -or [string]$t.status -ne "in_progress") { continue }
    if (Test-SenPathOverlap -PathsA @($target.allowedPaths) -PathsB @($t.allowedPaths)) {
      return [pscustomobject]@{ Started = $false; Status = "blocked_file_lock"; ConflictTaskId = [string]$t.id; Reason = "File lock conflict: '$Id' shares allowedPaths with active task '$($t.id)' ($($t.assignee))" }
    }
  }
  $target.status = "in_progress"
  if (-not [string]::IsNullOrWhiteSpace($Assignee)) { $target.assignee = $Assignee }
  $curRev = if ($target.PSObject.Properties.Name -contains "_rev") { [int]$target._rev } else { 1 }
  $target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
  $target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
  return [pscustomobject]@{ Started = $true; Status = "in_progress"; ConflictTaskId = $null; Task = $target; Reason = $null }
}

function Unlock-SenTask {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Workspace,
    [Parameter(Mandatory = $true)]
    [string]$Id
  )
  $tasks = @(Get-SenTasks -Workspace $Workspace)
  $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
  if ($null -eq $target) {
    return [pscustomobject]@{ Unlocked = $false; Status = "not_found"; Reason = "Task '$Id' not found" }
  }
  $target.status = "ready"
  $curRev = if ($target.PSObject.Properties.Name -contains "_rev") { [int]$target._rev } else { 1 }
  $target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
  $target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
  return [pscustomobject]@{ Unlocked = $true; Status = "ready"; Task = $target }
}

function Submit-SenTaskForReview {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
    [Parameter(Mandatory = $true)][string]$Id,
    [Alias("Note")][string]$Notes = "",
    [string]$Actor = ""
  )
  $tasks = @(Get-SenTasks -Workspace $Workspace)
  $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
  if ($null -eq $target) { return [pscustomobject]@{ Submitted = $false; Reason = "Task '$Id' not found" } }
  $target.status = "reviewing"
  if (-not [string]::IsNullOrWhiteSpace($Notes) -and $target.evidence) { $target.evidence.notes = $Notes }
  $curRev = if ($target.PSObject.Properties.Name -contains "_rev") { [int]$target._rev } else { 1 }
  $target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
  $target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
  return [pscustomobject]@{ Submitted = $true; Status = "reviewing"; Task = $target }
}

function Complete-SenTaskReview {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $false)][bool]$Passed = $true,
    [string]$Reviewer = "tester",
    [string]$EvidenceCommand = "",
    [int]$ExitCode = 0,
    [Alias("Note")][string]$Notes = "",
    [string]$Verdict = ""
  )
  if ($Verdict -match '(?i)^(REJECT|FAIL)') { $Passed = $false }
  elseif ($Verdict -match '(?i)^(APPROV|PASS)' -and [string]::IsNullOrWhiteSpace($EvidenceCommand)) { $EvidenceCommand = "verified-in-session" }
  $tasks = @(Get-SenTasks -Workspace $Workspace)
  $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
  if ($null -eq $target) { return [pscustomobject]@{ Completed = $false; Status = "not_found"; Reason = "Task '$Id' not found" } }
  $validRoles = @("reviewer", "tester", "qa", "sec", "security", "owner-judge", "judge", "pm", "arch", "lead", "techlead", "tech_lead")
  if ($validRoles -notcontains $Reviewer.Trim().ToLowerInvariant()) {
    return [pscustomobject]@{ Completed = $false; Status = [string]$target.status; Reason = "Unrecognized or unauthenticated Reviewer role '$Reviewer'." }
  }

  $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  $curRev = if ($target.PSObject.Properties.Name -contains "_rev") { [int]$target._rev } else { 1 }
  if ($Passed) {
    if ([string]::IsNullOrWhiteSpace($EvidenceCommand) -or $EvidenceCommand -notmatch '[A-Za-z0-9]{3,}' -or $ExitCode -ne 0) {
      return [pscustomobject]@{
        Completed = $false
        Status    = [string]$target.status
        Reason    = "Integration & Testing gate requires a valid executable EvidenceCommand and ExitCode = 0 to mark '$Id' done."
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
    $target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
    $target.updatedAt = $now
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
    [void](Get-SenTasks -Workspace $Workspace)
    if (Get-Command Sync-SenTasksToMarkdown -ErrorAction SilentlyContinue) {
      [void](Sync-SenTasksToMarkdown -Workspace $Workspace)
    }
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
    $target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
    $target.updatedAt = $now
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
    return [pscustomobject]@{
      Completed   = $false
      Status      = "in_progress"
      ReworkCount = [int]$target.reworkCount
      Task        = $target
      Reason      = "Review failed; returned to in_progress for rework (#$($target.reworkCount))."
    }
  }
}

function Test-SenHungTasks {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [int]$StaleMinutes = 15, [int]$TimeoutSeconds = 0, [string]$LogContent = "")
  $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-1 * [Math]::Max(1, $StaleMinutes))
  $maxSec = if ($TimeoutSeconds -gt 0) { $TimeoutSeconds } else { [Math]::Max(1, $StaleMinutes) * 60 }
  $staleTasks = [System.Collections.Generic.List[string]]::new(); $activeLongRunning = [System.Collections.Generic.List[string]]::new()
  $staleSubs = [System.Collections.Generic.List[string]]::new(); $idleSubs = [System.Collections.Generic.List[string]]::new()
  $deadlocked = [System.Collections.Generic.List[string]]::new()
  $probeLog = Join-Path -Path $Workspace -ChildPath ".agents/office/hung-probes.log"
  $rawLog = $LogContent + "`n" + $(if (Test-Path -LiteralPath $probeLog) { [System.IO.File]::ReadAllText($probeLog) } else { "" })
  foreach ($m in [regex]::Matches($rawLog, '(?i)(Supply values for the following parameters:|\[Y/n\]|Press any key to continue|Overwrite\s*\?)')) { $deadlocked.Add($m.Value.Trim()) }
  $hungPids = [System.Collections.Generic.List[int]]::new()
  try {
    $winProcs = if ($env:OS -eq 'Windows_NT' -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue) } else { @() }
    foreach ($wp in $winProcs) {
      if (-not $wp -or [int]$wp.ProcessId -eq $PID -or [string]$wp.CommandLine -notmatch '(?i)-Command\s+"try\s*\{\s*\$OutputEncoding|Sen\.psm1|Invoke-SenCiPushLoop') { continue }
      $proc = Get-Process -Id ([int]$wp.ProcessId) -ErrorAction SilentlyContinue
      if ($null -ne $proc -and $proc.StartTime.ToUniversalTime() -lt $cutoff) { $hungPids.Add([int]$wp.ProcessId); $deadlocked.Add("OSHungProcess:PID=$($wp.ProcessId)") }
    }
    $psLines = if ($env:OS -ne 'Windows_NT' -and (Get-Command ps -ErrorAction SilentlyContinue)) { @(& ps -eo pid,etimes,args 2>$null) } else { @() }
    foreach ($line in $psLines) {
      if ($line -match '^\s*(\d+)\s+(\d+)\s+(.+)$' -and [int]$matches[1] -ne $PID -and [int]$matches[2] -gt $maxSec -and $matches[3] -match 'Sen\.psm1|Invoke-SenCiPushLoop') {
        $hungPids.Add([int]$matches[1]); $deadlocked.Add("OSHungProcess:PID=$($matches[1])")
      }
    }
  } catch { <# Ignore OS process probe errors #> }
  $subFile = Join-Path -Path $Workspace -ChildPath ".agents/office/subagents.json"
  $subObj = if (Test-Path -LiteralPath $subFile) { Read-SenSafeJson -Path $subFile } else { $null }
  $subList = if ($null -eq $subObj) { @() } elseif ($subObj.PSObject.Properties.Name -contains "subagents") { @($subObj.subagents) } else { @($subObj) }
  foreach ($t in @(Get-SenTasks -Workspace $Workspace)) {
    if (-not $t -or [string]$t.status -ne "in_progress") { continue }
    $rawTs = if ($t.PSObject.Properties['updatedAt'] -and $t.updatedAt) { [string]$t.updatedAt } elseif ($t.PSObject.Properties['createdAt'] -and $t.createdAt) { [string]$t.createdAt } else { "" }
    $parsed = [DateTime]::MinValue
    $isOld = [string]::IsNullOrWhiteSpace($rawTs) -or (-not [DateTime]::TryParse($rawTs, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) -or ($parsed -lt $cutoff)
    if (-not $isOld) { continue }
    $hbRaw = if ($t.PSObject.Properties['heartbeatAt'] -and $t.heartbeatAt) { [string]$t.heartbeatAt } else { "" }
    $hbDt = [DateTime]::MinValue
    $hasHb = (-not [string]::IsNullOrWhiteSpace($hbRaw)) -and [DateTime]::TryParse($hbRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$hbDt) -and ($hbDt -ge $cutoff)
    $hasFileMod = $false
    foreach ($ap in @($t.allowedPaths)) {
      $apFull = if ([string]::IsNullOrWhiteSpace([string]$ap)) { "" } else { Join-Path -Path $Workspace -ChildPath ([string]$ap) }
      if ($apFull -and (Test-Path -LiteralPath $apFull) -and @(@(Get-ChildItem -LiteralPath $apFull -File -Recurse -ErrorAction SilentlyContinue) | Where-Object { $_.LastWriteTimeUtc -ge $cutoff }).Count -gt 0) { $hasFileMod = $true; break }
    }
    $hasSubProg = $false
    foreach ($s in $subList) {
      $sState = if ($s.PSObject.Properties['state'] -and $s.state) { [string]$s.state } else { [string]$s.status }
      $sStepRaw = if ($s.PSObject.Properties['lastStepTime'] -and $s.lastStepTime) { [string]$s.lastStepTime } elseif ($s.PSObject.Properties['heartbeatAt'] -and $s.heartbeatAt) { [string]$s.heartbeatAt } else { "" }
      $sStepDt = [DateTime]::MinValue
      $sMatch = ($s.PSObject.Properties['taskId'] -and [string]$s.taskId -eq [string]$t.id) -or ($s.PSObject.Properties['role'] -and [string]$s.role -eq [string]$t.assignee)
      if ($sState -eq "running" -and $sMatch -and (-not [string]::IsNullOrWhiteSpace($sStepRaw)) -and [DateTime]::TryParse($sStepRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$sStepDt) -and ($sStepDt -ge $cutoff)) { $hasSubProg = $true; break }
    }
    if ($hasHb -or $hasFileMod -or $hasSubProg) { $activeLongRunning.Add([string]$t.id) } else { $staleTasks.Add([string]$t.id) }
  }
  foreach ($s in $subList) {
    if (-not $s) { continue }
    $sid = if ($s.PSObject.Properties['id'] -and $s.id) { [string]$s.id } elseif ($s.PSObject.Properties['conversationId']) { [string]$s.conversationId } else { "unknown-subagent" }
    $sState = if ($s.PSObject.Properties['state'] -and $s.state) { [string]$s.state } else { [string]$s.status }
    if ($sState -in @("idle", "completed")) { $idleSubs.Add($sid); continue }
    if ($sState -notin @("running", "active", "in_progress")) { continue }
    $sTs = if ($s.PSObject.Properties['lastStepTime'] -and $s.lastStepTime) { [string]$s.lastStepTime } elseif ($s.PSObject.Properties['heartbeatAt'] -and $s.heartbeatAt) { [string]$s.heartbeatAt } elseif ($s.PSObject.Properties['updatedAt'] -and $s.updatedAt) { [string]$s.updatedAt } elseif ($s.PSObject.Properties['startedAt'] -and $s.startedAt) { [string]$s.startedAt } else { "" }
    $sParsed = [DateTime]::MinValue
    $sOld = [string]::IsNullOrWhiteSpace($sTs) -or (-not [DateTime]::TryParse($sTs, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$sParsed)) -or ($sParsed -lt $cutoff)
    $ownsActive = ($s.PSObject.Properties['taskId'] -and ($activeLongRunning -contains [string]$s.taskId))
    if ($sOld -and (-not $ownsActive)) { $staleSubs.Add($sid) }
  }
  return [pscustomobject][ordered]@{
    Healthy = ($staleTasks.Count -eq 0 -and $staleSubs.Count -eq 0 -and $deadlocked.Count -eq 0); StaleMinutes = $StaleMinutes
    StaleTaskIds = @($staleTasks.ToArray()); StaleSubagents = @($staleSubs.ToArray()); ActiveLongRunningIds = @($activeLongRunning.ToArray())
    IdleSubagents = @($idleSubs.ToArray()); DeadlockedItems = @($deadlocked.ToArray()); HungProcessIds = @($hungPids.ToArray()); CheckedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  }
}

function Clear-SenHungTasks {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [int]$StaleMinutes = 15, [ValidateSet("reset_to_todo", "mark_blocked", "ready", "blocked")][string]$Resolution = "reset_to_todo", [string]$LogContent = "")
  $check = Test-SenHungTasks -Workspace $Workspace -StaleMinutes $StaleMinutes -LogContent $LogContent
  $killedPids = [System.Collections.Generic.List[int]]::new()
  foreach ($hp in @($check.HungProcessIds)) {
    if ($hp -and [int]$hp -ne $PID) { Stop-Process -Id ([int]$hp) -Force -ErrorAction SilentlyContinue; $killedPids.Add([int]$hp) }
  }
  $newStatus = if ($Resolution -in @("mark_blocked", "blocked")) { "blocked" } elseif ($Resolution -eq "ready") { "ready" } else { "todo" }
  $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  $clearedTasks = [System.Collections.Generic.List[string]]::new()
  $protectedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($check.ActiveLongRunningIds), [System.StringComparer]::OrdinalIgnoreCase)
  if ($check.StaleTaskIds.Count -gt 0) {
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $staleSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($check.StaleTaskIds), [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $tasks) {
      if ($t -and $staleSet.Contains([string]$t.id) -and (-not $protectedSet.Contains([string]$t.id))) {
        $t.status = $newStatus; $t.updatedAt = $now
        $noteMsg = "Cleared hung task (> ${StaleMinutes}m) -> $newStatus"
        if ($t.evidence) { $t.evidence.notes = $noteMsg }
        $t | Add-Member -NotePropertyName "notes" -NotePropertyValue $noteMsg -Force
        $curRev = if ($t.PSObject.Properties.Name -contains "_rev") { [int]$t._rev } else { 1 }
        $t | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
        $clearedTasks.Add([string]$t.id)
      }
    }
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
  }
  $clearedSubs = [System.Collections.Generic.List[string]]::new(); $closedIdle = [System.Collections.Generic.List[string]]::new()
  $subFile = Join-Path -Path $Workspace -ChildPath ".agents/office/subagents.json"
  if (($check.StaleSubagents.Count -gt 0 -or $check.IdleSubagents.Count -gt 0) -and (Test-Path -LiteralPath $subFile)) {
    $subObj = Read-SenSafeJson -Path $subFile
    $isWrapped = ($null -ne $subObj -and $subObj.PSObject.Properties.Name -contains "subagents")
    $subList = if ($null -eq $subObj) { @() } elseif ($isWrapped) { @($subObj.subagents) } else { @($subObj) }
    $subSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($check.StaleSubagents), [System.StringComparer]::OrdinalIgnoreCase)
    $idleSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($check.IdleSubagents), [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($s in $subList) {
      $sid = if ($s.PSObject.Properties['id'] -and $s.id) { [string]$s.id } elseif ($s.PSObject.Properties['conversationId']) { [string]$s.conversationId } else { "" }
      if ($sid -and $subSet.Contains($sid)) {
        $s | Add-Member -NotePropertyName "status" -NotePropertyValue "terminated_hung" -Force
        $s | Add-Member -NotePropertyName "state" -NotePropertyValue "terminated_hung" -Force
        $s | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue $now -Force
        $clearedSubs.Add($sid)
      }
      elseif ($sid -and $idleSet.Contains($sid)) {
        $s | Add-Member -NotePropertyName "status" -NotePropertyValue "closed_idle" -Force
        $s | Add-Member -NotePropertyName "state" -NotePropertyValue "closed_idle" -Force
        $s | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue $now -Force
        $closedIdle.Add($sid)
      }
    }
    $outPayload = if ($isWrapped) { $subObj.subagents = $subList; $subObj } else { $subList }
    Write-SenAtomicJson -Path $subFile -InputObject $outPayload -Depth 6
  }
  return [pscustomobject][ordered]@{
    ClearedCount = ($clearedTasks.Count + $clearedSubs.Count + $killedPids.Count); ClearedTaskIds = @($clearedTasks.ToArray())
    ClearedSubagents = @($clearedSubs.ToArray()); ClosedIdleSubagents = @($closedIdle.ToArray()); KilledProcessIds = @($killedPids.ToArray())
    ProtectedLongRunningIds = @($check.ActiveLongRunningIds); Resolution = $Resolution; NewStatus = $newStatus
  }
}

function Test-SenDeliveryGate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
    [string]$ProjectPath = "", [string]$SessionStartedAt = "", [int]$StaleMinutes = 15,
    [switch]$RequireActiveSessionTask, [switch]$CheckCodeHealth, [switch]$CheckVnLaw, [switch]$SkipCodeHealth, [switch]$SkipVnLaw, [switch]$EnforcePhysicalDiff
  )
  $targetDir = if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath } else { $Workspace }
  if (Get-Command Sync-SenPlanToTasks -ErrorAction SilentlyContinue) { [void](Sync-SenPlanToTasks -Workspace $Workspace) }
  foreach ($st in @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.id -like "SUBAGENT-*" -and [string]$_.status -ne "done" })) {
    [void](Complete-SenTaskReview -Workspace $Workspace -Id ([string]$st.id) -Passed $true -Reviewer "pm" -EvidenceCommand "subagent-verified" -ExitCode 0)
  }
  $hungObj = Test-SenHungTasks -Workspace $Workspace -StaleMinutes $StaleMinutes
  $tasks = @(Get-SenTasks -Workspace $Workspace)
  $active = @($tasks | Where-Object { [string]$_.status -ne "backlog" })
  $incomplete = [System.Collections.Generic.List[string]]::new(); $rems = [System.Collections.Generic.List[string]]::new(); $doneCount = 0
  foreach ($t in $active) {
    $hasValidEvidence = ($null -ne $t.evidence) -and (-not [string]::IsNullOrWhiteSpace([string]$t.evidence.command)) -and ([int]$t.evidence.exitCode -eq 0)
    if ([string]$t.status -eq "done" -and $hasValidEvidence) { $doneCount++ } else { $incomplete.Add([string]$t.id) }
  }
  $reasons = [System.Collections.Generic.List[string]]::new()
  $allowed = ($active.Count -gt 0) -and ($incomplete.Count -eq 0) -and $hungObj.Healthy
  if (-not $hungObj.Healthy) { $reasons.Add("Hung tasks or stale subagents ($((@($hungObj.StaleTaskIds) + @($hungObj.StaleSubagents)) -join ', '))"); $rems.Add("Clear-SenHungTasks -Workspace '$Workspace'") }
  if ($active.Count -eq 0) { $reasons.Add("No active tasks registered in tasks.json"); $rems.Add("New-SenTask -Workspace '$Workspace' -Title 'Task'") }
  elseif ($incomplete.Count -gt 0) { $reasons.Add("Incomplete or unverified tasks ($($incomplete -join ', '))"); $rems.Add("Complete-SenTaskReview -Workspace '$Workspace' -Id '$($incomplete[0])' -Passed `$true -Reviewer 'qa' -EvidenceCommand 'tests/run.ps1' -ExitCode 0") }

  $auditFile = Join-Path $Workspace ".agents/office/process-audit.json"
  $auditObj = if (Test-Path -LiteralPath $auditFile) { Read-SenSafeJson -Path $auditFile } else { $null }
  $sessStart = if (-not [string]::IsNullOrWhiteSpace($SessionStartedAt)) { $SessionStartedAt } elseif ($auditObj -and $auditObj.PSObject.Properties['startedAt']) { [string]$auditObj.startedAt } else { "" }
  if ($active.Count -gt 0 -and (-not [string]::IsNullOrWhiteSpace($sessStart) -or $RequireActiveSessionTask.IsPresent)) {
    $minTs = if (-not [string]::IsNullOrWhiteSpace($sessStart)) { $sessStart } else { [DateTime]::UtcNow.AddHours(-4).ToString("yyyy-MM-ddTHH:mm:ssZ") }
    $sessionDone = @($active | Where-Object { [string]$_.status -eq "done" -and ([string]$_.updatedAt -ge $minTs -or ($_.evidence -and [string]$_.evidence.verifiedAt -ge $minTs)) })
    if ($sessionDone.Count -eq 0) { $allowed = $false; $reasons.Add("No tasks verified in current audit session since $minTs"); $rems.Add("Initialize-SenProcessAudit -Workspace '$Workspace'") }
  }
  $codeHealthObj = if ((-not $SkipCodeHealth.IsPresent) -and (Get-Command Measure-SenCodeHealth -ErrorAction SilentlyContinue)) { Measure-SenCodeHealth -Path $targetDir } else { $null }
  if ($null -ne $codeHealthObj -and (-not $codeHealthObj.Healthy)) { $allowed = $false; $reasons.Add("Clean Code check failed (Score=$($codeHealthObj.Score))"); $rems.Add("Measure-SenCodeHealth -Path '$targetDir'") }
  $vnLawObj = if ((-not $SkipVnLaw.IsPresent) -and (Get-Command Invoke-SenVnLawScan -ErrorAction SilentlyContinue)) { Invoke-SenVnLawScan -Path $targetDir } else { $null }
  if ($null -ne $vnLawObj -and (-not $vnLawObj.CompliantCodeLevel)) {
    $allowed = $false; $codes = @($vnLawObj.CodeRedFlags | ForEach-Object { $_.Code }) -join ', '; $reasons.Add("Vietnam Law code red flags ($codes)"); $rems.Add("Invoke-SenVnLawScan -Path '$targetDir'")
  }
  $complianceObj = if ($null -ne $auditObj -and (Get-Command Test-SenProjectCompliance -ErrorAction SilentlyContinue)) { Test-SenProjectCompliance -Workspace $Workspace -ProjectPath $targetDir } else { $null }
  if ($null -ne $complianceObj -and (-not $complianceObj.Compliant)) { $allowed = $false; $reasons.Add("Process Compliance missing steps ($($complianceObj.MissingSteps -join ', '))"); $rems.Add("Test-SenProjectCompliance -Workspace '$Workspace'") }
  $rtmObj = if ((Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/requirements.json")) -and (Get-Command Get-SenRequirementTraceability -ErrorAction SilentlyContinue)) { Get-SenRequirementTraceability -Workspace $Workspace } else { $null }
  if ($null -ne $rtmObj -and (-not $rtmObj.Accepted)) { $allowed = $false; $reasons.Add("Requirement Traceability NOT_ACCEPTED (Unverified=$($rtmObj.UnverifiedRequirements -join ', '))"); $rems.Add("Get-SenRequirementTraceability -Workspace '$Workspace'") }
  if ((Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/quality-baseline.json")) -and (Get-Command Test-SenAntiMetricGaming -ErrorAction SilentlyContinue)) {
    $amgObj = Test-SenAntiMetricGaming -Workspace $Workspace
    if (-not $amgObj.Passed) { $allowed = $false; $reasons.Add("Anti-Metric Gaming violation ($($amgObj.Violations -join '; '))"); $rems.Add("Lock-SenQualityBaseline -Workspace '$Workspace'") }
  }
  if (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/bounded-loops.json")) {
    $escClaims = @(Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/bounded-loops.json") | Where-Object { $_ -and [string]$_.state -in @("ESCALATED", "REJECTED") } | ForEach-Object { [string]$_.claimId })
    if ($escClaims.Count -gt 0) { $allowed = $false; $reasons.Add("Quarantined ESCALATED claims awaiting pre-push review ($($escClaims -join ', '))"); $rems.Add("Invoke-SenEscalationQuarantine -Workspace '$Workspace' -ClaimId '$($escClaims[0])'") }
  }
  if ($EnforcePhysicalDiff.IsPresent -and (Get-Command Test-SenEvidenceValidity -ErrorAction SilentlyContinue)) {
    $evVal = Test-SenEvidenceValidity -Workspace $Workspace
    if (-not $evVal.AllValid) { $allowed = $false; $reasons.Add("Physical diff / stale evidence ($($evVal.StaleEvidenceIds -join ', '))"); $rems.Add("Register-SenEvidence -Workspace '$Workspace' -Command 'tests/run.ps1' -ExitCode 0") }
  }
  if ((Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/state-seal.json")) -and (Get-Command Sync-SenOfficeState -ErrorAction SilentlyContinue)) {
    $sealRes = Sync-SenOfficeState -Workspace $Workspace -VerifySeal
    if ($sealRes.Tampered) { $allowed = $false; $reasons.Add("State seal tampered ($($sealRes.TamperedFiles -join ', '))"); $rems.Add($sealRes.RemediationCommand) }
  }
  $reason = if ($allowed) { "All $($active.Count) active task(s) verified and done." } else { "Delivery blocked: " + ($reasons -join "; ") + "." }
  return [pscustomobject]@{
    Allowed = $allowed; Passed = $allowed; TotalActive = $active.Count; DoneCount = $doneCount; IncompleteIds = @($incomplete.ToArray())
    HungTasks = $hungObj; CodeHealth = $codeHealthObj; VnLawScan = $vnLawObj; ProcessCompliance = $complianceObj; RequirementTraceability = $rtmObj
    Reason = $reason; Issues = @($reasons.ToArray()); RemediationCommands = @($rems.ToArray())
  }
}

function Get-SenRecoveryState {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
  $tasks = @(Get-SenTasks -Workspace $Workspace)
  $inProgress = @($tasks | Where-Object { [string]$_.status -eq "in_progress" } | ForEach-Object { [string]$_.id })
  $reviewing  = @($tasks | Where-Object { [string]$_.status -eq "reviewing" } | ForEach-Object { [string]$_.id })
  $ready      = @($tasks | Where-Object { [string]$_.status -eq "ready" } | ForEach-Object { [string]$_.id })
  $pending    = @($tasks | Where-Object { [string]$_.status -eq "pending" } | ForEach-Object { [string]$_.id })
  $done       = @($tasks | Where-Object { [string]$_.status -eq "done" } | ForEach-Object { [string]$_.id })
  $backlog    = @($tasks | Where-Object { [string]$_.status -eq "backlog" } | ForEach-Object { [string]$_.id })
  $failed     = @($tasks | Where-Object { [string]$_.status -eq "failed" } | ForEach-Object { [string]$_.id })
  return [pscustomobject][ordered]@{
    needsRecovery = [bool](($inProgress.Count + $reviewing.Count + $failed.Count) -gt 0); totalTasks = $tasks.Count
    doneIds = $done; inProgressIds = $inProgress; reviewingIds = $reviewing; readyIds = $ready; pendingIds = $pending; failedIds = $failed; backlogIds = $backlog
  }
}

function Get-SenQualityMetrics {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
  $tasks = @(Get-SenTasks -Workspace $Workspace)
  $active = @($tasks | Where-Object { [string]$_.status -ne "backlog" })
  $backlog = @($tasks | Where-Object { [string]$_.status -eq "backlog" })
  $done = @($active | Where-Object { [string]$_.status -eq "done" })
  $inProg = @($active | Where-Object { [string]$_.status -in @("in_progress", "reviewing") })
  $ready = @($active | Where-Object { [string]$_.status -in @("ready", "pending") })
  $totalActive = $active.Count; $doneCount = $done.Count
  $firstPassCount = @($done | Where-Object { [int]$_.reworkCount -eq 0 }).Count
  $reworkedCount = @($active | Where-Object { [int]$_.reworkCount -gt 0 }).Count
  $verifiedPassCount = @($done | Where-Object { $null -ne $_.evidence -and [int]$_.evidence.exitCode -eq 0 }).Count
  $successPct = if ($totalActive -gt 0) { [int][Math]::Round(($doneCount * 100.0) / $totalActive) } else { 100 }
  $firstPassPct = if ($doneCount -gt 0) { [int][Math]::Round(($firstPassCount * 100.0) / $doneCount) } else { 100 }
  $reworkPct = if ($totalActive -gt 0) { [int][Math]::Round(($reworkedCount * 100.0) / $totalActive) } else { 0 }
  $testPassPct = if ($doneCount -gt 0) { [int][Math]::Round(($verifiedPassCount * 100.0) / $doneCount) } else { 100 }
  $reqCovPct = 100
  if ((Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/requirements.json")) -and (Get-Command Get-SenRequirementTraceability -ErrorAction SilentlyContinue)) {
    $rtm = Get-SenRequirementTraceability -Workspace $Workspace
    if ($rtm.TotalRequirements -gt 0) { $reqCovPct = [int][Math]::Round(($rtm.Verified * 100.0) / $rtm.TotalRequirements) }
  }
  return [pscustomobject][ordered]@{
    totalTasks = $tasks.Count; activeTasks = $totalActive; doneTasks = $doneCount; inProgressTasks = $inProg.Count
    readyTasks = $ready.Count; backlogTasks = $backlog.Count; taskSuccessRatePct = $successPct
    firstPassRatePct = $firstPassPct; reworkRatePct = $reworkPct; testPassRatePct = $testPassPct; requirementCoveragePct = $reqCovPct
  }
}

function Add-SenBacklogItem {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Workspace, [Parameter(Mandatory = $false)][string]$Id = ("BL-" + [Guid]::NewGuid().ToString("N").Substring(0, 6)), [Parameter(Mandatory = $true)][string]$Title, [string]$Priority = "P1", [string]$Details = "", [string]$Module = "Backlog")
  $task = New-SenTask -Workspace $Workspace -Id $Id -Title $Title -Tier 2 -RiskLevel "medium" -Module $Module -Assignee "pm" -Status "backlog"
  $docsDir = Join-Path -Path $Workspace -ChildPath "docs"
  if (-not (Test-Path -LiteralPath $docsDir)) { [System.IO.Directory]::CreateDirectory($docsDir) | Out-Null }
  $todoPath = Join-Path -Path $docsDir -ChildPath "TODO.md"
  $existingText = if (Test-Path -LiteralPath $todoPath) { [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $todoPath).Path, [System.Text.Encoding]::UTF8) } else { "# Project Backlog (TODO)`n`n" }
  if ($existingText -notmatch "(?<!\w)$([regex]::Escape($Id))(?!\w)") {
    $entryLine = "- [ ] **${Id} (${Priority}): ${Title}**" + $(if (-not [string]::IsNullOrWhiteSpace($Details)) { "`n  - " + $Details.Trim() } else { "" })
    [System.IO.File]::WriteAllText($todoPath, ($existingText.TrimEnd() + "`n`n" + $entryLine + "`n"), [System.Text.UTF8Encoding]::new($false))
  }
  return [pscustomobject]@{ Id = $Id; Title = $Title; Priority = $Priority; TodoPath = $todoPath; Task = $task }
}

function New-SenRestorePoint {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Parameter(Mandatory = $false)][string[]]$Files = @(), [string]$Label = "pre-edit")
  $resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('\', '/')
  $restoreRoot = Join-Path -Path $resolvedWs -ChildPath ".agents/.sen-restore"
  $ts = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
  $id = "rp-$ts-" + ([Guid]::NewGuid().ToString("N").Substring(0, 6))
  $rpDir = Join-Path -Path $restoreRoot -ChildPath $id
  $filesDir = Join-Path -Path $rpDir -ChildPath "files"
  [System.IO.Directory]::CreateDirectory($filesDir) | Out-Null
  $skipHeavyRe = '(?i)(^|[\\/])(node_modules|\.git|\.agents|Code|Antigravity IDE|dist|build)([\\/]|$)'
  $entries = [System.Collections.Generic.List[object]]::new()
  $idx = 0
  foreach ($f in $Files) {
    if ([string]::IsNullOrWhiteSpace($f) -or ($f -match $skipHeavyRe)) { continue }
    $fullPath = if ([System.IO.Path]::IsPathRooted($f)) { [System.IO.Path]::GetFullPath($f) } else { [System.IO.Path]::GetFullPath((Join-Path $resolvedWs $f)) }
    $relPath = if ($fullPath.StartsWith($resolvedWs, [System.StringComparison]::OrdinalIgnoreCase)) { $fullPath.Substring($resolvedWs.Length).TrimStart('\', '/') } else { [System.IO.Path]::GetFileName($fullPath) }
    if ($relPath -match $skipHeavyRe) { continue }
    $existed = Test-Path -LiteralPath $fullPath -PathType Leaf
    $storedName = "f_$idx.bak"
    if ($existed) { Copy-Item -LiteralPath $fullPath -Destination (Join-Path $filesDir $storedName) -Force }
    $entries.Add([ordered]@{ relPath = $relPath; fullPath = $fullPath; existed = [bool]$existed; storedName = $storedName })
    $idx++
  }
  $manifest = [ordered]@{ id = $id; label = $Label; createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); entries = @($entries.ToArray()) }
  Write-SenAtomicJson -Path (Join-Path -Path $rpDir -ChildPath "manifest.json") -InputObject $manifest -Depth 6
  return [pscustomobject]@{ Id = $id; Label = $Label; Directory = $rpDir; FileCount = $entries.Count }
}

function Restore-SenRestorePoint {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$Id = "")
  $resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('\', '/')
  $restoreRoot = Join-Path -Path $resolvedWs -ChildPath ".agents/.sen-restore"
  if (-not (Test-Path -LiteralPath $restoreRoot)) { return [pscustomobject]@{ Restored = $false; Id = $null; Error = "No restore points found" } }
  $targetDir = if (-not [string]::IsNullOrWhiteSpace($Id)) {
    $cand = Join-Path -Path $restoreRoot -ChildPath $Id
    if (Test-Path -LiteralPath $cand) { Get-Item -LiteralPath $cand } else { $null }
  }
  else { Get-ChildItem -LiteralPath $restoreRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1 }
  if ($null -eq $targetDir) { return [pscustomobject]@{ Restored = $false; Id = $Id; Error = "Restore point not found" } }
  $manifest = Read-SenSafeJson -Path (Join-Path -Path $targetDir.FullName -ChildPath "manifest.json")
  if ($null -eq $manifest) { return [pscustomobject]@{ Restored = $false; Id = $targetDir.Name; Error = "Manifest missing" } }
  $filesDir = Join-Path -Path $targetDir.FullName -ChildPath "files"
  $restoredCount = 0
  foreach ($e in @($manifest.entries)) {
    $destPath = Join-Path -Path $resolvedWs -ChildPath ([string]$e.relPath)
    if ([bool]$e.existed) {
      $srcBak = Join-Path -Path $filesDir -ChildPath ([string]$e.storedName)
      if (Test-Path -LiteralPath $srcBak) {
        $parent = Split-Path -Parent $destPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
        Copy-Item -LiteralPath $srcBak -Destination $destPath -Force; $restoredCount++
      }
    }
    elseif (Test-Path -LiteralPath $destPath) { Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue; $restoredCount++ }
  }
  return [pscustomobject]@{ Restored = $true; Id = [string]$manifest.id; RestoredCount = $restoredCount; Error = $null }
}

$senGovPath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Governance.psm1"
if (Test-Path -LiteralPath $senGovPath) {
  Import-Module -Name $senGovPath -Global -Force
}

Export-ModuleMember -Function Save-SenTasks, Get-SenTasks, Clear-SenTasks, New-SenTask, Get-SenReadyTasks, Start-SenTask, Unlock-SenTask, Submit-SenTaskForReview, Complete-SenTaskReview, Test-SenHungTasks, Clear-SenHungTasks, Test-SenDeliveryGate, Get-SenRecoveryState, Get-SenQualityMetrics, Add-SenBacklogItem, New-SenRestorePoint, Restore-SenRestorePoint

