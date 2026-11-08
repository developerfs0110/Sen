# scripts/Sen.Legal.psm1
# Native PowerShell Vietnamese Web & Mobile App Legal Compliance Scanner (ASCII only).
# Implements 100% signal parity with mhfed/vn-law-check scripts/scan.sh and references/00-triage.md.

$ErrorActionPreference = 'Stop'

function Get-SenVnLawCandidateFiles {
    param([string]$RootPath)
    $validExts = @(
        '.html', '.htm', '.js', '.mjs', '.cjs', '.jsx', '.ts', '.tsx', '.vue', '.svelte',
        '.astro', '.php', '.py', '.rb', '.erb', '.liquid', '.twig', '.json', '.toml',
        '.yml', '.yaml', '.dart', '.kt', '.kts', '.java', '.swift', '.m', '.mm',
        '.gradle', '.xml', '.plist', '.md'
    )
    $skipDirRe = '^(?i)(\.git|node_modules|dist|build|out|\.next|\.nuxt|\.svelte-kit|vendor|coverage|\.vn-law-check|Pods|\.dart_tool|\.gradle|DerivedData|\.expo|\.agents.*|\.sen-backup|\.sen-restore|\.superpowers|\.gemini|\.claude|\.cursor|Antigravity IDE|tests|test|__tests__|docs|skills|rules)$'
    $filtered = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($RootPath)
    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        foreach ($d in @(Get-ChildItem -LiteralPath $cur -Directory -ErrorAction SilentlyContinue)) {
            if ($d.Name -notmatch $skipDirRe) { $queue.Enqueue($d.FullName) }
        }
        foreach ($f in @(Get-ChildItem -LiteralPath $cur -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '(?i)(package-lock\.json|\.lock$|\.min\.js$|^(README(\.[a-z]+)?|CHANGELOG|INSTALL|CONTRIBUTING|CODE_OF_CONDUCT|SECURITY|LICENSE)\.md$)') { continue }
            if ($validExts -contains $f.Extension.ToLowerInvariant() -or $f.Name -in @('Podfile', '.env.example', 'AndroidManifest.xml', 'Info.plist')) {
                $filtered.Add($f)
            }
        }
    }
    return , @($filtered.ToArray())
}

