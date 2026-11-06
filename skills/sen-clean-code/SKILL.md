---
name: sen-clean-code
description: Audits codebase health (800-line/45KB logic threshold, 1500-line UI threshold, 1000-line test threshold), creates restore points, and performs behavior-preserving modularization, deduplication, and hot-path optimization. Trigger on "clean code", "tối ưu code", or "dọn dẹp mã nguồn".
---

# `sen-clean-code` — Quantitative Code Health Audit & Behavior-Preserving Optimization

## When to Trigger
- When the user says **"tối ưu code"**, **"clean code"**, **"dọn dẹp mã nguồn"**, **"refactor code"**, or **"kiểm tra sức khỏe code"**.
- Proactively suggested (as a 1-line tip at the end of a Tier 2/3 handover report) when `Measure-SenCodeHealth` detects files exceeding single-read thresholds.
- Applies equally to **user projects** (TypeScript/JavaScript, Python, PowerShell, C#, Go, HTML/CSS/Vue) and to **Sen itself (`sen-method`)**.

---

## Why the 3-Tier Thresholds (`800` / `1500` / `1000` Lines)

Antigravity's `read_file` tool reads at most **800 lines or 46,080 bytes (~45 KB)** per call. Keeping source files within these bounds ensures:
1. **1-Shot Context Reading:** An agent reads the entire module in a single tool call (`1..800`) without losing imports/exports across chunked reads.
2. **High First-Pass Edit Rate:** `edit_file` target matching stays near 100% accuracy and avoids duplicate-block collisions.
3. **Parallel Multi-Agent Unlocking (Tier 3):** Smaller, single-responsibility modules allow Developer A and Developer B to work in parallel without colliding on `allowedPaths` file locks.

| Category | Extensions / Pattern | Max Lines | Max Bytes |
|---|---|---|---|
| **Logic / Module (`logic`)** | `.ps1`, `.psm1`, `.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.cs`, `.go` | **`800` lines** | **`46,080` bytes (45 KB)** |
| **Standalone UI (`ui`)** | `.html`, `.css`, `.vue` | **`1,500` lines** | **`81,920` bytes (80 KB)** |
| **Test Suites (`test`)** | `*.Tests.ps1`, `*.test.*`, `*.spec.*`, `test_*.py`, `*_test.go` | **`1,000` lines** | **`61,440` bytes (60 KB)** |

---

## 5-Step Workflow

### Step 1: Run Quantitative Audit (`Measure-SenCodeHealth`)
Before proposing any change, run the zero-token health scanner on the target project root:

```powershell
Import-Module "<WORKSPACE>/.agents/plugins/sen-method/scripts/Sen.psm1" -Force
$beforeHealth = Measure-SenCodeHealth -Path "<PROJECT_ROOT>"
$beforeHealth | ConvertTo-Json -Depth 5
```

Inspect `$beforeHealth.OversizedFiles`, `$beforeHealth.TodoCount`, and `$beforeHealth.Score`, then check for:
1. **God-files (`OversizedFiles`)** that combine multiple responsibilities in a single file.
2. **Duplicate code blocks (DRY violations)** where 2+ functions repeat the same I/O, validation, or API logic.
3. **Hot-path / Hook bottlenecks** where startup scripts or event handlers eagerly load heavy modules they rarely use.
4. **Dead code or leftover temporary folders** (never use `Remove-Item -Recurse` or `rm -rf` via shell commands; use `.gitignore` or safe file-level cleanup).

---

### Step 2: Confirm the Approach (`[Cấp 2 - Xác nhận phương án]` / `[Tier 2 - Confirming the approach]`)
Present a concise **Before Metrics & Refactoring Plan** table to the user:
- List each file to split or deduplicate, its current line/byte count, and the target module structure.
- State explicitly that **100% of public APIs, exports, and existing tests will remain backward-compatible**.
- Wait for user approval **once** before modifying code (unless the user already said *"làm luôn đi"* / *"triển khai"*).

---

### Step 3: Create an Automatic Restore Point (`New-SenRestorePoint`)
Before editing or splitting any file, snapshot all target files so any regression can be reverted in 1 second:

```powershell
$rp = New-SenRestorePoint -Workspace "<PROJECT_ROOT>" -Files @("path/to/file1", "path/to/file2") -Label "clean-code"
```

---

### Step 4: Execute Behavior-Preserving Refactoring & Verify Gates
1. **Modularize:** Split oversized files by domain responsibility so every resulting file is strictly below its category threshold (`<= 800` lines / `<= 45 KB` for logic files). Re-export symbols from the entry module so existing callers do not break.
2. **Deduplicate (DRY):** Extract shared helpers for repeated JSON/file I/O, network calls, or UI state mappings.
3. **Lazy-Load Hot Paths:** Defer importing heavy modules until the code branch that needs them actually executes.
4. **Run Verification (`verification-before-completion`):**
   - Run the project's full test suite and build/linter (`Test-SenDeliveryGate`).
   - If optimizing Sen itself, run `scripts/Validate-Repo.ps1` and `tests/run.ps1`.
   - If tests fail and cannot be immediately resolved, call `Restore-SenRestorePoint -Workspace "<PROJECT_ROOT>" -Id $rp.Id`.

---

### Step 5: Re-Audit & Present Before/After Report (`sen-delivery-report`)
Re-run `Measure-SenCodeHealth -Path "<PROJECT_ROOT>"` to confirm `$afterHealth.Healthy -eq $true` (`Score = 100`), then include a **Before vs. After** comparison table in the delivery report showing exact line and byte reductions.
