---
name: sen-clean-code
description: Audits codebase health across 6 ISO/IEC 5055, SonarQube, ESLint, Pylint, PSScriptAnalyzer, and AI-Native (800L/45KB) dimensions, creates restore points, and performs behavior-preserving refactoring. Trigger on "clean code", "tối ưu code", or "dọn dẹp mã nguồn".
---

# `sen-clean-code` — 6-Dimension Code Health Audit & Behavior-Preserving Refactoring

## When to Trigger
- When the user says **"tối ưu code"**, **"clean code"**, **"dọn dẹp mã nguồn"**, **"refactor code"**, or **"kiểm tra sức khỏe code"**.
- Proactively suggested (as a 1-line tip at the end of a Tier 2/3 handover report) when `Measure-SenCodeHealth` detects any violation (`Healthy -eq $false`).
- Applies equally to **user projects** (TypeScript/JavaScript, Python, PowerShell, C#, Go, HTML/CSS/Vue) and to **Sen itself (`sen-method`)**.

---

## Reference Standards & 6 Measured Dimensions

`Measure-SenCodeHealth` evaluates codebases objectively (`0-token` static + AST analysis) against **ISO/IEC 5055:2021 (CISQ / MITRE CWE)**, **SonarQube (`SonarWay`)**, **ESLint / Pylint / Microsoft `PSScriptAnalyzer`**, and **AI-Native Single-Read limits**:

| # | Dimension (`Measure-SenCodeHealth` Property) | Threshold | ISO/IEC 5055 & CWE | SonarQube / ESLint / Pylint / PSScriptAnalyzer |
|---|---|---|---|---|
| **1** | **`OversizedFiles`** *(File Size & 1-Shot Readability)* | Logic $\le 800\text{L}/45\text{KB}$, UI $\le 1500\text{L}/80\text{KB}$, Test $\le 1000\text{L}/60\text{KB}$ | **CWE-1080** | Sonar **`S104`** · ESLint **`max-lines`** · Pylint **`C0302`** · Antigravity `read_file` 1-shot limit |
| **2** | **`LongFunctions`** *(Function Length)* | $\le 100$ lines per function | **CWE-1064** | Sonar **`S138`** · ESLint **`max-lines-per-function`** · Pylint **`R0915`** |
| **3** | **`DeepNesting`** *(Control-Flow Nesting / Arrow Anti-Pattern)* | $\le 4$ nested control-flow levels (`if/for/while/switch/try`) | **CWE-1121** | Sonar **`S134`** & **`S3776`** *(Cognitive Complexity)* · ESLint **`max-depth`** · Pylint **`R1702`** |
| **4** | **`DuplicateBlocks`** *(DRY / Copy-Paste Detection)* | $0$ duplicated $\ge 8$-line substantive blocks across files | **CWE-1041** | Sonar **`common:DuplicatedBlocks` (CPD)** · Pylint **`R0801`** · `jscpd` |
| **5** | **`EmptyCatches`** *(Silent Exception Swallowing)* | $0$ bare `catch {}` blocks without handling or rationale comment | **CWE-1069** / **CWE-390** | Sonar **`S108`** & **`S2486`** · ESLint **`no-empty`** · Microsoft **`PSAvoidUsingEmptyCatchBlock`** |
| **6** | **`DeadFunctions`** *(Unused Internal Functions)* | $0$ unreferenced, unexported internal functions | **CWE-561** | Sonar **`S1144`** · ESLint **`no-unused-vars`** · Roslyn **`IDE0051`** |

---

## 5-Step Workflow

### Step 1: Run Quantitative 6-Dimension Audit (`Measure-SenCodeHealth`)
Before proposing any change, run the zero-token analyzer on the target project root:

```powershell
Import-Module "<WORKSPACE>/.agents/plugins/sen-method/scripts/Sen.psm1" -Force
$beforeHealth = Measure-SenCodeHealth -Path "<PROJECT_ROOT>"
$beforeHealth | ConvertTo-Json -Depth 5
```

Inspect all 6 arrays (`OversizedFiles`, `LongFunctions`, `DeepNesting`, `DuplicateBlocks`, `EmptyCatches`, `DeadFunctions`) plus `TodoCount` and `Score`.

---

### Step 2: Confirm the Approach (`[Cấp 2 - Xác nhận phương án]` / `[Tier 2 - Confirming the approach]`)
Present a concise **Before Metrics & Refactoring Plan** table to the user:
- List each violation found (with its CWE / SonarQube / Linter rule ID) and how it will be resolved (guard clauses to flatten nesting, helper extraction for long functions/duplicate blocks, module splitting, or explicit error handling).
- State explicitly that **100% of public APIs, exports, and existing tests will remain backward-compatible**.
- Wait for user approval **once** before modifying code (unless the user already said *"làm đi"* / *"triển khai"*).

---

### Step 3: Create an Automatic Restore Point (`New-SenRestorePoint`)
Before editing or splitting any file, snapshot all target files so any regression can be reverted in 1 second:

```powershell
$rp = New-SenRestorePoint -Workspace "<PROJECT_ROOT>" -Files @("path/to/file1", "path/to/file2") -Label "clean-code"
```

---

### Step 4: Execute Behavior-Preserving Refactoring & Verify Gates
1. **Modularize (`CWE-1080` / `S104`):** Split oversized files by domain responsibility (`<= 800` lines / `<= 45 KB` for logic files) and re-export symbols for backward compatibility.
2. **Decompose Long Functions & Flatten Nesting (`CWE-1064`, `CWE-1121` / `S138`, `S134`):** Use guard clauses (`if (-not $ok) { return }`) and focused helper functions so every function is `<= 100` lines and `maxNesting <= 4`.
3. **Eliminate Clones (`CWE-1041` / `CPD`):** Extract shared I/O, validation, or transaction helpers.
4. **Fix Silent Catches & Remove Dead Code (`CWE-1069`, `CWE-561`):** Handle or document intentional fallback `catch` blocks and remove unused internal functions.
5. **Run Verification (`verification-before-completion`):**
   - Run the project's test suite and build/linter (`Test-SenDeliveryGate`).
   - If tests fail and cannot be immediately resolved, call `Restore-SenRestorePoint -Workspace "<PROJECT_ROOT>" -Id $rp.Id`.

---

### Step 5: Re-Audit & Present Before/After Report (`sen-delivery-report`)
Re-run `Measure-SenCodeHealth -Path "<PROJECT_ROOT>"` to confirm `$afterHealth.Healthy -eq $true` (`Score = 100` across all 6 dimensions), then include a **Before vs. After** table in the delivery report.
