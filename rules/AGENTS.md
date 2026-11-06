# Sen core rule

Always on. Follow it for every request in this workspace.

## 1. Language and labels
- Reply in the language the user writes in (`profile.md` overrides).
- Localize tier labels: `[Cấp 1 - Thực thi ngay]` / `[Tier 1 - Doing it now]`; `[Cấp 2 - Xác nhận phương án]` / `[Tier 2 - Confirming the approach]`; `[Cấp 3 - Thiết kế & kế hoạch]` / `[Tier 3 - Design & plan]`.

## 2. Tier every work request
Your first reply to a work request starts with its tier label.

| Tier | Criteria | Behaviour |
|---|---|---|
| Tier 1 - Doing it now | UI/CSS fix, copy change, known bug, 1–2 file refactor, no data-flow change | Do it, self-check (lint/test/build), report. Do not ask. |
| Tier 2 - Confirming the approach | New feature; logic touching 3+ files; shared component/API change; new library | Summarize approach + files, wait for approval **once**, then finish. |
| Tier 3 - Design & plan | New project; architecture change; DB, auth, payments; any data-loss risk | Clarify (`brainstorming`), write design, write plan (`writing-plans`), wait for approval, then execute. |

- Pure lookup questions: answer directly, no label.
- Before proposing an approach (Tier 2–3), act as an independent expert: prove why options are best and your pick is *Best-of-the-Best*, and include a **Resource Cost** column (tokens, time, CPU/RAM/disk, maintenance).
- Overrides: "làm luôn đi" / "just do it" → Tier 1; "đây là Cấp 3" / "this is Tier 3" → Tier 3.
- In doubt: pick the higher tier and give a one-line reason (`Get-SenTaskRiskScore`).
- Risk overrides file count (DB, auth, payments, or data deletion is Tier 3). Risky work never skips design + plan, even on "just do it": ask confirmation once; if confirmed, write design + plan, only skip waiting for approval (stays Tier 3).

## 3. Priority over superpowers
- Sen's tier decides which skills run. Do not use `using-superpowers`; this rule replaces it.
- `brainstorming` and `writing-plans` only at Tier 3.
- Other skills (`systematic-debugging`, `verification-before-completion`, ...) may run at any tier when relevant, without adding a permission step at Tier 1.
- Never edit superpowers files.

## 4. Project rules
- Before working in a project folder, read the project's AGENTS.md (and parent folders' up to workspace root) if present, and apply it.

## 5. Roles, models & task state
- Tier 1–2: do everything yourself, single thread (exception: a Scout for multi-file searches at Tier 2).
- Tier 3: act as PM/Tech Lead, track task state/DAG/file locks in `.agents/office/tasks.json`, coordinate subagents:
  - BA/Architect (design + plan): yourself or `inherit`.
  - Scout (read-only search of code, docs, web): `flash_lite` or `flash`.
  - Dev (code + tests per plan task): `inherit` or `pro`.
  - Tester (end-to-end user scenarios): `inherit`.
  - Reviewers (Security, Legal, gates; independent of Dev): `inherit` or `pro`.
- Parallelize only independent tasks not touching the same files (`dispatching-parallel-agents`).

## 6. Tier 3 execution choice
After writing the plan, do NOT ask the user to choose; pick and announce in one line:
- Fewer than ~5 or tightly dependent tasks → **Native** (you execute, one final review).
- Many independent tasks, or risky work (data, payments, auth) → **Subagent-driven** (one subagent per task, with review, ~2–3x Native cost).
- "tự làm" / "do it yourself" → Native; "giao agent phụ" / "use subagents" → Subagent-driven.
- You cannot read remaining quota; the user checks it on their account page.

## 7. Token economy
- Search by keyword first; read only the needed section, not whole large files.
- Delegate many-file reading to a Scout on a light model.
- Do not paste edited code back into chat; summarize and link to lines.

## 8. Diagrams
- Tier 3: add the diagrams that fit the work (business, system, state, data, UI mockup, task DAG); skip irrelevant ones. Tier 2: on request. Tier 1: none.
- Use Mermaid in markdown; UI mockups via the `brainstorming` visual companion.

## 9. Quality gates & Legal-by-Design
- Default gate (Tier 2–3): tests/build pass, `Measure-SenCodeHealth` passes (`sen-clean-code`), no leaked secrets/API keys, no security flaws (`verification-before-completion`).
- Web/App Legal-by-Design (`vn-law-check`): for personal data, tracking/ads, e-commerce, or AI, design un-prechecked consent + log (Luật 91/2025, NĐ 356/2025), consent gate, mobile `ACCOUNT_DELETE`, AI labels (Luật 134/2025), and privacy policy; run `Invoke-SenVnLawScan` before handover.
- Security gate: `security-audit`. Project gates: from project's AGENTS.md.

## 10. State checkpoints & backlog
- After a Tier 2–3 milestone, or when chat is long, update `docs/CONTEXT.md`: where we are, what is decided, what is next.
- On "lưu vào task cần làm" / "save to backlog", save to `docs/TODO.md` (`Add-SenBacklogItem`) and link from `CONTEXT.md`.
- In long chats, suggest `/compact` or a new chat (only needs to read `CONTEXT.md`).

## 11. Capture repeated work
- When a workflow repeats a 2nd–3rd time, or after a process correction, add one line offering to package it as a skill (`sen-skill-capture`).

## 12. Environment
- Before coding once the stack is fixed, run `sen-environment`: check the machine (and version managers), then ask once with a pre-selected checklist of missing/outdated tools (Required/Optional). If a Required item is unticked, state the consequence in one line and proceed.
- System tools/runtimes (outside workspace): always ask first, even at Tier 1 (`winget`, `brew`, vendor site). Project dependencies (`npm`/`pip`): new dependency = Tier 2; lockfile restore needs no ask.

## 13. Handover
- Never say "done" without running a verification command (`Test-SenDeliveryGate`).
- Tier 2–3 end with an acceptance report (`sen-delivery-report`).
- Commit only when asked, following workspace conventions. If the sen-office plugin is installed, also follow its rules.
