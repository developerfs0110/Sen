# tests/Assert.ps1
# Pure ASCII assertions for PowerShell 5.1+

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string]$Message = ""
    )
    $equal = $false
    if ($null -eq $Expected -and $null -eq $Actual) {
        $equal = $true
    }
    elseif ($null -eq $Expected -or $null -eq $Actual) {
        $equal = $false
    }
    elseif ($Expected -is [System.Collections.IEnumerable] -and $Expected -isnot [string] -and
            $Actual -is [System.Collections.IEnumerable] -and $Actual -isnot [string]) {
        $expArr = @($Expected)
        $actArr = @($Actual)
        if ($expArr.Count -ne $actArr.Count) {
            $equal = $false
        }
        else {
            $equal = $true
            for ($i = 0; $i -lt $expArr.Count; $i++) {
                if ($expArr[$i] -ne $actArr[$i]) {
                    $equal = $false
                    break
                }
            }
        }
    }
    else {
        $equal = ($Expected -eq $Actual)
    }

    if (-not $equal) {
        $expStr = if ($null -eq $Expected) { "<null>" } else { "$Expected" }
        $actStr = if ($null -eq $Actual) { "<null>" } else { "$Actual" }
        $msg = "Assert-Equal failed: expected [$expStr] but got [$actStr]."
        if ($Message) { $msg += " $Message" }
        throw $msg
    }
}

function Assert-True {
    param(
        [bool]$Cond,
        [string]$Message = ""
    )
    if (-not $Cond) {
        $msg = "Assert-True failed: condition was false."
        if ($Message) { $msg += " $Message" }
        throw $msg
    }
}

function Assert-Throws {
    param(
        [scriptblock]$Block,
        [string]$Message = ""
    )
    $threw = $false
    $caught = $null
    try {
        & $Block
    }
    catch {
        $threw = $true
        $caught = $_
    }
    if (-not $threw) {
        $msg = "Assert-Throws failed: expected scriptblock to throw, but it succeeded."
        if ($Message) { $msg += " $Message" }
        throw $msg
    }
    return $caught
}

function Test {
    param(
        [string]$Name,
        [scriptblock]$Block
    )
    if ($null -eq $global:TotalTests) {
        $global:TotalTests = 0
        $global:PassedTests = 0
        $global:FailedTests = 0
    }
    $global:TotalTests++
    try {
        & $Block
        $global:PassedTests++
        Write-Host "  PASS: $Name" -ForegroundColor Green
    }
    catch {
        $global:FailedTests++
        Write-Host "  FAIL: $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    }
}

Set-Alias -Name It -Value Test -ErrorAction SilentlyContinue