function Get-SenVnLawSignalRules {
    return @(
        [pscustomobject]@{ Name = 'FORM'; Limit = 3; Regex = '(?i)(<form[\s>]|jsxs?\("form"|createElement\("form"|formspree\.io|getform\.io|data-netlify=|docs\.google\.com/forms|type\s*=\s*["'']email["'']|type:\s*["'']email["'']|keyboardType\s*=\s*["''](email-address|phone-pad)["'']|textContentType\s*=\s*["''](emailAddress|telephoneNumber)["'']|TextInputType\.(emailAddress|phone))' },
        [pscustomobject]@{ Name = 'TRACKING'; Limit = 3; Regex = '(?i)(gtag\(|googletagmanager\.com|google-analytics\.com|fbq\(|connect\.facebook\.net|analytics\.tiktok\.com|clarity\.ms|hotjar|cdn\.segment\.com|plausible\.io|umami)' },
        [pscustomobject]@{ Name = 'COMMERCE'; Limit = 3; Regex = '(?i)(add[-_ ]?to[-_ ]?cart|addToCart|/checkout|/cart["''/]|gi\u1ecf\s+h\u00e0ng|gio\s+hang|th\u00eam\s+v\u00e0o\s+gi\u1ecf|them\s+vao\s+gio|mua\s+ngay|\u0111\u1eb7t\s+h\u00e0ng|\u0111\u1eb7t\s+mua|thanh\s+to\u00e1n|vnpay|momo|zalopay|"stripe"|stripe\.com|paypal|woocommerce|shopify)' },
        [pscustomobject]@{ Name = 'AUTH'; Limit = 3; Regex = '(?i)(/login|/register|/signin|/signup|sign[-_ ]?in|\u0111\u0103ng\s+nh\u1eadp|dang\s+nhap|next-auth|nextauth|firebase/auth|supabase\.auth|passport|@clerk|auth0)' },
        [pscustomobject]@{ Name = 'MARKETPLACE'; Limit = 3; Regex = '(?i)(multi[-_ ]?vendor|seller[-_ ]?(dashboard|register|signup|onboard)|vendor[-_ ]?(dashboard|register)|ng\u01b0\u1eddi\s+b\u00e1n|k\u00eanh\s+ng\u01b0\u1eddi\s+b\u00e1n|\u0111\u0103ng\s+k\u00fd\s+b\u00e1n\s+h\u00e0ng)' },
        [pscustomobject]@{ Name = 'AI'; Limit = 3; Regex = '(?i)(api\.openai\.com|"openai"|@anthropic-ai|api\.anthropic\.com|@ai-sdk|generativelanguage\.googleapis|@google/generative-ai|dialogflow|langchain|chatbot)' },
        [pscustomobject]@{ Name = 'PERMISSIONS'; Limit = 10; Regex = '(?i)(android\.permission\.(ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|ACCESS_BACKGROUND_LOCATION|READ_CONTACTS|WRITE_CONTACTS|CAMERA|RECORD_AUDIO|READ_SMS|RECEIVE_SMS|READ_CALL_LOG|READ_PHONE_STATE|READ_MEDIA_IMAGES|READ_MEDIA_VIDEO|READ_EXTERNAL_STORAGE|BODY_SENSORS|ACTIVITY_RECOGNITION)|NS(LocationWhenInUse|LocationAlways|LocationAlwaysAndWhenInUse|Contacts|Camera|Microphone|PhotoLibrary|PhotoLibraryAdd|UserTracking|HealthShare|HealthUpdate|SpeechRecognition|Motion)UsageDescription|"(ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|ACCESS_BACKGROUND_LOCATION|READ_CONTACTS|CAMERA|RECORD_AUDIO|READ_SMS)")' },
        [pscustomobject]@{ Name = 'SDK_TRACKING'; Limit = 3; Regex = '(?i)(firebase_analytics|@react-native-firebase/analytics|firebase-analytics|FirebaseAnalytics|react-native-fbsdk|facebook_app_events|FBSDKCoreKit|com\.facebook\.android|appsflyer|react-native-adjust|com\.adjust\.sdk|adjust_sdk|react-native-branch|io\.branch|mixpanel|amplitude|@segment/analytics-react-native|AppTrackingTransparency|app_tracking_transparency|react-native-tracking-transparency)' },
        [pscustomobject]@{ Name = 'ADS_SDK'; Limit = 3; Regex = '(?i)(google_mobile_ads|react-native-google-mobile-ads|play-services-ads|Google-Mobile-Ads-SDK|GoogleMobileAds|applovin|unity-ads|unity_ads|ironsource|admob)' },
        [pscustomobject]@{ Name = 'FOREIGN_HOST'; Limit = 3; Regex = '(?i)(amazonaws\.com|cloudfront\.net|firebaseio\.com|firebase\.json|"firebase"|firebase/firestore|vercel|netlify|wrangler|cloudflare|herokuapp|fly\.io|render\.com|azurewebsites)' },
        [pscustomobject]@{ Name = 'BOT_FORWARDING'; Limit = 5; Regex = '(?i)(\bforwardMessage\s*\(|\bcopyMessage\s*\(|message:photo|message:document|\bbot\.on\s*\(\s*[\[''"]message)'; OnlyExts = @('.js', '.mjs', '.cjs', '.jsx', '.ts', '.tsx', '.py', '.php', '.rb', '.go', '.java', '.kt', '.dart'); ExcludeLine = '^\s*(//|#|/\*|\*)' },
        [pscustomobject]@{ Name = 'EXPIRED_LAW_REF'; Limit = 5; Regex = '(?i)(ngh\u1ecb\s+\u0111\u1ecbnh\s+(s\u1ed1\s+)?(13/2023|52/2013|85/2021)|n\u0111\s*(13/2023|52/2013|85/2021)|nghi\s+dinh\s+(13/2023|52/2013|85/2021)|decree\s+(no\.?\s*)?(13/2023|52/2013|85/2021))'; ExcludeLine = '(?i)(expired|h\u1ebft\s+hi\u1ec7u\s+l\u1ef1c|het\s+hieu\s+luc|thay\s+th\u1ebf|thay\s+the|replaces|replacing|never\s+cite|kh\u00f4ng\s+d\u1eabn)' }
    )
}

