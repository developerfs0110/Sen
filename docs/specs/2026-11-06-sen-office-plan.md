# Sen Office (`v0.2.0`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and ship `sen-office` (`v0.2.0`) inside the `sen-method` repository (`https://github.com/developerfs0110/Sen`), providing a 3D Chibi Isometric AI Office monitor, all 10 governance/UI upgrades inspired by `my-office` (secret redaction, stuck-loop breaker, denied-command cards, read-only Antigravity quota pill, 6-counter agent/place inspector, desk screen states, micro-animations, 3D/2D/Dual-Phase views, streamer mode, and replay scrubber), a zero-dependency local office server, and bilingual documentation.

**Architecture:** `scripts/Sen.psm1` provides ASCII-only PowerShell 5.1 state management under `<WORKSPACE>/.agents/office/` (`config.json`, `events.jsonl`, `loops.json`, `showcase.json`) plus secret redaction and stuck-loop tracking. `hooks.json` wires `PreToolUse` (`scripts/guard.ps1` / `guard.sh`) and `PostToolUse` (`scripts/office-post.ps1` / `office-post.sh`) for zero-token real-time telemetry. `scripts/start-office.ps1` / `start-office.sh` serves `office/index.html` and JSON endpoints (`/api/state`, `/api/config`, `/api/event`, `/api/clear`) on `127.0.0.1:<port>`, while `office/index.html` falls back seamlessly to interactive Demo Mode when opened via `file://`.

**Tech Stack:** Windows PowerShell 5.1+ (ASCII-only `.ps1`/`.psm1`), POSIX `sh`/`bash` + `python3` fallback, standalone HTML5 + SVG Isometric Chibi 3D + CSS3 + Vanilla ES6 JavaScript.

**Spec:** `docs/specs/2026-11-06-sen-office-design.md`

## Global Constraints

- `rules/AGENTS.md` MUST remain `<= 6,000` bytes (LF) and `< 100` lines.
- All `.ps1` and `.psm1` files MUST be 100% ASCII-only (`0` bytes `>= 128`) and pass `scripts/Validate-Repo.ps1 -Root .`.
- Every skill directory under `skills/` MUST start with `sen-` (`skills/sen-office/SKILL.md`), have valid YAML frontmatter (`description <= 300` chars), and stay `<= 12,000` bytes.
- No personal workspace paths (`TUNBH\Workspace` or `d:\TUNBH`) may appear in `rules/`, `skills/`, `templates/`, `scripts/`, `office/`, or `INSTALL.md`.
- Secret strings (`Bearer ...`, `sk-...`, `ghp_...`, `api_key=...`, `password=...`, JWT `eyJ...`, URL `user:pass@`) MUST be redacted to `[REDACTED]` before writing to `.agents/office/events.jsonl`.
- When `.agents/office/config.json` has `mode: "off"`, `Write-SenOfficeEvent` and `office-post.ps1`/`.sh` MUST exit immediately without writing events.

## Review Focus

- `Write-SenOfficeEvent` called when `.agents/office/config.json` is `"off"`: must return `$false` and leave `events.jsonl` untouched/absent.
- Secret redaction on nested command strings containing `Bearer eyJ...`, `sk-proj-1234567890`, `ghp_abcdefghij1234`, and `https://admin:mysecret@example.com`: all secrets must be replaced with `[REDACTED]`.
- Stuck loop breaker (`Test-SenStuckLoop`): 3 consecutive identical failures on the same tool + target must mark `IsStuck = $true` on the 3rd failure and cause `guard.ps1` to return `decision = "deny"` on the 4th attempt, while a successful call or file edit resets the streak.
- `guard.ps1` denying a destructive command (`git push --force` or `write_file` outside `workspacePaths`) when `workspacePaths` is provided: must append a `guard-denied` alert event to `<WORKSPACE>/.agents/office/events.jsonl` (unless office mode is `"off"`).
- `Install-SenSelf` (and `install.sh`): must copy `office/` and the new `scripts/office-post.*` and `scripts/start-office.*` into `<WORKSPACE>/.agents/plugins/sen-method/`.

---

### Task 1: Office State Engine, Secret Redaction, Stuck-Loop Tracker & Quota Reader in `scripts/Sen.psm1`

**Files:**
- Modify: `scripts/Sen.psm1`
- Modify: `scripts/install.sh`
- Create: `tests/Office.Tests.ps1`

**Interfaces:**
- Produces (exported in `scripts/Sen.psm1`):
  - `Protect-SenRedactedText -Text <string>` -> `<string>`
  - `Get-SenOfficeConfig -Workspace <string>` -> `<hashtable>` (`mode`, `port`, `updatedAt`)
  - `Set-SenOfficeConfig -Workspace <string> -Mode <string> [-Port <int>]` -> `<hashtable>`
  - `Write-SenOfficeEvent -Workspace <string> -From <string> -To <string> -Lane <string> -EcoText <string> [-FullText <string>] [-Kind <string>] [-Hold <int>] [-Source <string>] [-Tool <string>] [-Target <string>] [-Command <string>] [-Model <string>]` -> `<bool>`
  - `Read-SenOfficeEvents -Workspace <string> [-Limit <int>]` -> `<object[]>`
  - `Clear-SenOfficeEvents -Workspace <string>` -> `<void>`
  - `Test-SenStuckLoop -Workspace <string> -ToolName <string> -Target <string> [-Failed] [-ErrorText <string>] [-Reset]` -> `<hashtable>` (`IsStuck`, `Streak`, `Key`, `Reason`)
  - `Write-SenOfficeShowcase -Workspace <string> -Showcase <hashtable>` -> `<void>`
  - `Read-SenOfficeShowcase -Workspace <string>` -> `<psobject>`
  - `Get-SenAntigravityQuota` -> `<hashtable>` (`available`, `models`)

