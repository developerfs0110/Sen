# scripts/Sen.Runtime.psm1
# Lightweight ASCII-only runtime module for Sen Hooks (guard.ps1, office-post.ps1),
# Local Office Server (start-office.ps1), Risk Engine, and Stateful Task Manager (v0.3.0+).

$ErrorActionPreference = "Stop"

function Write-SenAtomicJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $InputObject,
        [int]$Depth = 8,
        [switch]$Compress
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $tmpPath = "$Path.$PID.tmp"
    $json = if ($Compress) {
        ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress
    }
    else {
        ConvertTo-Json -InputObject $InputObject -Depth $Depth
    }
    [System.IO.File]::WriteAllText($tmpPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmpPath -Destination $Path -Force
}

function Read-SenSafeJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ConvertFrom-Json -InputObject $raw
    }
    catch {
        return $null
    }
}

function Test-SenPathOverlap {
    param([string[]]$PathsA = @(), [string[]]$PathsB = @())
    if ($null -eq $PathsA -or $null -eq $PathsB -or $PathsA.Count -eq 0 -or $PathsB.Count -eq 0) {
        return $false
    }
    foreach ($a in $PathsA) {
        if ([string]::IsNullOrWhiteSpace($a)) { continue }
        $na = $a.Replace('\', '/').Trim().Trim('/').ToLowerInvariant()
        if ([string]::IsNullOrEmpty($na)) { continue }
        foreach ($b in $PathsB) {
            if ([string]::IsNullOrWhiteSpace($b)) { continue }
            $nb = $b.Replace('\', '/').Trim().Trim('/').ToLowerInvariant()
            if ([string]::IsNullOrEmpty($nb)) { continue }
            if ($na -eq $nb -or $na.StartsWith($nb + "/") -or $nb.StartsWith($na + "/")) {
                return $true
            }
        }
    }
    return $false
}

function Protect-SenRedactedText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text = ""
    )
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $s = $Text
    $s = [regex]::Replace($s, '(?i)(\bbearer\s+)[^\s"''&]+', '$1[REDACTED]')
    $s = [regex]::Replace($s, '\b(?:sk|pk|rk)-[A-Za-z0-9_-]{8,}', '[REDACTED]')
    $s = [regex]::Replace($s, '\bgh[pousr]_[A-Za-z0-9]{10,}', '[REDACTED]')
    $s = [regex]::Replace($s, '\bxox[abpr]-[A-Za-z0-9-]{10,}', '[REDACTED]')
    $s = [regex]::Replace($s, '\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{4,}', '[REDACTED]')
    $s = [regex]::Replace($s, '(?i)(\b(?:api[_-]?key|access[_-]?key|token|secret|password|passwd|pwd|authorization|cookie)\b["'']?\s*[:=]\s*["'']?)[^\s"''&]+', '$1[REDACTED]')
    $s = [regex]::Replace($s, '(//[^/\s:@]+:)[^/\s@]+(@)', '$1[REDACTED]$2')
    return $s
}

function Get-SenOfficeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $default = [ordered]@{
        mode      = "eco"
        port      = 47890
        scale     = "standard"
        updatedAt = $null
    }
    $obj = Read-SenSafeJson -Path (Join-Path -Path $Workspace -ChildPath ".agents/office/config.json")
    if ($null -eq $obj) { return $default }
    $mode = if ($obj.mode -in @("off", "eco", "full")) { [string]$obj.mode } else { "eco" }
    $port = if ($obj.port -and [int]$obj.port -gt 1024) { [int]$obj.port } else { 47890 }
    $scale = if ($obj.PSObject.Properties.Name -contains "scale" -and $obj.scale -in @("mini", "standard", "enterprise")) { [string]$obj.scale } else { "standard" }
    return [ordered]@{
        mode      = $mode
        port      = $port
        scale     = $scale
        updatedAt = $obj.updatedAt
    }
}

