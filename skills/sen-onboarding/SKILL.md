---
name: sen-onboarding
description: Interactive walkthrough for new Sen users. Trigger when user says "hướng dẫn tôi", "onboard me", or asks how to start using Sen. Verifies installation and profile.md, introduces Tiers 1-3 with workspace examples, and runs a live Tier 1 task.
---

# `sen-onboarding` — Interactive First-Time Walkthrough

## When to Trigger
- The user types **"hướng dẫn tôi"**, **"onboard me"**, **"bắt đầu với Sen"**, or asks for a tour after installing Sen.
- Handed off from `sen-setup` Step 9 after the user opens their Sen workspace in Antigravity IDE.

## Language & Tone
- Reply in the user's preferred language (from `.agents/rules/profile.md` if set, otherwise match the language the user writes in).
- Keep explanations warm, concise, and free of unnecessary jargon. Guide the user step by step rather than dumping a wall of text.

---

## Step-by-Step Walkthrough

### Step 1: Verify Installation & `profile.md`
Before starting the tour, verify that the current workspace `<WORKSPACE>` is properly set up:

1. **Check `.agents/sen.lock.json` and required packages:**
   ```powershell
   Import-Module -Name "<WORKSPACE>/.agents/plugins/sen-method/scripts/Sen.psm1" -Force
   $lock = Read-SenLock -Workspace "<WORKSPACE>"
   ```
   Verify that `sen-method`, `superpowers`, and `security-audit` exist in `$lock.packages` and on disk (`.agents/plugins/sen-method`, `.agents/plugins/superpowers`, `.agents/skills/security-audit`).
   - **If the lock file or required packages are missing:** Explain that Sen setup is incomplete in this folder and immediately invoke **`sen-setup`** to complete the installation.
2. **Check `.agents/rules/profile.md` (or `.agents/memory/profile.md`):**
   - If `profile.md` is missing or still contains unfilled template placeholders (`{{NAME}}`, `{{LANGUAGE}}`, `{{STACK}}`, `{{STYLE}}`), ask the 4 profile questions (Name/Role, Preferred language, Primary tech stack/level, Working style) and generate `.agents/rules/profile.md` via `New-SenFileFromTemplate` (see `sen-setup` Step 6) before continuing.

---

### Step 2: Introduce the 3 Tiers with Real Workspace Examples
Greet the user by name (from `profile.md`) and explain that every work request in a Sen workspace is **automatically classified into 3 Tiers**, shown in the very first line of the AI's reply. Ground your examples in the actual folders present in their workspace (`Code/`, `docs/`, `Templates/`):

| Tier | Label (VI / EN) | Concrete Example in This Workspace | What You Do |
|---|---|---|---|
| **Tier 1** | `[Cấp 1 - Thực thi ngay]` / `[Tier 1 - Doing it now]` | Fix a typo in `docs/`, create a small note, or tweak 1–2 files in `Code/` without changing data flow. | **Nothing** — AI does it right away, checks the result, and reports back without asking permission. |
| **Tier 2** | `[Cấp 2 - Xác nhận phương án]` / `[Tier 2 - Confirming the approach]` | Add a feature touching 3+ files in `Code/` or install a new library. | **Approve once** — AI summarizes the approach and file list, waits for your OK once, then finishes the job. |
| **Tier 3** | `[Cấp 3 - Thiết kế & kế hoạch]` / `[Tier 3 - Design & plan]` | Build a new app in `Code/`, change architecture, or touch databases, authentication, or payments. | **Review design & plan** — AI clarifies goals, writes design + diagrams + plan, coordinates specialist subagents, and runs quality gates. |

*(Mention in one line that pure lookup/information questions are answered directly with no tier label.)*

---

### Step 3: Run a Live `Tier 1` Practice Task Together
Invite the user to experience `Tier 1` right now with a safe, 10-second micro-task inside their workspace:

1. **Propose or run the micro-task:**
   Create `<WORKSPACE>/Code/hello/README.md` containing a short welcome note in the user's language (or ask them to type: *"Tạo file `Code/hello/README.md` ghi lời chào của Sen"* / *"Create `Code/hello/README.md` with a short Sen greeting"*).
2. **Execute as a real `Tier 1` response:**
   - Start your response with `[Cấp 1 - Thực thi ngay]` (Vietnamese) or `[Tier 1 - Doing it now]` (English).
   - Create `Code/hello/README.md` without asking extra permission questions.
   - Verify that `Code/hello/README.md` exists and is non-empty.
   - Report completion with a clickable link to `Code/hello/README.md` (and offer to delete the practice folder if they want a clean `Code/` directory).

---

### Step 4: Show Overrides & Update Commands
Finish the walkthrough with a short cheat-sheet of phrases the user can say anytime in natural language:

1. **Override the Tier for the current request:**
   - Drop to **Tier 1** (fast execution): say **`"làm luôn đi"`** / **`"làm nhanh"`** / **`"just do it"`** / **`"quick"`**. *(Note: risky work touching data deletion, databases, auth, or payments never skips design + plan even on "just do it".)*
   - Escalate to **Tier 3** (full design & plan): say **`"đây là Cấp 3"`** / **`"làm kỹ"`** / **`"this is Tier 3"`** / **`"thorough"`**.
2. **Switch Tier 3 execution mode (save quota vs. parallel team):**
   - Say **`"tự làm"`** / **`"do it yourself"`** for Native execution (lower token usage), or **`"giao agent phụ"`** / **`"use subagents"`** for Subagent-driven execution.
3. **Check for Sen updates anytime:**
   - Sen checks for updates automatically in the background once a week at zero token cost.
   - To check manually anytime, say **`"kiểm tra cập nhật Sen"`** or **`"check Sen updates"`** (runs `sen-update`).

Ask the user what real project or task they would like to tackle first!
