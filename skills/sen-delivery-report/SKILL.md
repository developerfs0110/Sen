---
name: sen-delivery-report
description: Generates a verified acceptance and delivery report at the end of Tier 2 and Tier 3 tasks. Trigger when finishing Tier 2/3 work or when the user says "báo cáo nghiệm thu", "báo cáo bàn giao", or "delivery report".
---

# `sen-delivery-report` — Tier 2 & Tier 3 Acceptance and Handover Report

## When to Trigger
- **Automatically** at the end of every **Tier 2** (`[Cấp 2 - Xác nhận phương án]` / `[Tier 2 - Confirming the approach]`) and **Tier 3** (`[Cấp 3 - Thiết kế & kế hoạch]` / `[Tier 3 - Design & plan]`) task or milestone before declaring the work complete.
- **On demand** when the user asks for an acceptance or handover summary (e.g., **"báo cáo nghiệm thu"**, **"báo cáo bàn giao"**, **"delivery report"**, **"handover report"**).
- Not required for routine Tier 1 tasks (Tier 1 reports inline in a few lines after self-checking).

## Language & Token Economy Rules
- Write the final delivery report in the **user's language** (from `.agents/rules/profile.md` if set, otherwise match the language the user writes in).
- **Do not paste edited source code blocks into the report.** Summarize what changed and link directly to the modified files and line ranges (`file:///...#L10-L25`).

---

## Step-by-Step Workflow

### Step 1: Run `verification-before-completion` First (Mandatory)
Never claim a task is "done" or write a delivery report from memory or assumptions:

1. Follow the **`verification-before-completion`** skill strictly:
   - Run the actual test suite, build, linter, or scenario verification commands fresh in the current state of the workspace.
   - Confirm that the exit code is `0` and inspect the command output.
   - Check that no passwords, tokens, or API keys were accidentally introduced into tracked files, and no basic security flaws were added.
2. Check if the project has a local `AGENTS.md` (in the project root or parent directories up to the workspace root):
   - If the project's `AGENTS.md` enables additional gates (such as `security-audit`, `vn-law-check`, or custom checks), run those gates before finalizing the report.
3. If any test, build, or required gate fails, **stop**, fix the issue first, and re-run verification before generating the delivery report.

---

### Step 2: Update `docs/CONTEXT.md` (State Checkpoint)
For Tier 2 and Tier 3 projects that maintain a project context file (or when completing a milestone in a multi-step project):

1. Check if `<project>/docs/CONTEXT.md` exists (or create it from `<WORKSPACE>/.agents/plugins/sen-method/templates/CONTEXT.template.md` at Tier 3 milestones if missing).
2. Update `docs/CONTEXT.md` with:
   - **Where We Are:** The milestone or feature just completed.
   - **Locked Decisions:** Any architectural, schema, or API decisions finalized during this work.
   - **Completed Work & Verified Gates:** Summary of verified test and gate results.
   - **Next Immediate Steps:** What remains to be done next.
3. If the conversation has grown long, add a 1-line tip at the end of your reply suggesting `/compact` or starting a fresh chat session (which only needs to read `docs/CONTEXT.md`).
4. If `sen-office` is active (`Get-SenOfficeConfig` mode is `"eco"` or `"full"`), call `Write-SenOfficeShowcase` to update Phase 2 (`phase2.summary`, `phase2.verifiedOutputs`, and `phase2.gates`) so the Dual-Phase Visualizer in the 3D Office reflects the final verified outputs.

---

### Step 3: Render the Report Using `report.template.md`
Read and follow the structure in [report.template.md](report.template.md) to present the final handover report in the user's language. Every report must include all 5 sections:

1. **Summary of What Was Built / Fixed** (*Tóm tắt công việc đã hoàn thành*):
   - Clear, concise description of the solution and how it fulfills the approved approach or plan.
2. **Files Changed** (*Danh sách file đã thay đổi*):
   - List each created, modified, or deleted file with clickable `file:///` links to specific line numbers (`#L<start>-L<end>`) and a 1-line note per file.
3. **Verification & Test Results** (*Kết quả kiểm tra & test*):
   - Record the **exact commands run**, their **exit codes**, and a concise **output summary** (e.g., pass/fail counts, build output) as concrete evidence.
4. **Review & Quality Gates Passed** (*Kết quả các cổng kiểm duyệt*):
   - Status of the default gate (`verification-before-completion`), Tier 2/3 spec and code reviews (including Tester / Reviewer subagents at Tier 3), and any project-specific security (`security-audit`), legal (`vn-law-check`), or release readiness (`sen-release-readiness`) gates.
5. **Remaining Work, Known Limitations & Next Steps** (*Việc còn lại & bước tiếp theo*):
   - Confirm whether `docs/CONTEXT.md` was updated, list any deferred items or known limitations, and state the next recommended step.
   - **Git Commit Reminder:** Do **not** commit automatically unless the user explicitly asked to commit. Offer to commit following workspace conventions if changes are uncommitted.
