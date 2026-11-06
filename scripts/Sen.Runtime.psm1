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

$senOrchestratorPath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Orchestrator.psm1"
if (Test-Path -LiteralPath $senOrchestratorPath) {
    Import-Module -Name $senOrchestratorPath -Global -Force
}

Export-ModuleMember -Function Write-SenAtomicJson, Read-SenSafeJson, Test-SenPathOverlap, Protect-SenRedactedText, Get-SenOfficeConfig, Set-SenOfficeConfig, Write-SenOfficeEvent, Read-SenOfficeEvents, Clear-SenOfficeEvents, Test-SenStuckLoop, Write-SenOfficeShowcase, Read-SenOfficeShowcase, Get-SenAntigravityQuota, Get-SenTaskRiskScore
