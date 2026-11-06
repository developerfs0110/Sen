# Delivery & Acceptance Report: {{TASK_OR_MILESTONE_TITLE}}

> **Agent Instruction:** Render this report in the user's language (Vietnamese if the user writes in Vietnamese or as configured in `profile.md`, English otherwise). Translate section headings naturally while preserving all five sections and concrete verification evidence.

- **Tier:** {{TIER_LABEL}}
- **Date:** {{DATE}}
- **Status:** {{OVERALL_STATUS}}

---

## 1. Summary of What Was Built / Fixed
- Concise overview of the completed feature, fix, or milestone and how it satisfies the approved requirements or plan.
- Key architectural or implementation decisions taken during execution.

## 2. Files Changed
*(Use clickable markdown links with `file:///` paths and line ranges so the user can jump directly to each change without reading pasted code blocks in chat.)*

- Created / Modified / Deleted: `path/to/file.ext` (lines `L10-L45`) — brief 1-line summary of the change.

## 3. Verification & Test Results
*(Every completion claim must be backed by a fresh command execution from `verification-before-completion`.)*

| Check | Exact Command Run | Exit Code | Output / Evidence Summary |
|---|---|---|---|
| Unit / Integration Tests | `{{TEST_COMMAND}}` | `0` | {{PASS_FAIL_COUNTS}} |
| Build / Type Check / Lint | `{{BUILD_COMMAND}}` | `0` | {{BUILD_SUMMARY}} |
| End-to-End / Scenario Check | `{{SCENARIO_COMMAND}}` | `0` | {{SCENARIO_SUMMARY}} |

## 4. Review & Quality Gates Passed
- **Default Gate (`verification-before-completion`):** {{DEFAULT_GATE_RESULT}} (tests/build pass, no leaked secrets/API keys, no basic security flaws).
- **Tier 2 / Tier 3 Code & Spec Review:** {{CODE_REVIEW_RESULT}}
- **Project / Security / Legal / Release Gates (from project `AGENTS.md` or `sen-release-readiness`, if applicable):** {{PROJECT_GATES_RESULT}}

## 5. Remaining Work, Known Limitations & Next Steps
- **Context Checkpoint (`docs/CONTEXT.md`):** Updated with current status, locked decisions, and next steps (or N/A if no project `docs/CONTEXT.md` is used).
- **Remaining Work / Known Limitations:** Any deferred items, follow-up tasks, or known constraints.
- **Recommended Next Steps:** Immediate next milestone or action for the user (note: git commit is only performed when explicitly requested by the user).
