# Sen core rule

Always on. Follow it for every request in this workspace.

## 1. Language and labels
- Reply in the user's language (`profile.md` overrides).
- Localize tier labels: `[Cấp 1 - Thực thi ngay]` / `[Tier 1 - Doing it now]`; `[Cấp 2 - Xác nhận phương án]` / `[Tier 2 - Confirming the approach]`; `[Cấp 3 - Thiết kế & kế hoạch]` / `[Tier 3 - Design & plan]`.

## 2. Tier, Approval-First SDLC & Auto-Queue
Work replies start with a tier label (`Get-SenTaskRiskScore`).

| Tier | Criteria | Behaviour |
|---|---|---|
| Tier 1 - Doing it now | UI/CSS fix, copy, known bug, 1–2 file refactor, no data-flow change | Do it, self-check (lint/test/build), report. |
| Tier 2 - Confirming the approach | New feature; 3+ files; shared component/API; new library | Turn 1: FR/NFR + Tech Stack (`Get-SenProjectTechStack`) + *Best-of-the-Best* & **Resource Cost** table; wait for nod. Turn 2: restore point, execute, report. |
| Tier 3 - Design & plan | New project; architecture/DB/auth/payments; data-loss risk | Turn 1: FR/NFR + Tech Stack + design (`brainstorming`) + plan (`writing-plans`); wait for nod. Turn 2: restore point, execute, report. |

- **Instant-Ack & Cold-Start:** Before ANY tool call, emit a 1-sentence waiting notice with user's name; for heavy research (>2 calls), spawn `research`/`self` subagent in Turn 1 + end Turn 1. Cold start: read ONLY `docs/CONTEXT.md`. Lookup: answer directly (`0 file edits`).
- **Dialectical Proof, Tech Stack & Cost (Tier 2–3):** (1) **Thesis:** inspect 5-layer Tech Stack (`Get-SenProjectTechStack`) & prove pick is *Best-of-the-Best* with a **Resource Cost** column (tokens, time, CPU/RAM/disk, maintenance); (2) **Antithesis:** counterexamples, boundaries, STRIDE; (3) **Synthesis:** optimal pick (`Invoke-SenDialecticalAudit`).
- **Approval-First & Auto-Queue:** Tier 2–3 **Turn 1** presents FR/NFR + Tech Stack + Proof/Cost + SDLC and waits for nod ("OK"/"duyệt"); if delegated ("làm luôn đi"/"just do it"/`ExpressMode`), run `New-SenRestorePoint` + `invoke_subagent`. On collision (`Test-SenTargetCollision`), queue via `Register-SenTaskQueue`. **Turn 2** reports results & undo (`Restore-SenRestorePoint`).
- Overrides: "làm luôn đi"/"just do it" → Tier 1; "đây là Cấp 3"/"this is Tier 3" → Tier 3; auto-escalate via `Test-SenMidTaskEscalation`. Risk overrides file count (DB, auth, payments, deletion = Tier 3).

## 3. Priority over superpowers & Project rules
- Sen's tier decides which skills run (`using-superpowers` replaced). `brainstorming` + `writing-plans` only at Tier 3. Other skills (`systematic-debugging`, `verification-before-completion`, ...) run at any tier. Never edit superpowers files. Apply the project's AGENTS.md (up to root).

## 4. Roles, models & task state
- Tier 1: execute directly. Tier 2: spawn 1 Dev subagent (`invoke_subagent`).
- Tier 3: act as PM/Tech Lead, track DAG/locks in `.agents/office/tasks.json`, coordinate: BA/Architect (`inherit`), Scout (`flash_lite`/`flash`), Dev (`inherit`/`pro`), Tester (`inherit`), Reviewers (`inherit`/`pro`). Parallelize (`dispatching-parallel-agents`).
- **Anti-Hang & Teardown:** Pass `-Workspace`; never kill active/`idle` subagents; only kill stalled tasks (`manage_task`/`manage_subagents`, `Test-SenHungTasks`, `Clear-SenHungTasks`).

## 5. Tier 3 execution choice & Token economy
Announce in 1 line: <5 or dependent tasks → **Native** (1 Dev subagent, 1 review); many independent/risky tasks → **Subagent-driven** (1 subagent/task, ~2–3x cost). "tự làm"/"do it yourself" → Native; "giao agent phụ"/"use subagents" → Subagent-driven. Search by keyword first; delegate multi-file reads to `flash_lite` Scout; link to lines.

## 8. Diagrams & Singleton 3D Office
- Tier 3: Mermaid diagrams (business, system, state, data, UI, DAG). Tier 2: on request. Tier 1: flows.
- **Mermaid Pro & Archify:** No flat/unstyled Mermaid or `<br/>`. Use layered `subgraph` (<=5 nodes), numbered edges (`①`, `②`), semantic shapes (`(["..."])`, `[("...")]`, `{"..."}`), quoted `"..."`, and `classDef` + `style` palettes (`sen-office`). Interactive HTML/diff: `.agents/skills/archify/SKILL.md` (`generative_ui`).
- Tier 2–3: check `Get-SenOfficeTabStatus` (`start-office.ps1`); reuse tab; record `Write-SenOfficeShowcase` (Phase 1 Stage 2, Phase 2 Stage 4).

## 9. Quality gates & Legal-by-Design
- Default gate (Tier 2–3): tests/build pass (`Invoke-SenBoundedRepairRound`/`Invoke-SenEscalationQuarantine`), `Measure-SenCodeHealth` (`sen-clean-code`), no leaked secrets (`verification-before-completion`).
- Web/App Legal-by-Design (`vn-law-check`): un-prechecked consent + log (Luật 91/2025, NĐ 356/2025), consent gate, mobile `ACCOUNT_DELETE`, AI labels (Luật 134/2025), privacy policy; run `Invoke-SenVnLawScan`. Security: `security-audit`.

## 10. State checkpoints, Logic-Doc Sync & backlog
- Sync `docs/CONTEXT.md`, `docs/TODO.md`, `README.md`/`README.vi.md`, `CHANGELOG.md`, `Sync-SenOfficeState`, and `docs/releases/` (`New-SenReleaseNote`, `Test-SenReleaseNoteGate`) on changes (`Test-SenCapabilityParity`). On "lưu vào task cần làm"/"save to backlog", call `Add-SenBacklogItem`. Suggest `/compact`.

## 11. Capture repeated work & Environment
- Offer `sen-skill-capture` (`Register-SenActionPattern`, `New-SenCapturedSkill`) when workflows repeat 2–3x. Run `sen-environment` for tools; ask before `winget`/`brew`; new `npm`/`pip` = Tier 2.

## 12. Handover & CI Auto-Heal Loop
- Never say "done" without `Test-SenDeliveryGate` (`Install-SenGitHooks`). Tier 2–3 end with report (`sen-delivery-report`). On Git push, run `Invoke-SenCiPushLoop` (max 3 tries) until CI is 100% green. If the sen-office plugin is installed, also follow its rules.