function Find-SenVnLawPatternHits {
    param(
        [array]$FileEntries,
        [string]$Regex,
        [int]$Limit = 3,
        [string[]]$OnlyExtensions = @(),
        [string]$ExcludeLineRegex = ""
    )
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $FileEntries) {
        if ($OnlyExtensions.Count -gt 0 -and ($OnlyExtensions -notcontains $entry.Ext)) { continue }
        $fileHit = $false
        for ($i = 0; $i -lt $entry.Lines.Count; $i++) {
            $ln = $entry.Lines[$i]
            if ($ExcludeLineRegex -and ($ln -match $ExcludeLineRegex)) { continue }
            $m = [regex]::Match($ln, $Regex)
            if ($m.Success) {
                $fileHit = $true
                $snippet = $m.Value
                if ($snippet.Length -gt 120) { $snippet = $snippet.Substring(0, 120) }
                $hits.Add("$($entry.RelPath):$($i + 1):$snippet")
                if ($hits.Count -ge $Limit) { return , @($hits.ToArray()) }
            }
        }
        if (-not $fileHit -and -not [string]::IsNullOrWhiteSpace($entry.Raw) -and ($Regex -match '<script')) {
            $mRaw = [regex]::Match($entry.Raw, "(?s)$Regex")
            if ($mRaw.Success -and (-not $ExcludeLineRegex -or $mRaw.Value -notmatch $ExcludeLineRegex)) {
                $snippet = ($mRaw.Value -replace '\s+', ' ').Trim()
                if ($snippet.Length -gt 120) { $snippet = $snippet.Substring(0, 120) }
                $hits.Add("$($entry.RelPath):1:$snippet")
                if ($hits.Count -ge $Limit) { return , @($hits.ToArray()) }
            }
        }
    }
    return , @($hits.ToArray())
}

function Get-SenVnLawMobilePlatforms {
    param([array]$FileEntries)
    $platforms = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $FileEntries) {
        if ($entry.Name -eq 'pubspec.yaml' -and -not $platforms.Contains('Flutter')) { $platforms.Add('Flutter') }
        if ($entry.Name -eq 'AndroidManifest.xml' -and -not $platforms.Contains('Android')) { $platforms.Add('Android') }
        if ($entry.Name -eq 'Info.plist' -and -not $platforms.Contains('iOS')) { $platforms.Add('iOS') }
        if ($entry.Name -eq 'package.json') {
            if ($entry.Raw -match '"react-native"' -and -not $platforms.Contains('React-Native')) { $platforms.Add('React-Native') }
            if ($entry.Raw -match '"expo"' -and -not $platforms.Contains('Expo')) { $platforms.Add('Expo') }
        }
    }
    return , @($platforms.ToArray())
}

function Resolve-SenVnLawChecklistsAndRedFlags {
    param(
        [hashtable]$Found,
        [string]$ConsentState,
        [bool]$IsMobileApp,
        [bool]$HasAccountDelete,
        [bool]$HasBotConsent = $true,
        [int]$Level
    )
    $checklists = [System.Collections.Generic.List[string]]::new()
    if ($Level -eq 1) {
        $checklists.Add('01-personal-data-protection.md (A, B, C)')
        if ($Found['FOREIGN_HOST']) { $checklists.Add('01-personal-data-protection.md (D - cross-border transfer)') }
    }
    elseif ($Level -eq 2) {
        $checklists.Add('01-personal-data-protection.md')
        $checklists.Add('02-ecommerce.md')
        $checklists.Add('04-consumer-protection.md')
        $checklists.Add('06-electronic-transactions.md')
    }
    elseif ($Level -ge 3) {
        for ($c = 1; $c -le 8; $c++) { $checklists.Add(("0{0}" -f $c)) }
    }
    if ($Found['AI']) { $checklists.Add('07-ai-transparency.md') }
    if ($IsMobileApp) { $checklists.Add('09-mobile-app.md') }

    $redFlags = [System.Collections.Generic.List[object]]::new()
    if ($Found['TRACKING'] -and $ConsentState -eq 'static') {
        $redFlags.Add([pscustomobject]@{
                Code     = 'TRACKING_PRELOAD_WITHOUT_CONSENT'
                Severity = 'red'
                LawRef   = 'Luat 91/2025/QH15 Dieu 9, Khoan 8 Dieu 28 & ND 356/2025/ND-CP Dieu 4, 6'
                Message  = 'Tracking script loads statically in HTML before user consent (01-C).'
            })
    }
    if ($IsMobileApp -and $Found['AUTH'] -and (-not $HasAccountDelete)) {
        $redFlags.Add([pscustomobject]@{
                Code     = 'MOBILE_AUTH_MISSING_ACCOUNT_DELETE'
                Severity = 'red'
                LawRef   = 'Luat 91/2025/QH15 Dieu 4 & Checklist 09-mobile-app.md (Muc C)'
                Message  = 'Mobile app has authentication (AUTH) but no account deletion flow (ACCOUNT_DELETE) was detected.'
            })
    }
    if ($Found['BOT_FORWARDING'] -and (-not $HasBotConsent)) {
        $redFlags.Add([pscustomobject]@{
                Code     = 'BOT_DATA_FORWARDING_WITHOUT_CONSENT'
                Severity = 'red'
                LawRef   = 'Luat 91/2025/QH15 Dieu 9, 11 & ND 356/2025/ND-CP Dieu 4, 6'
                Message  = 'Bot/Backend collects and forwards user messages, account IDs, or receipt photos without privacy notice or user consent logging.'
            })
    }
    if ($Found['EXPIRED_LAW_REF']) {
        $redFlags.Add([pscustomobject]@{
                Code     = 'EXPIRED_VIETNAM_LAW_CITATION'
                Severity = 'red'
                LawRef   = 'ND 356/2025/ND-CP (thay ND 13/2023) & Luat TMDT 122/2025 + ND 248/2026 (thay ND 52/2013, 85/2021)'
                Message  = 'Code or policy cites expired decrees (ND 13/2023, ND 52/2013, or ND 85/2021).'
            })
    }
    return [pscustomobject]@{
        Checklists = @($checklists.ToArray())
        RedFlags   = @($redFlags.ToArray())
    }
}

