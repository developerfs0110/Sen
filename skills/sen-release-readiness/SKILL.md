---
name: sen-release-readiness
description: Runs an 8-domain pre-release audit in parallel (Security, Legal/VN Law, App Store, Licenses, Accessibility, Performance, SEO, Operations) and aggregates PASS/WARN/BLOCK verdicts. Trigger when user says "kiểm tra trước phát hành", "chuẩn bị phát hành", or "release readiness".
---

# `sen-release-readiness` — 8-Domain Parallel Pre-Release Audit

## When to Trigger
- The user asks to check if a project is ready for release, production deployment, or store submission (e.g., **"kiểm tra trước phát hành"**, **"chuẩn bị phát hành"**, **"kiểm tra phát hành"**, **"release readiness"**, **"pre-release audit"**).
- Before cutting a release at the end of a **Tier 3** project or when required by a project's `AGENTS.md`.

## Language & Execution Rules
- Present the final aggregated report in the **user's language** (from `.agents/rules/profile.md` if set, otherwise match the language the user writes in).
- Because all 8 audit domains are read-only inspections and independent of one another, follow **`dispatching-parallel-agents`** to run the applicable domain checks concurrently using read-only Reviewer subagents (`inherit` or `pro` for Security/Legal, `flash` or `inherit` for checklist domains) and merge their results into one table.

---

## Step-by-Step Workflow

### Step 1: Determine Scope & Applicable Domains
Inspect the project root (e.g., `package.json`, `plugin.json`, `pyproject.toml`, `pubspec.yaml`, `AndroidManifest.xml`, `Info.plist`, `README.md`) to identify what kind of artifact is being released. All 8 domains must appear in the final report table; domains that do not apply to the project type (for example, App Store for a CLI tool or SEO for a local backend script) are recorded as `PASS (N/A)` with a 1-line reason.

| # | Domain | Skill or Checklist Used | When Applicable |
|---|---|---|---|
| 1 | **Security** (*Bảo mật*) | **`security-audit`** skill | Always applicable |
| 2 | **Legal & Compliance (VN)** (*Pháp lý*) | **`vn-law-check`** skill (if installed) | Always checked (see Step 2 rule if not installed) |
| 3 | **App Store / Play Store** (*Kho ứng dụng*) | [checklists/app-store.md](checklists/app-store.md) | Mobile / desktop store apps (`PASS (N/A)` otherwise) |
| 4 | **Open-Source Licenses** (*Giấy phép thư viện*) | [checklists/licenses.md](checklists/licenses.md) | Always applicable |
| 5 | **Accessibility (a11y)** (*Khả năng tiếp cận*) | [checklists/accessibility.md](checklists/accessibility.md) | Projects with UI/HTML/CLI human output (`PASS (N/A)` for headless libraries) |
| 6 | **Performance & Bundle Size** (*Hiệu năng*) | [checklists/performance.md](checklists/performance.md) | Always applicable |
| 7 | **SEO & Web Metadata** (*SEO & Metadata*) | [checklists/seo.md](checklists/seo.md) | Public web pages / docs sites (`PASS (N/A)` otherwise) |
| 8 | **Operations, Monitoring & Backup** (*Vận hành & Sao lưu*) | [checklists/operations.md](checklists/operations.md) | Always applicable |

---

### Step 2: Dispatch Parallel Domain Audits (`dispatching-parallel-agents`)
Following **`dispatching-parallel-agents`**, dispatch independent read-only checks in parallel across the applicable domains:

1. **Domain 1 — Security (`security-audit`):**
   - Invoke the installed **`security-audit`** skill (at `<WORKSPACE>/.agents/skills/security-audit/SKILL.md`).
   - Check for hardcoded secrets/API keys, injection vectors, authentication/authorization flaws, insecure file/command handling, and vulnerable dependencies.
   - Any critical/high vulnerability or leaked secret is `BLOCK`; medium/low hardening suggestions are `WARN`; clean is `PASS`.
