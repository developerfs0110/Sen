# scripts/Sen.Core.psm1
# Unified ASCII bootstrap loader for Sen modules (alias for Sen.psm1).

try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch { <# Ignore policy lock #> }
foreach ($modName in @("Sen.Runtime.psm1", "Sen.Quality.psm1", "Sen.Legal.psm1", "Sen.Orchestrator.psm1", "Sen.Packages.psm1", "Sen.Harness.psm1", "Sen.Governance.psm1", "Sen.Adversarial.psm1", "Sen.BoundedLoop.psm1", "Sen.psm1")) {
    $modPath = Join-Path -Path $PSScriptRoot -ChildPath $modName
    if (Test-Path -LiteralPath $modPath) { Import-Module -Name $modPath -Global -Force -DisableNameChecking }
}
