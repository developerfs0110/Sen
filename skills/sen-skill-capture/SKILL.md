---
name: sen-skill-capture
description: Captures repeated multi-step workflows or user process corrections into a reusable workspace skill. Trigger when a workflow repeats 2-3 times, after the user corrects a process mistake, or when user says "đóng gói thành skill" or "capture skill".
---

# `sen-skill-capture` — Package Repeated Workflows & Corrections into Reusable Skills

## When to Suggest or Trigger
1. **Repeated Workflow (2nd–3rd time — Deterministic Detection via `Register-SenActionPattern`):** You notice the user asking for, or you are executing, the same multi-step domain pattern, build/deploy ritual, or code convention for the **2nd or 3rd time** across the project or workspace. Record recurring action sequences via `Register-SenActionPattern -Workspace $ws -PatternName "<name>" -Steps @(...)`; when `ShouldCapture -eq $true`, offer to package it using the returned `SuggestedSkillName` (which automatically strips any reserved `sen-` prefix).
2. **After a Process Correction:** Immediately after the user corrects a non-trivial workflow, convention, or architectural mistake so the team never repeats the same mistake in future chats.
3. **Explicit User Request:** The user says **"đóng gói thành skill"**, **"tạo skill từ việc này"**, **"lưu quy trình này thành skill"**, **"capture this as a skill"**, or **"package this workflow as a skill"**.

---

## Core Safety & Placement Rules
- **Never create a skill silently.** When triggered proactively (cases 1 or 2 above), add **one concise line at the end of your reply** in the user's language offering to package the workflow as a skill, and wait for the user's explicit consent before creating any files.
  - *Vietnamese example:* `"Quy trình này đã lặp lại (hoặc vừa được bạn chỉnh lại). Bạn có muốn tôi đóng gói thành một skill riêng trong workspace để các lần sau tự động áp dụng không?"`
  - *English example:* `"We've repeated (or just refined) this workflow. Would you like me to package it as a workspace skill so future tasks follow it automatically?"`
- **Always place captured skills in the workspace's `.agents/skills/<skill-name>/SKILL.md`:**
  - Target path: `<WORKSPACE>/.agents/skills/<skill-name>/SKILL.md`
  - **NEVER** place user or project skills inside `<WORKSPACE>/.agents/plugins/sen-method/skills/` or `<WORKSPACE>/.agents/plugins/superpowers/skills/`. Those plugin directories are managed and replaced by `sen-update`.
- **Naming & Reserved `sen-` Prefix:**
  - Use lowercase kebab-case matching the directory name (`<skill-name>` in frontmatter `name:` must equal the folder name).
  - **Do NOT use the `sen-` prefix** for user-captured workspace skills (unless the user is intentionally developing the `sen-method` plugin itself). The `sen-` prefix is reserved for official Sen core skills so skill names never collide in Antigravity's global namespace.

---

## Step-by-Step Workflow (After User Consents)

### Step 1: Confirm Scope & Skill Name
Once the user agrees to create the skill:
1. Propose a short, descriptive kebab-case `<skill-name>` without the `sen-` prefix (for example, `fastapi-db-migration`, `release-changelog-check`, or `invoice-pdf-export`).
2. Confirm the destination path: `<WORKSPACE>/.agents/skills/<skill-name>/SKILL.md`.
3. If `<WORKSPACE>/.agents/skills/<skill-name>/SKILL.md` already exists, ask the user before updating or overwriting it.

### Step 2: Author & Package the Skill (`New-SenCapturedSkill, Invoke-SenPostCodePipeline` + `writing-skills`)
Use **`New-SenCapturedSkill, Invoke-SenPostCodePipeline`** to deterministically scaffold `<WORKSPACE>/.agents/skills/<skill-name>/SKILL.md` along with zero-token executable scripts (`scripts/run.ps1` and `scripts/run.sh`) and follow the **`writing-skills`** skill (`<WORKSPACE>/.agents/plugins/superpowers/skills/writing-skills/SKILL.md`):

1. Run `New-SenCapturedSkill, Invoke-SenPostCodePipeline -Workspace $ws -SkillName "<skill-name>" -Description "<trigger description>" -Steps @(...) -Commands @(...)` to generate `SKILL.md`, `scripts/run.ps1`, and `scripts/run.sh`, and automatically mark `.agents/office/action-patterns.json` as captured (`capturedSkill = "<skill-name>"`).
2. Read and follow **`writing-skills`** best practices:
   - Write clear YAML frontmatter with `name: <skill-name>` and a specific `description` (`<= 300` characters) that states **when to trigger** the skill (including both Vietnamese and English trigger phrases if the user works in Vietnamese).
   - Keep the body focused on actionable steps, exact commands/paths, edge cases discovered during the session, and the specific mistake or pitfall the user corrected.
   - Keep `SKILL.md` compact (`<= 12,000` bytes); if the workflow requires a long checklist, template, or helper script, place those in sibling files inside `<WORKSPACE>/.agents/skills/<skill-name>/` and link to them with relative markdown links.

### Step 3: Verify & Report
1. Verify that `<WORKSPACE>/.agents/skills/<skill-name>/SKILL.md` exists, its frontmatter `name` matches `<skill-name>`, and any relative links inside it resolve to existing files.
2. Report the new skill to the user in their language with a clickable link to `<WORKSPACE>/.agents/skills/<skill-name>/SKILL.md` and a 1-line example of how it will trigger automatically in future requests.
