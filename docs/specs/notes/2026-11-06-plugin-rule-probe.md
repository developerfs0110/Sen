# Plugin rule loading probe (Task 0), 2026-11-06

## Results
1. **Plugin rule: LOADED.** `<workspace>/.agents/plugins/sen-probe/rules/AGENTS.md` was applied in a new chat (`probe sen` → `SEN-PROBE-OK`). The main plugin layout works; the fallback copy into `.agents/rules/sen.md` is **not** needed.
2. **Project-level `AGENTS.md`: NOT loaded** just from the user opening a file in `Code/_probe/` in the editor. Note that `Code/` is itself a git repository root, so the docs' "walk up to the repository root" rule should have reached it. The rule may only load when the agent itself opens or edits a file in that folder. That was not confirmed: reading the file from an existing session showed no injected rule either.

## Decision
- Keep the plugin layout (`rules/AGENTS.md` inside the plugin).
- Per-project gates must not depend on automatic loading. The core rule gets an explicit instruction: **before working in a project folder, read `AGENTS.md` in that project's root (and parent folders up to the workspace) if it exists, and apply it.** This is cheap (one small file read, only when working in a project) and works whether or not Antigravity loads it automatically.
- Affects: spec 7.6 (project gates), plan Task 2 (rule must contain this instruction; add `AGENTS.md` lookup string to the rule test).

## Cleanup
Probe files removed individually. The workspace guard hook blocks recursive delete, so implementers must delete files one by one as well.