- [ ] **Step 1: Write the failing unit tests in `tests/Office.Tests.ps1`**
  Cover `Protect-SenRedactedText`, `Get-SenOfficeConfig` / `Set-SenOfficeConfig`, `Write-SenOfficeEvent` (including `mode = "off"` no-op and 200-line cap), `Test-SenStuckLoop` (3 failures -> stuck, reset on success), and `Write-SenOfficeShowcase` / `Read-SenOfficeShowcase`.
- [ ] **Step 2: Implement the functions in `scripts/Sen.psm1` and update `Install-SenSelf` & `scripts/install.sh` to copy `office`**
- [ ] **Step 3: Run `tests/run.ps1` to verify `Office.Tests.ps1` passes**

---

### Task 2: Wire `PreToolUse` & `PostToolUse` Hooks (`hooks.json`, `guard.ps1`/`.sh`, `office-post.ps1`/`.sh`)

**Files:**
- Modify: `hooks.json`
- Modify: `scripts/guard.ps1`
- Modify: `scripts/guard.sh`
- Create: `scripts/office-post.ps1`
- Create: `scripts/office-post.sh`
- Modify: `scripts/install.sh`
- Modify: `tests/Office.Tests.ps1`

**Interfaces:**
- Consumes: `Protect-SenRedactedText`, `Write-SenOfficeEvent`, `Test-SenStuckLoop`
- Produces:
  - `hooks.json` with both `PreToolUse` and `PostToolUse` hooks
  - `scripts/office-post.ps1` and `scripts/office-post.sh` mapping tool executions to office roles (`r1`, `r2`, `ba`, `fe`, `be`, `qa`, `sec`, `pm`)

- [ ] **Step 1: Add hook tests in `tests/Office.Tests.ps1`**
  Test that `guard.ps1` writes a `guard-denied` alert event to `.agents/office/events.jsonl` when blocking a command, blocks the 4th call when `loops.json` has `streak >= 3`, and `office-post.ps1` records redacted evidence events when `mode != "off"`.
- [ ] **Step 2: Implement `hooks.json`, `scripts/guard.ps1`, `scripts/guard.sh`, `scripts/office-post.ps1`, `scripts/office-post.sh`, and update `scripts/install.sh` hook rewiring**
- [ ] **Step 3: Run `tests/run.ps1` and `bash -n` to verify all hook tests pass**

---

### Task 3: Build `office/index.html` (Chibi 3D Cast + 10 Upgrades + Dual-Phase Visualizer) & Local Office Server (`start-office.ps1`/`.sh`)

**Files:**
- Create: `office/index.html`
- Create: `scripts/start-office.ps1`
- Create: `scripts/start-office.sh`
- Modify: `tests/Office.Tests.ps1`

**Interfaces:**
- Consumes: `<WORKSPACE>/.agents/office/{config.json,events.jsonl,loops.json,showcase.json}`
- Produces:
  - `office/index.html` with Chibi 3D characters (no face ring, floor status rings, 3D shading, blinking eyes, role props), Desk Screen states, Steaming coffee cups, Clickable Props & 6-Counter Agent Inspector, `3D | 2D | Dual-Phase` view switcher, `Tắt | Tiết kiệm | Chi tiết` mode switcher with warning modal & `/api/config` persistence, Denied Command cards with Copy button, Antigravity Quota Pill, Streamer Redact Mode (`🔒`), Night Switch (`🌙`), and Replay Scrubber.
  - `scripts/start-office.ps1` (supports `-DryRun` for testing) and `scripts/start-office.sh`.

- [ ] **Step 1: Add UI and server dry-run assertions to `tests/Office.Tests.ps1`**
- [ ] **Step 2: Create `office/index.html`, `scripts/start-office.ps1`, and `scripts/start-office.sh`**
- [ ] **Step 3: Run `tests/run.ps1` and `bash -n scripts/start-office.sh`**

---

### Task 4: Create `skills/sen-office/SKILL.md`, Update Docs & Release `v0.2.0`

**Files:**
- Create: `skills/sen-office/SKILL.md`
- Modify: `skills/sen-delivery-report/SKILL.md`
- Modify: `plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `README.en.md`
- Modify: `README.vi.md`
- Modify: `docs/huong-dan.md`
- Modify: `docs/guide.md`
- Modify: `tests/Skills.Tests.ps1`

- [ ] **Step 1: Add `sen-office` skill validation assertions to `tests/Skills.Tests.ps1`**
- [ ] **Step 2: Create `skills/sen-office/SKILL.md`, update `skills/sen-delivery-report/SKILL.md`, bump `plugin.json` to `0.2.0`, and update `CHANGELOG.md` and READMEs/guides**
- [ ] **Step 3: Run `scripts/Validate-Repo.ps1 -Root .` and `tests/run.ps1`, commit, push `v0.2.0` to GitHub, sync to `d:\TUNBH\Workspace\.agents\plugins\sen-method\`, and open the live `office/index.html` for the user**