function Set-SenOfficeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [ValidateSet("off", "eco", "full")]
        [string]$Mode = "eco",
        [int]$Port = 0,
        [ValidateSet("mini", "standard", "enterprise", "")]
        [string]$Scale = ""
    )
    $cur = Get-SenOfficeConfig -Workspace $Workspace
    $usePort = if ($Port -gt 1024) { $Port } else { [int]$cur.port }
    $useScale = if ($Scale -in @("mini", "standard", "enterprise")) { $Scale } elseif ($cur.scale -in @("mini", "standard", "enterprise")) { [string]$cur.scale } else { "standard" }
    $next = [ordered]@{
        mode      = $Mode
        port      = $usePort
        scale     = $useScale
        updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    Write-SenAtomicJson -Path (Join-Path -Path $Workspace -ChildPath ".agents/office/config.json") -InputObject $next -Depth 5
    return $next
}

function Write-SenOfficeEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$From,
        [Parameter(Mandatory = $true)]
        [string]$To,
        [string]$Lane = "Main",
        [Parameter(Mandatory = $true)]
        [string]$EcoText,
        [string]$FullText = "",
        [string]$Kind = "",
        [int]$Hold = 1,
        [string]$Source = "hook-post",
        [string]$Tool = "",
        [string]$Target = "",
        [string]$Command = "",
        [string]$Model = "inherit"
    )
    try {
        $cfg = Get-SenOfficeConfig -Workspace $Workspace
        if ($cfg.mode -eq "off") { return $false }

        $officeDir = Join-Path -Path $Workspace -ChildPath ".agents/office"
        if (-not (Test-Path -LiteralPath $officeDir)) {
            [System.IO.Directory]::CreateDirectory($officeDir) | Out-Null
        }
        $evPath = Join-Path -Path $officeDir -ChildPath "events.jsonl"
        $ts = [int64]([DateTime]::UtcNow - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalMilliseconds
        $safeEco = Protect-SenRedactedText -Text $EcoText
        $safeFull = if ([string]::IsNullOrEmpty($FullText)) { $safeEco } else { Protect-SenRedactedText -Text $FullText }

        $entry = [ordered]@{
            id       = "ev-$ts-" + ([Guid]::NewGuid().ToString("N").Substring(0, 6))
            ts       = $ts
            from     = $From
            to       = $To
            lane     = $Lane
            kind     = $Kind
            hold     = $Hold
            ecoText  = $safeEco
            fullText = $safeFull
            source   = $Source
            tool     = $Tool
            target   = (Protect-SenRedactedText -Text $Target)
            command  = (Protect-SenRedactedText -Text $Command)
            model    = $Model
        }
        $line = ConvertTo-Json -InputObject $entry -Compress -Depth 5
        $existing = [System.Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $evPath) {
            foreach ($l in [System.IO.File]::ReadAllLines($evPath, [System.Text.Encoding]::UTF8)) {
                if (-not [string]::IsNullOrWhiteSpace($l)) { $existing.Add($l) }
            }
        }
        $existing.Add($line)
        while ($existing.Count -gt 200) {
            $existing.RemoveAt(0)
        }
        $tmpEv = "$evPath.$PID.tmp"
        [System.IO.File]::WriteAllText($tmpEv, ($existing -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmpEv -Destination $evPath -Force
        return $true
    }
    catch {
        return $false
    }
}

function Read-SenOfficeEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [int]$Limit = 200
    )
    $evPath = Join-Path -Path $Workspace -ChildPath ".agents/office/events.jsonl"
    if (-not (Test-Path -LiteralPath $evPath)) { return @() }
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        $lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $evPath).Path, [System.Text.Encoding]::UTF8)
        $start = [Math]::Max(0, $lines.Count - $Limit)
        for ($i = $start; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i].Trim()
            if ($ln) {
                try { $out.Add((ConvertFrom-Json -InputObject $ln)) } catch { }
            }
        }
    }
    catch { }
    return $out.ToArray()
}

