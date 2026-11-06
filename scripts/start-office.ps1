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
Write-Host ("SEN_OFFICE_URL=" + $url)

if (-not $NoBrowser) {
    try { Start-Process $url } catch { <# Ignore headless environments without browser #> }
}

function Send-HttpResponse($stream, [int]$statusCode, [string]$statusText, [string]$contentType, [byte[]]$bodyBytes) {
    $header = "HTTP/1.1 $statusCode $statusText`r`n" +
              "Content-Type: $contentType`r`n" +
              "Content-Length: $($bodyBytes.Length)`r`n" +
              "Cache-Control: no-store`r`n" +
              "Access-Control-Allow-Origin: *`r`n" +
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
            $path = ($parts[1] -split '\?')[0]

            $contentLen = 0
            while ($true) {
                $hLine = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($hLine)) { break }
                if ($hLine -match '(?i)^Content-Length:\s*(\d+)') {
                    $contentLen = [int]$matches[1]
                }
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
                Send-HttpResponse $stream 200 "OK" "text/html; charset=utf-8" $bytes
            }
            elseif ($method -eq "GET" -and $path -eq "/api/state") {
                $c = Get-SenOfficeConfig -Workspace $resolvedWs
                $evs = @(Read-SenOfficeEvents -Workspace $resolvedWs -Limit 150)
                $sh = Read-SenOfficeShowcase -Workspace $resolvedWs
                $q = Get-SenAntigravityQuota
                $tks = @(Get-SenTasks -Workspace $resolvedWs)
                $met = Get-SenQualityMetrics -Workspace $resolvedWs
                $rec = Get-SenRecoveryState -Workspace $resolvedWs
                $les = @(Get-SenExecutionLessons -Workspace $resolvedWs)
                $st = [ordered]@{
                    live      = $true
                    workspace = $resolvedWs
                    config    = $c
                    events    = $evs
                    showcase  = $sh
                    quota     = $q
                    tasks     = $tks
                    metrics   = $met
                    recovery  = $rec
                    lessons   = $les
                }
                $jBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $st -Depth 8 -Compress))
                Send-HttpResponse $stream 200 "OK" "application/json; charset=utf-8" $jBytes
            }
            elseif ($method -eq "POST" -and $path -eq "/api/config") {
                $reqObj = ConvertFrom-Json -InputObject $bodyStr
                $newMode = if ($reqObj.mode -in @("off", "eco", "full")) { [string]$reqObj.mode } else { "eco" }
                $updated = Set-SenOfficeConfig -Workspace $resolvedWs -Mode $newMode -Port $usePort
                $jBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $updated -Compress))
                Send-HttpResponse $stream 200 "OK" "application/json; charset=utf-8" $jBytes
            }
            elseif ($method -eq "POST" -and $path -eq "/api/clear") {
                Clear-SenOfficeEvents -Workspace $resolvedWs
                $jBytes = [System.Text.Encoding]::UTF8.GetBytes('{"cleared":true}')
                Send-HttpResponse $stream 200 "OK" "application/json; charset=utf-8" $jBytes
            }
            else {
                $nf = [System.Text.Encoding]::UTF8.GetBytes('{"error":"not found"}')
                Send-HttpResponse $stream 404 "Not Found" "application/json; charset=utf-8" $nf
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