function Invoke-SenVnLawScan {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Target path not found: $Path" }
    $resolvedRoot = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
    $files = Get-SenVnLawCandidateFiles -RootPath $resolvedRoot
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/').Replace('\', '/')
        $raw = [System.IO.File]::ReadAllText($f.FullName)
        $entries.Add([pscustomobject]@{ Name = $f.Name; Ext = $f.Extension.ToLowerInvariant(); RelPath = $rel; Raw = $raw; Lines = ($raw -split "\r?\n") })
    }
    $found = @{}; $evidence = [ordered]@{}
    foreach ($rule in (Get-SenVnLawSignalRules)) {
        $excl = if ($rule.PSObject.Properties['ExcludeLine']) { [string]$rule.ExcludeLine } else { "" }
        $onlyExts = if ($rule.PSObject.Properties['OnlyExts']) { @($rule.OnlyExts) } else { @() }
        $hits = Find-SenVnLawPatternHits -FileEntries $entries -Regex $rule.Regex -Limit $rule.Limit -OnlyExtensions $onlyExts -ExcludeLineRegex $excl
        $found[$rule.Name] = ($hits.Count -gt 0); $evidence[$rule.Name] = $hits
    }
    $consentState = 'none'
    if ($found['TRACKING']) {
        $staticRe = '(?i)<script[^>]*src\s*=\s*["''][^"'']*(googletagmanager\.com|google-analytics\.com|connect\.facebook\.net|analytics\.tiktok\.com|clarity\.ms|hotjar|cdn\.segment\.com)'
        $gateRe = '(?i)(cookiebot|onetrust|cookieyes|cookie-script\.com|klaro|iubenda|osano|termly|complianz|cookieconsent|gtag\(\s*["'']consent["'']|ad_storage["'']?\s*:\s*["'']denied|data-cookieconsent|data-category\s*=\s*["''](analytics|marketing)|cookie[_-]?consent|consent[_-]?(given|granted|accepted)|\u0111\u1ed3ng\s+\u00fd\s+cookie|ch\u1ea5p\s+nh\u1eadn\s+cookie)'
        $staticHits = Find-SenVnLawPatternHits -FileEntries $entries -Regex $staticRe -Limit 3 -OnlyExtensions @('.html', '.htm', '.php', '.liquid') -ExcludeLineRegex '(?i)type\s*=\s*["'']text/plain'
        $gateHits = Find-SenVnLawPatternHits -FileEntries $entries -Regex $gateRe -Limit 3 -ExcludeLineRegex '^\s*(//|#|/\*|\*|<!--)'
        $evidence['TRACKING_PRELOAD'] = $staticHits; $evidence['CONSENT_GATE'] = $gateHits
        if ($staticHits.Count -gt 0 -and $gateHits.Count -eq 0) { $consentState = 'static' }
        elseif ($gateHits.Count -gt 0) { $consentState = 'gated' }
        else { $consentState = 'unknown' }
    }
    $platforms = Get-SenVnLawMobilePlatforms -FileEntries $entries
    $isMobileApp = ($platforms.Count -gt 0)
    $hasAccountDelete = $false
    if ($isMobileApp -and $found['AUTH']) {
        $delHits = Find-SenVnLawPatternHits -FileEntries $entries -Regex '(?i)(delete[-_ ]?account|deleteAccount|deleteUser|x\u00f3a\s+t\u00e0i\s+kho\u1ea3n|xo\u00e1\s+t\u00e0i\s+kho\u1ea3n|account[-_ ]deletion)' -Limit 2 -ExcludeLineRegex '^\s*(//|#|/\*|\*|<!--)'
        $hasAccountDelete = ($delHits.Count -gt 0); $evidence['ACCOUNT_DELETE'] = $delHits
    }
    $privacyConsentRe = '(?i)(privacy[-_ ]?(policy|notice)|ch\u00ednh\s+s\u00e1ch\s+b\u1ea3o\s+m\u1eadt|chinh\s+sach\s+bao\s+mat|b\u1ea3o\s+v\u1ec7\s+d\u1eef\s+li\u1ec7u\s+c\u00e1\s+nh\u00e2n|bao\s+ve\s+du\s+lieu\s+ca\s+nhan|consent[_-]?(log|given|granted|record|gate)|cookie[_-]?consent|\u0111\u1ed3ng\s+\u00fd\s+(x\u1eed\s+l\u00fd|chia\s+s\u1ebb|chuy\u1ec3n\s+ti\u1ebfp|cookie)|dong\s+y\s+(xu\s+ly|chia\s+se|chuyen\s+tiep|cookie)|356/2025|91/2025)'
    $privacyConsentHits = Find-SenVnLawPatternHits -FileEntries $entries -Regex $privacyConsentRe -Limit 3
    $hasPrivacyConsent = ($privacyConsentHits.Count -gt 0)
    $hasBotConsent = $true
    if ($found['BOT_FORWARDING']) {
        $hasBotConsent = $hasPrivacyConsent; $evidence['BOT_CONSENT'] = $privacyConsentHits
    }
    $level = 0
    if ($found['AUTH'] -and $found['MARKETPLACE']) { $level = 3 }
    elseif ($found['COMMERCE']) { $level = 2 }
    elseif ($found['FORM'] -or $found['TRACKING'] -or $found['AUTH'] -or $found['AI'] -or $found['PERMISSIONS'] -or $found['SDK_TRACKING'] -or $found['ADS_SDK'] -or $found['BOT_FORWARDING']) { $level = 1 }
    $eval = Resolve-SenVnLawChecklistsAndRedFlags -Found $found -ConsentState $consentState -IsMobileApp $isMobileApp -HasAccountDelete $hasAccountDelete -HasBotConsent $hasBotConsent -Level $level
    $scopeStatus = if ($level -eq 0 -and $eval.RedFlags.Count -eq 0 -and $eval.Checklists.Count -eq 0 -and $consentState -eq 'none') { 'NOT_APPLICABLE' } else { 'APPLICABLE' }
    $verdict = if ($eval.RedFlags.Count -gt 0) { 'FAIL' } elseif ($scopeStatus -eq 'NOT_APPLICABLE') { 'PASS' } elseif ($consentState -eq 'unknown' -or (-not $hasPrivacyConsent)) { 'UNKNOWN' } else { 'PASS' }
    $codeCompliant = ($eval.RedFlags.Count -eq 0) -and ($verdict -in @('PASS', 'NOT_APPLICABLE'))
    return [pscustomobject]@{
        Path = $resolvedRoot; Level = [int]$level; ScopeStatus = $scopeStatus; AI = [bool]$found['AI']; ForeignHost = [bool]$found['FOREIGN_HOST']
        MobileApp = [bool]$isMobileApp; MobilePlatforms = $platforms; TrackingConsent = $consentState; AccountDelete = [bool]$hasAccountDelete
        BotForwarding = [bool]$found['BOT_FORWARDING']; BotConsent = [bool]$hasBotConsent
        Signals = [pscustomobject]$found; Evidence = [pscustomobject]$evidence
        RequiredChecklists = $eval.Checklists; CodeRedFlags = $eval.RedFlags; CompliantCodeLevel = [bool]$codeCompliant
        Passed = [bool]$codeCompliant; Verdict = $verdict; LawCatalogVersion = '2026.11'; EffectiveDate = '2026-01-01'
        LegalDisclaimer = 'Static code scan only; does not replace human legal audit.'
    }
}

Export-ModuleMember -Function Invoke-SenVnLawScan