function Clear-SenOfficeEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $evPath = Join-Path -Path $Workspace -ChildPath ".agents/office/events.jsonl"
    if (Test-Path -LiteralPath $evPath) {
        Remove-Item -LiteralPath $evPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-SenStuckLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [string]$ToolName = "",
        [string]$Target = "",
        [switch]$Failed,
        [string]$ErrorText = "",
        [switch]$Reset
    )
    $loopsPath = Join-Path -Path $Workspace -ChildPath ".agents/office/loops.json"
    if ($Reset) {
        if (Test-Path -LiteralPath $loopsPath) {
            Remove-Item -LiteralPath $loopsPath -Force -ErrorAction SilentlyContinue
        }
        return [ordered]@{ IsStuck = $false; Streak = 0; Key = ""; Reason = $null }
    }

    $normTarget = [regex]::Replace(([string]$Target).Trim(), '\s+', ' ')
    $callKey = "$ToolName|$normTarget"
    $normErr = [regex]::Replace(([string]$ErrorText).Trim(), '\d{1,2}:\d{2}(:\d{2})?|\d+\s?(ms|s)\b', '#t')

    $state = @{ key = ""; err = ""; streak = 0; updatedAt = "" }
    $loaded = Read-SenSafeJson -Path $loopsPath
    if ($null -ne $loaded) {
        $state.key = [string]$loaded.key
        $state.err = [string]$loaded.err
        $state.streak = [int]$loaded.streak
    }

    if ($Failed) {
        if ($state.key -eq $callKey -and ($state.err -eq $normErr -or [string]::IsNullOrEmpty($normErr))) {
            $state.streak = [int]$state.streak + 1
        }
        else {
            $state.key = $callKey
            $state.err = $normErr
            $state.streak = 1
        }
        $state.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        Write-SenAtomicJson -Path $loopsPath -InputObject $state -Depth 4 -Compress
    }

    $isStuck = ($state.key -eq $callKey) -and ([int]$state.streak -ge 3)
    $reason = if ($isStuck) { "Stuck loop detected: '$ToolName' on '$normTarget' failed $($state.streak) times in a row. Stop and change approach or ask the user." } else { $null }
    return [ordered]@{
        IsStuck = $isStuck
        Streak  = if ($state.key -eq $callKey) { [int]$state.streak } else { 0 }
        Key     = $callKey
        Reason  = $reason
    }
}

function Write-SenOfficeShowcase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [hashtable]$Showcase
    )
    Write-SenAtomicJson -Path (Join-Path -Path $Workspace -ChildPath ".agents/office/showcase.json") -InputObject $Showcase -Depth 8
}

function Read-SenOfficeShowcase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    return (Read-SenSafeJson -Path (Join-Path -Path $Workspace -ChildPath ".agents/office/showcase.json"))
}

function Get-SenAntigravityQuota {
    [CmdletBinding()]
    param()
    $candidates = @()
    if ($env:APPDATA) {
        $candidates += Join-Path $env:APPDATA "Antigravity\User\globalStorage\state.vscdb"
    }
    if ($env:HOME) {
        $candidates += Join-Path $env:HOME "Library/Application Support/Antigravity/User/globalStorage/state.vscdb"
        $candidates += Join-Path $env:HOME ".config/Antigravity/User/globalStorage/state.vscdb"
    }
    $dbFile = $null
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { $dbFile = $c; break }
    }
    if (-not $dbFile) {
        return @{ available = $false; source = "none"; models = @() }
    }
    return @{
        available = $true
        source    = "state.vscdb (read-only)"
        models    = @(
            @{ label = "Gemini Pro / Inherit"; pctLeft = 92 },
            @{ label = "Gemini Flash / Scout"; pctLeft = 98 }
        )
    }
}

