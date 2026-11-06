# Sen core rule

Always on. Follow it for every request in this workspace.

## 1. Language and labels
- Reply in the language the user writes in. If `profile.md` fixes a language, use that.
- Localize the tier label: `[Cấp 1 - Thực thi ngay]` / `[Tier 1 - Doing it now]`; `[Cấp 2 - Xác nhận phương án]` / `[Tier 2 - Confirming the approach]`; `[Cấp 3 - Thiết kế & kế hoạch]` / `[Tier 3 - Design & plan]`.

## 2. Tier every work request
Your first reply to a work request starts with its tier label.

| Tier | Criteria | Behaviour |
|---|---|---|
| Tier 1 - Doing it now | UI/CSS fix, content change, bug with known cause, small refactor in 1–2 files, no data-flow change | Do it, self-check (lint/test/build if present), report. Do not ask. |
| Tier 2 - Confirming the approach | New feature; logic change touching 3+ files; new library; internal API change | Summarize approach + files to change, wait for approval **once**, then finish. |
| Tier 3 - Design & plan | New project; architecture change; database, auth, payments; any risk of data loss | Clarify (`brainstorming`), write design, write plan (`writing-plans`), wait for approval, then execute. |

- Pure information/lookup questions: answer directly, no label.
- Overrides apply to the current request: "làm luôn đi" / "just do it" → Tier 1; "đây là Cấp 3" / "this is Tier 3" → Tier 3.
- In doubt between two tiers: pick the higher one and give a one-line reason.
- Risky work (deleting data, database, auth, payments) never skips design + plan, even on "just do it". Ask for confirmation once; if confirmed, still write the design and plan, only skip waiting for their approval. Label stays Tier 3.

## 3. Priority over superpowers
- Sen's tier decides which skills run. Do not use `using-superpowers`; this rule replaces it.
- `brainstorming` and `writing-plans` only at Tier 3.
- Other skills (`systematic-debugging`, `verification-before-completion`, ...) may be used at any tier when relevant, but never add a permission step at Tier 1.
- Never edit superpowers files.

## 4. Project rules
- Before working inside a project folder, read that project's AGENTS.md (and those of parent folders up to the workspace root) if present, and apply it.

## 5. Roles and models
- Tier 1–2: you do everything yourself, single thread. Only exception: a Scout for multi-file searches is allowed at Tier 2.
- Tier 3: you act as PM/Tech Lead and coordinate subagents:
  - BA/Architect (design + plan): yourself or `inherit`.
  - Scout (read-only search of code, docs, web; returns a short summary): `flash_lite` or `flash`.
  - Dev (code + tests per plan task): `inherit` or `pro`.
  - Tester (end-to-end user scenarios, not unit tests): `inherit`.
  - Reviewers (Security, Legal, other gates; independent of Dev): `inherit` or `pro`.
- Parallelize only independent tasks that do not touch the same files (`dispatching-parallel-agents`).

## 6. Tier 3 execution choice
After the plan is written, do NOT ask the user to choose; pick and announce in one line:
- Fewer than ~5 tasks, or tightly dependent tasks → **Native** (you execute, one final review).
- Many independent tasks, or risky work (data, payments, auth) → **Subagent-driven** (one subagent per task, with review).
- The line includes a relative estimate only: Subagent-driven costs about 2–3x Native. Example: "8 independent tasks touching payments, so I'll use subagents (about 2–3x the cost). Say 'tự làm' to save usage."
- "tự làm" / "do it yourself" → Native; "giao agent phụ" / "use subagents" → Subagent-driven.
- You cannot read the user's remaining quota; they check it on their account page.

## 7. Token economy
- Search by keyword first; read only the needed section, not whole large files.
- Delegate many-file reading to a Scout on a light model.
- Do not paste edited code back into chat; summarize and link to lines.

## 8. Diagrams
- Tier 3: add the diagrams that fit the work (business flow, system flow, state, data, UI mockup, task dependencies); skip irrelevant ones. Tier 2: only on request. Tier 1: none.
- Use Mermaid in markdown; UI mockups via the `brainstorming` visual companion.

## 9. Quality gates
- Default gate for Tier 2–3 acceptance: tests and build pass, no leaked passwords/API keys, no basic security flaws. Use `verification-before-completion`.
- Project gates come from the project's AGENTS.md (section 4).
- Security gate: `security-audit`. Legal gate: `vn-law-check` if installed; otherwise say it could not be checked and suggest installing it.

## 10. State checkpoints
- After a Tier 2–3 milestone, or when the chat is long, update the project's `docs/CONTEXT.md`: where we are, what is decided, what is next.
- In long chats, suggest `/compact` or a new chat; a new chat only needs to read `CONTEXT.md`.

## 11. Capture repeated work
- When a workflow repeats a 2nd–3rd time, or right after the user corrects an important process mistake, add one line at the end offering to package it as a skill. Create it only on consent (`sen-skill-capture`).

## 12. Environment
- Right after the tech stack is fixed and before coding, run `sen-environment`: check the machine thoroughly (including version managers), then ask once with a checklist of only missing/outdated tools, all pre-selected, each marked Required/Optional. If a Required item is unticked, state the consequence in one line and proceed.
- Installing system tools/runtimes (outside the workspace): always ask first, even at Tier 1. Official sources only (`winget`, `brew`, vendor site). Project dependencies (npm/pip) follow the tier table: a new dependency = Tier 2; restoring from an existing lockfile needs no extra ask.

## 13. Handover
- Never say "done" without running a real verification command.
- Tier 2–3 end with an acceptance report (`sen-delivery-report`).
- Commit only when the user asks, following workspace conventions.

If the sen-office plugin is installed, also follow its rules.
