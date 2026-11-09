# tests/run.ps1
# ASCII-only test runner for PowerShell 5.1+

$ErrorActionPreference = "Continue"
if (-not (Get-Command powershell -ErrorAction SilentlyContinue) -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Set-Alias -Name powershell -Value (Get-Command pwsh).Source -Scope Global
}

$global:TotalTests = 0
$global:PassedTests = 0
$global:FailedTests = 0

. "$PSScriptRoot/Assert.ps1"

$testFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.Tests.ps1" | Sort-Object Name)

if ($testFiles.Count -eq 0) {
    Write-Host "ERROR: No test files found in $PSScriptRoot" -ForegroundColor Red
    exit 1
}

Write-Host "Running $($testFiles.Count) test file(s)..."

foreach ($file in $testFiles) {
    Write-Host "`n[$($file.Name)]" -ForegroundColor Cyan
    try {
        . $file.FullName
    }
    catch {
        $global:FailedTests++
        Write-Host "  FAIL: $($file.Name) execution failed" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n----------------------------------------"
Write-Host "Test Results: $($global:PassedTests) passed, $($global:FailedTests) failed ($($global:TotalTests) total)"

if ($global:TotalTests -le 0) {
    Write-Host "ERROR: Zero assertions were executed." -ForegroundColor Red
    exit 1
}

if ($global:FailedTests -gt 0) {
    exit 1
}
exit 0