2. **Domain 2 — Legal & Compliance (`vn-law-check`):**
   - Check whether **`vn-law-check`** is installed at `<WORKSPACE>/.agents/skills/vn-law-check/SKILL.md` (or `<WORKSPACE>/.agents/plugins/vn-law-check/`).
   - **If installed:** First run `Invoke-SenVnLawScan -Path "<PROJECT_ROOT>"` (PowerShell parity with `scripts/scan.sh`) to determine the Triage Level (`0..3`), applicable checklists (`01..09`), and code-level red flags (`CodeRedFlags`). Then invoke `vn-law-check` (`references/00-triage.md`) to audit compliance against current Vietnamese laws (**Luật Bảo vệ DLCN 91/2025/QH15 & Nghị định 356/2025/NĐ-CP** replacing expired NĐ 13/2023; **Luật TMĐT 122/2025/QH15 & NĐ 248/2026/NĐ-CP** replacing expired NĐ 52/2013 & 85/2021; **Luật An ninh mạng 116/2025/QH15**; **Luật Trí tuệ nhân tạo 134/2025/QH15 & NĐ 142/2026/NĐ-CP**). Any 🔴 code-level violation or expired law citation is `BLOCK`; 🟡 procedural/paperwork items are `WARN`; 🟢/⚪ is `PASS`.
   - **If NOT installed:** Do not guess legal compliance and do not fail silently. Record the exact status:
     `WARN: legal check not run, vn-law-check not installed`
     (and include a 1-line note showing how to install `vn-law-check` if the project needs Vietnamese regulatory compliance).
3. **Domains 3 to 8 — Checklist Domains:**
   - For each applicable domain, evaluate every `- [ ]` item in its checklist file:
     - [checklists/app-store.md](checklists/app-store.md)
     - [checklists/licenses.md](checklists/licenses.md)
     - [checklists/accessibility.md](checklists/accessibility.md)
     - [checklists/performance.md](checklists/performance.md)
     - [checklists/seo.md](checklists/seo.md)
     - [checklists/operations.md](checklists/operations.md)
   - Cite concrete files/lines or command output for each finding.
   - If any item marked **`[BLOCK]`** fails, the domain verdict is **`BLOCK`**.
   - Otherwise, if one or more items marked **`[WARN]`** fail, the domain verdict is **`WARN`**.
   - If all applicable items pass, the domain verdict is **`PASS`**.

---

### Step 3: Aggregate into One `PASS / WARN / BLOCK` Report
Combine the findings from all 8 domains into a single unified release-readiness report in the user's language:

```markdown
## Release Readiness Report / Báo cáo kiểm tra trước phát hành

| # | Domain | Verdict (`PASS` / `WARN` / `BLOCK`) | Key Findings & Evidence |
|---|---|---|---|
| 1 | Security (`security-audit`) | PASS / WARN / BLOCK | ... |
| 2 | Legal & Compliance (`vn-law-check`) | PASS / WARN / BLOCK | e.g., `WARN: legal check not run, vn-law-check not installed` |
| 3 | App Store / Play Store | PASS / WARN / BLOCK | ... |
| 4 | Open-Source Licenses | PASS / WARN / BLOCK | ... |
| 5 | Accessibility (a11y) | PASS / WARN / BLOCK | ... |
| 6 | Performance & Bundle Size | PASS / WARN / BLOCK | ... |
| 7 | SEO & Web Metadata | PASS / WARN / BLOCK | ... |
| 8 | Operations, Monitoring & Backup | PASS / WARN / BLOCK | ... |
```

### Step 4: State the Final Release Decision Clearly
Immediately below the summary table, state the overall verdict using these exact rules:

- **If ANY domain has `BLOCK`:**
  - Conclude explicitly: **"Chưa sẵn sàng phát hành"** (Vietnamese) / **"Not ready for release"** (English).
  - List every `BLOCK` item with clickable file/line links (`file:///...#L10-L20`) and the exact fix required to clear the blocker.
- **If NO domain has `BLOCK`, but one or more domains have `WARN`:**
  - Conclude: **"Sẵn sàng phát hành kèm lưu ý (`WARN`)"** / **"Ready for release with warnings (`WARN`)"**.
  - List the `WARN` items so the user can decide whether to fix them now or track them for a follow-up update.
- **If all 8 domains are `PASS` (or `PASS (N/A)`):**
  - Conclude: **"Sẵn sàng phát hành (`PASS`)"** / **"Ready for release (`PASS`)"**.
