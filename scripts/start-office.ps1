# scripts/start-office.ps1
# Zero-dependency Local Office Server (ASCII only) for Sen Office v0.2.0.
# Serves office/index.html and /api/state, /api/config, /api/event, /api/clear over 127.0.0.1:<Port>.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workspace,
    [int]$Port = 0,
    [switch]$NoBrowser,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Runtime.psm1"
if (-not (Test-Path -LiteralPath $senModule)) {
    $senModule = Join-Path -Path $PSScriptRoot -ChildPath "Sen.psm1"
}
Import-Module $senModule -Force

$resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path
$cfg = Get-SenOfficeConfig -Workspace $resolvedWs
$usePort = if ($Port -gt 1024) { $Port } else { [int]$cfg.port }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
$htmlPath = Join-Path -Path $repoRoot -ChildPath "office/index.html"

if (-not (Test-Path -LiteralPath $htmlPath)) {
    throw "office/index.html not found at $htmlPath"
}

if ($DryRun) {
    $out = [ordered]@{
        workspace = $resolvedWs
        port      = $usePort
        url       = "http://127.0.0.1:$usePort/"
        htmlPath  = $htmlPath
        mode      = $cfg.mode
        dryRun    = $true
    }
    Write-Output ($out | ConvertTo-Json -Compress)
    exit 0
}