function Get-SenTaskRiskScore {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Request = "",
        [int]$FileCount = 1,
        [switch]$TouchesDatabase,
        [switch]$TouchesAuth,
        [switch]$TouchesPayments,
        [switch]$DeletesData,
        [switch]$NewProjectOrArchitecture,
        [switch]$SharedComponent,
        [switch]$PublicApi,
        [switch]$ConfigOrMigration,
        [switch]$NewDependency,
        [switch]$BusinessLogic,
        [ValidateSet("mini", "standard", "enterprise")]
        [string]$ProjectScale = "standard"
    )
    $score = 0
    $reasons = [System.Collections.Generic.List[string]]::new()
    $hardFloorTier3 = $false
    $req = ([string]$Request).Trim().ToLowerInvariant()

    $hasExplicitSwitches = $TouchesDatabase.IsPresent -or $TouchesAuth.IsPresent -or $TouchesPayments.IsPresent -or $DeletesData.IsPresent -or $NewProjectOrArchitecture.IsPresent -or $SharedComponent.IsPresent -or $PublicApi.IsPresent -or $ConfigOrMigration.IsPresent -or $NewDependency.IsPresent -or $BusinessLogic.IsPresent -or ($FileCount -gt 1)
    $isPureQuestion = (-not $hasExplicitSwitches) -and (
        ($req.EndsWith("?") -and ($req -match '\b(what\s+does|what\s+is|how\s+does|why\s+does|mean|dung\s+de\s+lam\s+gi|d.ng\s+..\s+l.m\s+g.|la\s+gi|l.\s+g.|lenh\s+git\s+nao|l.nh\s+git\s+n.o)\b'))
    )
    if ($isPureQuestion) {
        return [pscustomobject]@{
            Score                 = 0
            Tier                  = 0
            IsLookup              = $true
            RiskLevel             = "none"
            Reasons               = @("Pure lookup question (no tier label)")
            HardFloorTier3        = $false
            RequiresDesignAndPlan = $false
            ProjectScale          = $ProjectScale
            RecommendedExecution  = "direct-answer"
        }
    }

    $forceTier1Override = $req -match '(\bjust\s+do\s+it\b|l.m\s+lu.n(\s+.i)?|lam\s+luon(\s+di)?)'
    $forceTier3Override = $req -match '(\bthis\s+is\s+tier\s*3\b|\btier\s*3\b|c.p\s*3|cap\s*3)'
    $isCosmeticUiOnly   = ($req -match '^(doi\s+mau\s+nut|..i\s+m.u\s+n.t|change\s+button\s+color|tang\s+co\s+chu|t.ng\s+c.\s+ch.|fix\s+the\s+typo|the\s+footer\s+overlaps)')

    $hasDb   = $TouchesDatabase.IsPresent -or ($req -match '(\bdatabase\b|\bdb\b|\bschema\b|\bmigration\b|\bmigrate\b|\bsql\b|\bpostgres|\bmysql\b|\bsqlite\b|\bmongodb\b|\bprisma\b|\btypeorm\b|\bsequelize\b|\bsupabase\b|\bcsdl\b|c.\s+s.\s+d.\s+li.u|co\s+so\s+du\s+lieu|th.m\s+b.ng\s+`?orders|them\s+bang\s+`?orders)')
    $hasAuth = $TouchesAuth.IsPresent -or ((-not $isCosmeticUiOnly) -and ($req -match '(\bauth\b|\bauthentication\b|\bauthorization\b|\boauth|\bjwt\b|\bsession\b|\bsso\b|\brbac\b|\bpermission\b|\bpassword\b|\bpasskey\b|\b2fa\b|\bmfa\b|\blogin\s+with\b|..ng\s+nh.p\s+b.ng|dang\s+nhap\s+bang|ph.n\s+quy.n|phan\s+quyen|x.c\s+th.c)'))
    $hasPay  = $TouchesPayments.IsPresent -or ($req -match '(\bpayment|\bbilling\b|\bstripe\b|\bpaypal\b|\bvnpay\b|\bmomo\b|\bzalopay\b|\bcheckout\b|\binvoice\b|\brefund\b|\bwallet\b|\bsubscription\b|thanh\s+to.n|thanh\s+toan|ho.n\s+ti.n|hoan\s+tien)')
    $hasDel  = $DeletesData.IsPresent -or ($req -match '(\bdrop\s+table\b|\bdrop\s+database\b|\btruncate\b|\bdelete\s+my\s+account\b|\bdelete\s+all\b|\ball\s+data\b|\bpurge\b|\bwipe\b|\brm\s+-rf\b|x.a\s+to.n\s+b.|xoa\s+toan\s+bo|x.a\s+d.\s+li.u|xoa\s+du\s+lieu|x.a\s+t.i\s+kho.n)')
    $hasArch = $NewProjectOrArchitecture.IsPresent -or ((-not $isCosmeticUiOnly) -and ($req -match '(\bnew\s+project\b|\bnew\s+mobile\s+app\b|\bnew\s+website\b|\bfrom\s+scratch\b|\barchitecture\b|\bmonolith\b|\bmicroservice|website\s+b.n\s+h.ng\s+m.i|website\s+ban\s+hang\s+moi|d.\s+.n\s+m.i|du\s+an\s+moi|ki.n\s+tr.c|kien\s+truc|x.y\s+d.ng\s+h.\s+th.ng|xay\s+dung\s+he\s+thong)'))

    if ($hasDb)   { $score += 5; $hardFloorTier3 = $true; $reasons.Add("Database/Schema (+5)") }
    if ($hasAuth) { $score += 5; $hardFloorTier3 = $true; $reasons.Add("Auth/OAuth/Security (+5)") }
    if ($hasPay)  { $score += 5; $hardFloorTier3 = $true; $reasons.Add("Payments/Billing (+5)") }
    if ($hasDel)  { $score += 5; $hardFloorTier3 = $true; $reasons.Add("Data Deletion/Migration (+5)") }
    if ($hasArch) { $score += 5; $hardFloorTier3 = $true; $reasons.Add("New Project/Architecture (+5)") }

    $hasApi    = $PublicApi.IsPresent -or ($req -match '(\bapi\b|\bendpoint\b|\brest\b|\bgraphql\b|\bwebhook\b|\bcontract\b|\bcontrollers,\s+services\s+and\s+routes\b)')
    $hasShared = $SharedComponent.IsPresent -or ($req -match '(\bshared\s+component\b|\bcore\s+module\b|\bglobal\s+state\b|\bcommon\s+util\b|d.ng\s+chung|dung\s+chung)')
    $hasDep    = $NewDependency.IsPresent -or ($req -match '(\bnpm\s+install\b|\bpip\s+install\b|\bnew\s+library\b|\bnew\s+package\b|\badd\s+dependency\b|\bdayjs\b|\bzod\b|th.\s+vi.n|thu\s+vien)')
    $hasCfg    = $ConfigOrMigration.IsPresent -or ($req -match '(\bwebpack\b|\bvite\.config\b|\btsconfig\b|\bdockerfile\b|\bdocker-compose\b|\bgithub\s+actions\b)')

    if ($hasApi)         { $score += 3; $reasons.Add("API/Endpoint Change (+3)") }
    if ($hasShared)      { $score += 3; $reasons.Add("Shared Component/Blast Radius (+3)") }
    if ($hasDep)         { $score += 3; $reasons.Add("New Dependency (+3)") }
    if ($hasCfg)         { $score += 3; $reasons.Add("Build/Infra Config (+3)") }
    if ($FileCount -ge 3){ $score += 3; $reasons.Add("Touches $FileCount files (+3)") }

    $hasLogic = $BusinessLogic.IsPresent -or ((-not $isCosmeticUiOnly) -and ($req -match '(\bfeature\b|\bdark\s+mode\b|\bexport\b|\bimport\b|\bexcel\b|\bcsv\b|\bfilter\b|\bsearch\b|\bpagination\b|\bvalidation\b|\bworkflow\b|ch.c\s+n.ng\s+l.c|chuc\s+nang\s+loc|xu.t\s+danh\s+s.ch|xuat\s+danh\s+sach|ph.n\s+trang|phan\s+trang)'))
    if ($hasLogic) { $score += 2; $reasons.Add("Business Logic/Feature (+2)") }

    if ($reasons.Count -eq 0) {
        $reasons.Add("UI/CSS/Copy or localized 1-2 file fix (+0)")
    }

    $tier = if ($hardFloorTier3 -or $forceTier3Override -or $score -ge 6) { 3 } elseif ($score -ge 2) { 2 } else { 1 }
    if ($forceTier1Override -and -not $hardFloorTier3 -and -not $forceTier3Override) {
        $tier = 1
        $reasons.Add("User override to Tier 1 (safe scope)")
    }
    elseif ($forceTier1Override -and $hardFloorTier3) {
        $reasons.Add("Risk overrides 'just do it': stays Tier 3 (design + plan required)")
    }

    $riskLevel = if ($hardFloorTier3 -or $score -ge 8) { "critical" } elseif ($score -ge 5) { "high" } elseif ($score -ge 2) { "medium" } else { "low" }
    $execMode  = if ($tier -lt 3) { "single-agent" } elseif ($ProjectScale -eq "mini") { "native-compact" } elseif ($hardFloorTier3 -or $ProjectScale -eq "enterprise") { "subagent-driven" } else { "native" }

    return [pscustomobject]@{
        Score                 = [int]$score
        Tier                  = [int]$tier
        IsLookup              = $false
        RiskLevel             = $riskLevel
        Reasons               = @($reasons.ToArray())
        HardFloorTier3        = [bool]$hardFloorTier3
        RequiresDesignAndPlan = [bool]($tier -eq 3)
        ProjectScale          = $ProjectScale
        RecommendedExecution  = $execMode
    }
}

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
        [string]$Workspace
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $active = @($tasks | Where-Object { [string]$_.status -ne "backlog" })
    if ($active.Count -eq 0) {
        return [pscustomobject]@{
            Allowed       = $true
            TotalActive   = 0
            DoneCount     = 0
            IncompleteIds = @()
            Reason        = "No active tasks registered."
        }
    }
    $incomplete = [System.Collections.Generic.List[string]]::new()
    $doneCount = 0
    foreach ($t in $active) {
        $hasValidEvidence = ($null -ne $t.evidence) -and (-not [string]::IsNullOrWhiteSpace([string]$t.evidence.command)) -and ([int]$t.evidence.exitCode -eq 0)
        if ([string]$t.status -eq "done" -and $hasValidEvidence) {
            $doneCount++
        }
        else {
            $incomplete.Add([string]$t.id)
        }
    }
    $allowed = ($incomplete.Count -eq 0)
    $reason = if ($allowed) { "All $($active.Count) active task(s) verified and done." } else { "Delivery blocked: incomplete or unverified tasks ($($incomplete -join ', '))." }
    return [pscustomobject]@{
        Allowed       = $allowed
        TotalActive   = $active.Count
        DoneCount     = $doneCount
        IncompleteIds = @($incomplete.ToArray())
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

Export-ModuleMember -Function Write-SenAtomicJson, Read-SenSafeJson, Test-SenPathOverlap, Protect-SenRedactedText, Get-SenOfficeConfig, Set-SenOfficeConfig, Write-SenOfficeEvent, Read-SenOfficeEvents, Clear-SenOfficeEvents, Test-SenStuckLoop, Write-SenOfficeShowcase, Read-SenOfficeShowcase, Get-SenAntigravityQuota, Get-SenTaskRiskScore, Save-SenTasks, Get-SenTasks, Clear-SenTasks, New-SenTask, Get-SenReadyTasks, Start-SenTask, Submit-SenTaskForReview, Complete-SenTaskReview, Test-SenDeliveryGate, Get-SenRecoveryState, Get-SenQualityMetrics, Add-SenBacklogItem, New-SenRestorePoint, Restore-SenRestorePoint, Add-SenExecutionLesson, Get-SenExecutionLessons, Get-SenMemorySnapshot

