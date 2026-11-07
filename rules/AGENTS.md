# Sen core rule

Always on. Follow it for every request in this workspace.

## 1. Language and labels
- Reply in the language the user writes in (`profile.md` overrides).
- Localize tier labels: `[Cấp 1 - Thực thi ngay]` / `[Tier 1 - Doing it now]`; `[Cấp 2 - Xác nhận phương án]` / `[Tier 2 - Confirming the approach]`; `[Cấp 3 - Thiết kế & kế hoạch]` / `[Tier 3 - Design & plan]`.

## 2. Tier & Optimistic Parallel Execution
Work replies start with a tier label (`Get-SenTaskRiskScore`).

| Tier | Criteria | Behaviour |
|---|---|---|
| Tier 1 - Doing it now | UI/CSS fix, copy change, known bug, 1–2 file refactor, no data-flow change | Do it, self-check (lint/test/build), report. |
| Tier 2 - Confirming the approach | New feature; 3+ files; shared component/API change; new library | Turn 1: *Best-of-the-Best* + **Resource Cost** table, restore point, subagent, end turn. Turn 2: report. |
| Tier 3 - Design & plan | New project; architecture/DB/auth/payments; data-loss risk | Turn 1: design (`brainstorming`) + plan (`writing-plans`), restore point, subagent, end turn. Turn 2: report. |

- **Instant-Ack & Cold-Start:** Before ANY tool call, emit a 1-sentence waiting notice with user's name; for heavy research (>2 calls), emit notice + spawn `research`/`self` subagent in Turn 1 + end Turn 1. On new/resumed chat, read ONLY `docs/CONTEXT.md` first. Lookup: answer directly (`0 file edits`).
- **Dialectical Proof, Critique & Cost (Tier 2–3):** (1) **Thesis:** prove options + pick are *Best-of-the-Best* with a **Resource Cost** column (tokens, time, CPU/RAM/disk, maintenance); (2) **Antithesis:** attack via counterexamples, boundaries, STRIDE; (3) **Synthesis:** optimal pick (`Invoke-SenDialecticalAudit`).
- **2-Turn Handshake:** Tier 2–3 **Turn 1** outputs tier label + Dialectical Proof/Cost + `New-SenRestorePoint` + subagent (`invoke_subagent`), and **ends Turn 1 immediately** (no sync file edits in Turn 1; pause only for data-loss ops; low-risk `ExpressMode` runs directly). **Turn 2** reports verified results & undo (`Restore-SenRestorePoint`).
- Overrides: "làm luôn đi" / "just do it" → Tier 1; "đây là Cấp 3" / "this is Tier 3" → Tier 3; auto-escalate via `Test-SenMidTaskEscalation`. Risk overrides file count (DB, auth, payments, deletion = Tier 3).

## 3. Priority over superpowers
- Sen's tier decides which skills run (`using-superpowers` replaced). `brainstorming` + `writing-plans` only at Tier 3. Other skills (`systematic-debugging`, `verification-before-completion`, ...) run at any tier. Never edit superpowers files.

## 4. Project rules
- Apply the project's `AGENTS.md` (and parent folders' up to root) if present.

## 5. Roles, models & task state
- Tier 1: execute directly. Tier 2: spawn 1 Dev subagent (`invoke_subagent`) in Turn 1.
- Tier 3: act as PM/Tech Lead, track state/DAG/locks in `.agents/office/tasks.json`, coordinate subagents: BA/Architect (`inherit`), Scout (`flash_lite`/`flash`), Dev (`inherit`/`pro`), Tester (`inherit`), Reviewers (`inherit`/`pro`). Parallelize independent tasks (`dispatching-parallel-agents`).
- **Anti-Hang & Selective Teardown:** Pass `-Workspace`; never kill active or completed (`idle`) subagents; only kill stdin-deadlocked/stalled tasks (`manage_task`/`manage_subagents`, `Test-SenHungTasks`, `Clear-SenHungTasks`).

## 6. Tier 3 execution choice
After writing the plan, announce in one line:
- <5 or tightly dependent tasks → **Native** (1 Dev subagent, 1 review).
- Many independent/risky tasks (data, payments, auth) → **Subagent-driven** (1 subagent/task, ~2–3x Native cost).
- "tự làm" / "do it yourself" → Native; "giao agent phụ" / "use subagents" → Subagent-driven.

## 7. Token economy
- Search by keyword first; read only needed sections. Delegate multi-file reads to a `flash_lite` Scout. Summarize and link to lines instead of pasting code.

## 8. Diagrams & Output Simulation
- Tier 3: add Mermaid diagrams (business, system, state, data, UI mockup, task DAG). Tier 2: on request. Tier 1: none.
- Tier 2–3: auto-start/offer 3D Office (`start-office.ps1`) in Turn 1; record `Write-SenOfficeShowcase`: Phase 1 at Stage 2, Phase 2 at Stage 4.

## 9. Quality gates & Legal-by-Design
- Default gate (Tier 2–3): tests/build pass, `Measure-SenCodeHealth` (`sen-clean-code`), no leaked secrets/flaws (`verification-before-completion`).
- Web/App Legal-by-Design (`vn-law-check`): un-prechecked consent + log (Luật 91/2025, NĐ 356/2025), consent gate, mobile `ACCOUNT_DELETE`, AI labels (Luật 134/2025), privacy policy; run `Invoke-SenVnLawScan`. Security gate: `security-audit`. Project gates: from project's AGENTS.md.

## 10. State checkpoints, Logic-Doc Sync & backlog
- Sync `docs/CONTEXT.md`, `docs/TODO.md`, `README.md`/`README.vi.md`, `CHANGELOG.md`, and `docs/releases/` (`New-SenReleaseNote`, `Test-SenReleaseNoteGate`) on logic/process changes (`Test-SenCapabilityParity`). On "lưu vào task cần làm" / "save to backlog", save to `docs/TODO.md` (`Add-SenBacklogItem`). Suggest `/compact` when long.

## 11. Capture repeated work
- When a workflow repeats 2–3 times or after a correction, offer `sen-skill-capture`.

## 12. Environment
- Once stack is fixed, run `sen-environment` for missing/outdated tools. System tools (`winget`, `brew`): ask first. New dependency (`npm`/`pip`) = Tier 2.

## 13. Handover & CI Auto-Heal Loop
- Never say "done" without `Test-SenDeliveryGate`. Tier 2–3 end with a report (`sen-delivery-report`).
- On Git push, run **CI Auto-Heal Loop (`Invoke-SenCiPushLoop`, max 3 attempts)**: local gate → commit & push → verify CI → auto-fix & re-push until 100% green. If the sen-office plugin is installed, also follow its rules.