$tabSt = Get-SenOfficeTabStatus -Workspace $resolvedWs -Port $usePort
if ($tabSt.ServerAlive) {
    [void](Sync-SenOfficeActiveWorkspace -Port $usePort -Workspace $resolvedWs)
    Write-Host ("SEN_OFFICE_URL=" + $tabSt.Url)
    if ($tabSt.TabAlive -or $NoBrowser) {
        Write-Host "SEN_OFFICE_STATUS=ALREADY_OPEN"
        Write-Host ("SEN_OFFICE_HINT=" + $tabSt.UserHint)
        exit 0
    }
    [void](Update-SenOfficeTabHeartbeat -Workspace $resolvedWs -Port $usePort -Launched)
    try { Start-Process $tabSt.Url } catch { <# Ignore headless environments without browser #> }
    Write-Host "SEN_OFFICE_STATUS=REOPENED_CLOSED_TAB"
    Write-Host ("SEN_OFFICE_HINT=" + $tabSt.UserHint)
    exit 0
}

# Find an available loopback port starting at $usePort
$listener = $null
for ($try = 0; $try -lt 20; $try++) {
    $candidate = $usePort + $try
    try {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $candidate)
        $l.Start()
        $listener = $l
        $usePort = $candidate
        break
    }
    catch { <# Port busy; try next port in range #> }
}
if ($null -eq $listener) {
    throw "Could not bind Local Office Server on ports $usePort..$($usePort + 19)"
}

Set-SenOfficeConfig -Workspace $resolvedWs -Mode $cfg.mode -Port $usePort | Out-Null
$url = "http://127.0.0.1:$usePort/"
[void](Update-SenOfficeTabHeartbeat -Workspace $resolvedWs -Port $usePort -Launched)
Write-Host ("SEN_OFFICE_URL=" + $url)
Write-Host "SEN_OFFICE_STATUS=STARTED_NEW"

if (-not $NoBrowser) {
    try { Start-Process $url } catch { <# Ignore headless environments without browser #> }
}

function Send-HttpResponse($stream, [int]$statusCode, [string]$statusText, [string]$contentType, [byte[]]$bodyBytes, [int]$allowedPort = 47890, [string]$etag = "") {
    $etagHdr = if (-not [string]::IsNullOrEmpty($etag)) { "ETag: `"$etag`"`r`n" } else { "" }
    $header = "HTTP/1.1 $statusCode $statusText`r`n" +
    "Content-Type: $contentType`r`n" +
    "Content-Length: $($bodyBytes.Length)`r`n" +
    $etagHdr +
    "Cache-Control: no-store`r`n" +
    "Access-Control-Allow-Origin: http://127.0.0.1:$allowedPort`r`n" +
    "X-Content-Type-Options: nosniff`r`n" +
    "Connection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($bodyBytes.Length -gt 0) {
        $stream.Write($bodyBytes, 0, $bodyBytes.Length)
    }
    $stream.Flush()
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 3000
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $false, 4096, $true)
            $reqLine = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($reqLine)) { $client.Close(); continue }
            $parts = $reqLine -split ' '
            $method = $parts[0]
            $rawUrlParts = $parts[1] -split '\?', 2
            $path = $rawUrlParts[0]
            $queryStr = if ($rawUrlParts.Count -gt 1) { $rawUrlParts[1] } else { "" }

            $contentLen = 0
            $originHdr = ""
            $hostHdr = ""
            $contentTypeHdr = ""
            $ifNoneMatchHdr = ""
            $uaHdr = ""
            while ($true) {
                $hLine = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($hLine)) { break }
                if ($hLine -match '(?i)^Content-Length:\s*(\d+)') {
                    $contentLen = [int]$matches[1]
                }
                elseif ($hLine -match '(?i)^Origin:\s*(.+)$') {
                    $originHdr = $matches[1].Trim()
                }
                elseif ($hLine -match '(?i)^Host:\s*(.+)$') {
                    $hostHdr = $matches[1].Trim()
                }
                elseif ($hLine -match '(?i)^Content-Type:\s*(.+)$') {
                    $contentTypeHdr = $matches[1].Trim()
                }
                elseif ($hLine -match '(?i)^If-None-Match:\s*(.+)$') {
                    $ifNoneMatchHdr = $matches[1].Trim()
                }
                elseif ($hLine -match '(?i)^User-Agent:\s*(.+)$') {
                    $uaHdr = $matches[1].Trim()
                }
            }

            if ((-not [string]::IsNullOrEmpty($hostHdr)) -and ($hostHdr -notmatch '^(?i)(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$')) {
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"forbidden host header"}')
                Send-HttpResponse $stream 403 "Forbidden" "application/json; charset=utf-8" $errBytes $usePort
                continue
            }

            if ($contentLen -gt 65536) {
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"payload too large"}')
                Send-HttpResponse $stream 413 "Payload Too Large" "application/json; charset=utf-8" $errBytes $usePort
                continue
            }

            if ($method -eq "POST" -and (-not [string]::IsNullOrEmpty($originHdr)) -and ($originHdr -notmatch '^(?i)https?://(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$')) {
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"forbidden origin"}')
                Send-HttpResponse $stream 403 "Forbidden" "application/json; charset=utf-8" $errBytes $usePort
                continue
            }

            if ($method -eq "POST" -and ($path -in @("/api/config", "/api/clear", "/api/event", "/api/switch-workspace")) -and (($contentLen -gt 0) -or [string]::IsNullOrEmpty($originHdr)) -and ($contentTypeHdr -notmatch '(?i)application/json')) {
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"error":"application/json required"}')
                Send-HttpResponse $stream 415 "Unsupported Media Type" "application/json; charset=utf-8" $errBytes $usePort
                continue
            }

            $bodyStr = ""
            if ($contentLen -gt 0) {
                $buf = New-Object char[] $contentLen
                $readTotal = 0
                while ($readTotal -lt $contentLen) {
                    $n = $reader.Read($buf, $readTotal, $contentLen - $readTotal)
                    if ($n -le 0) { break }
                    $readTotal += $n
                }
                $bodyStr = [string]::new($buf, 0, $readTotal)
            }

            if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
                $bytes = [System.IO.File]::ReadAllBytes($htmlPath)
                Send-HttpResponse $stream 200 "OK" "text/html; charset=utf-8" $bytes $usePort
            }
            elseif ($method -eq "GET" -and $path -eq "/api/state") {
                $tabSess = Update-SenOfficeTabHeartbeat -Workspace $resolvedWs -Port $usePort -UserAgent $uaHdr -QueryString $queryStr
                $c = Get-SenOfficeConfig -Workspace $resolvedWs
                $evs = @(Read-SenOfficeEvents -Workspace $resolvedWs -Limit 150)
                $sh = Read-SenOfficeShowcase -Workspace $resolvedWs
                $q = Get-SenAntigravityQuota
                $tks = @(Get-SenTasks -Workspace $resolvedWs)
                $met = Get-SenQualityMetrics -Workspace $resolvedWs
                $rec = Get-SenRecoveryState -Workspace $resolvedWs
                $les = @(Get-SenExecutionLessons -Workspace $resolvedWs)
                $inObj = Read-SenSafeJson -Path (Join-Path $resolvedWs ".agents/office/current-intake.json")
                $auObj = Read-SenSafeJson -Path (Join-Path $resolvedWs ".agents/office/process-audit.json")
                $qItems = Read-SenSafeJson -Path (Join-Path $resolvedWs ".agents/office/task-queue.state")
                $st = [ordered]@{
                    live       = $true
                    workspace  = $resolvedWs
                    config     = $c
                    events     = $evs
                    showcase   = $sh
                    quota      = $q
                    tasks      = $tks
                    metrics    = $met
                    recovery   = $rec
                    lessons    = $les
                    intake     = $inObj
                    audit      = $auObj
                    queue      = $(if ($qItems) { @($qItems) } else { @() })
                    tabSession = $tabSess
                }
                $jBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $st -Depth 8 -Compress))
                $etagVal = ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($jBytes))).Replace("-", "").Substring(0, 16).ToLowerInvariant()
                if ($ifNoneMatchHdr -and ($ifNoneMatchHdr.Trim('"') -eq $etagVal)) {
                    Send-HttpResponse $stream 304 "Not Modified" "application/json; charset=utf-8" ([byte[]]@()) $usePort $etagVal
                }
                else {
                    Send-HttpResponse $stream 200 "OK" "application/json; charset=utf-8" $jBytes $usePort $etagVal
                }
            }
            elseif ($method -eq "POST" -and $path -eq "/api/client-bye") {
                [void](Update-SenOfficeTabHeartbeat -Workspace $resolvedWs -Port $usePort -UserAgent $uaHdr -Closed)
                $jBytes = [System.Text.Encoding]::UTF8.GetBytes('{"closed":true}')
                Send-HttpResponse $stream 200 "OK" "application/json; charset=utf-8" $jBytes $usePort
            }
            elseif ($method -eq "POST" -and $path -eq "/api/config") {
                $reqObj = ConvertFrom-Json -InputObject $bodyStr
                $newMode = if ($reqObj.mode -in @("off", "eco", "full")) { [string]$reqObj.mode } else { "eco" }
                $updated = Set-SenOfficeConfig -Workspace $resolvedWs -Mode $newMode -Port $usePort
                $jBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $updated -Compress))
                Send-HttpResponse $stream 200 "OK" "application/json; charset=utf-8" $jBytes $usePort
            }
            elseif ($method -eq "POST" -and $path -eq "/api/clear") {
                Clear-SenOfficeEvents -Workspace $resolvedWs
                $jBytes = [System.Text.Encoding]::UTF8.GetBytes('{"cleared":true}')
                Send-HttpResponse $stream 200 "OK" "application/json; charset=utf-8" $jBytes $usePort
            }
            elseif ($method -eq "POST" -and $path -eq "/api/switch-workspace") {
                $reqObj = ConvertFrom-Json -InputObject $bodyStr
                if ($reqObj -and $reqObj.workspace -and (Test-Path -LiteralPath ([string]$reqObj.workspace))) {
                    $resolvedWs = (Resolve-Path -LiteralPath ([string]$reqObj.workspace)).Path
                }
                $jBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ switched = $true; workspace = $resolvedWs } -Compress))
                Send-HttpResponse $stream 200 "OK" "application/json; charset=utf-8" $jBytes $usePort
            }
            else {
                $nf = [System.Text.Encoding]::UTF8.GetBytes('{"error":"not found"}')
                Send-HttpResponse $stream 404 "Not Found" "application/json; charset=utf-8" $nf $usePort
            }
        }
        catch { <# Ignore disconnected HTTP client socket #> }
        finally {
            try { $client.Close() } catch { <# Socket already closed #> }
        }
    }
}
finally {
    if ($listener) { $listener.Stop() }
}

