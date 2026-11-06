**English** | [Tiếng Việt](huong-dan.md)

# Complete Beginner Guide to Sen

This guide is written for anyone who wants to work with AI calmly, safely, and clearly — even if you have never used Git, written code, or heard of "skills" and "plugins" before.

---

## 1. Five Core Concepts (In Plain Language)

| Concept | Everyday Analogy (1 Sentence) | Concrete Example in Sen |
|---|---|---|
| **AI agent** | Like a capable office assistant who can read files, run tools, and finish real tasks instead of only chatting back. | When you ask to fix a button color, the AI agent opens the stylesheet, edits the color code, runs a check, and reports the result. |
| **Antigravity** | Like the shared office building where you and your AI assistants sit together working on your project folders. | You open Antigravity IDE on your computer and type requests in plain English into the chat panel next to your files. |
| **Rule** | Like a short company policy posted on the wall that every assistant follows automatically every day without being reminded. | Sen's `rules/AGENTS.md` is always active and makes the AI classify every work request into Tier 1, Tier 2, or Tier 3 on the very first line. |
| **Skill** | Like a step-by-step handbook for a specialized task that the assistant only opens when that specific job comes up. | When handing over a Tier 2/3 task, the AI opens `sen-delivery-report` to write a structured acceptance report; for security checks, it opens `security-audit`. |
| **Plugin** | Like a ready-to-use toolbox containing both the wall policy (rule) and all the specialist handbooks (skills) in one package. | `sen-method` is a plugin bundling the core rule and all 7 `sen-*` skills so you can install or toggle the entire Sen workflow as a single unit. |

---

## 2. Step-by-Step Installation (Including ZIP Download Without Git)

### Preparation: Install Antigravity IDE
1. Download and install **Antigravity IDE** on your computer (Windows, macOS, or Linux).
2. Open Antigravity IDE and sign in to your account.

### Method A (Recommended): Paste One Sentence into Antigravity Chat
Open the Antigravity chat panel and paste this single sentence:

```text
Please read https://github.com/developerfs0110/Sen/blob/main/INSTALL.md and install Sen for me.
```

The AI will read `INSTALL.md` and walk you through the 9-step `sen-setup` flow:
1. **Tool check:** The AI checks whether `git` is installed. If missing, it asks your permission to install it via `winget` (Windows) or `brew` (macOS). *(Note: `Node.js` is only needed later for the `sen-office` 3D monitor and is not required for core Sen).*
2. **Choose a workspace drive and folder:** The AI lists your writable drives with their free space and recommends the drive with the most room (e.g., `D:\Sen-Workspace`). You can accept the recommendation, use the currently open folder, or pick a custom path.
3. **Optional legal gate:** The AI asks whether you want to install `vn-law-check` (for projects needing Vietnamese legal compliance checks).
4. **Create workspace structure & fetch companion packages:** The installer creates `.agents/rules/`, `.agents/plugins/`, `.agents/skills/`, `Code/`, `Templates/`, and `docs/` (never overwriting existing files), installs Sen into `.agents/plugins/sen-method/`, downloads `superpowers` and `security-audit`, creates `.agents/rules/safety.md`, and records exact versions in `.agents/sen.lock.json`.
5. **Configure your profile (`profile.md`):** The AI asks 4 quick questions (your name/role, preferred language, primary tech stack/level, and working style) to create `.agents/rules/profile.md`.
6. **Register weekly update checks:** Sets up a background check once a week that uses zero tokens when no updates are pending.
7. **Open your new workspace:** If you installed Sen into a different folder than the one currently open, click **File → Open Folder**, select your new workspace folder, and type `"onboard me"` in a new chat.

### Method B: Manual `.zip` Download (For Users Without Git)
If your computer does not have Git yet or you prefer downloading a `.zip` file first:
1. Open your browser and download the archive:
   `https://github.com/developerfs0110/Sen/archive/refs/heads/main.zip`
2. Extract the `.zip` file to a temporary folder (for example, `D:\Sen-main`).
3. Open Antigravity IDE and paste into the chat:
   ```text
   Please read D:\Sen-main\INSTALL.md and install Sen from D:\Sen-main for me.
   ```
4. The AI will read the extracted folder on your computer and guide you through the same interactive workspace setup as Method A.

---

## 3. Verifying Your Installation

Once your Sen workspace folder is open in Antigravity IDE, start a new chat and try this test request:

```text
Create Code/hello/README.md with a short Sen greeting
```

**Expected result:**
- The very first line of the AI's reply starts with **`[Tier 1 - Doing it now]`** (or **`[Cấp 1 - Thực thi ngay]`** if your profile language is Vietnamese).
- The AI creates `Code/hello/README.md` right away **without asking unnecessary permission questions**, verifies the file exists, and gives you a clickable link.
- You can also type **`"onboard me"`** anytime to launch the interactive tour (`sen-onboarding`).

---

## 4. Your First Task at Each Tier (3 Concrete Examples)

Every work request in Sen is classified into one of 3 tiers (drawn directly from [`tests/tier-scenarios.md`](../tests/tier-scenarios.md)):

### Tier 1 Example — Small, Clear Task (Immediate Execution)
- **What you type:**
  > `Fix the typo "Welcom" on the home page`
- **What you see:**
  1. The AI starts its reply with **`[Tier 1 - Doing it now]`**.
  2. It locates the home page file, fixes `"Welcom"` to `"Welcome"`, runs any available lint/test/build check, and summarizes the change with a link to the updated line.
- **What you do:**
  - **Nothing else.** Small tasks are finished in a single turn with zero back-and-forth permission prompts.

### Tier 2 Example — New Feature or Changes Across 3+ Files
- **What you type:**
  > `Add dark mode to the app`
- **What you see:**
  1. The AI starts its reply with **`[Tier 2 - Confirming the approach]`**.
  2. It summarizes the proposed approach (e.g., theme context, CSS variables, toggle button, persistence) along with the **exact list of files it plans to create or edit**.
  3. It pauses and asks for your approval **once**.
- **What you do:**
  - Review the short summary and reply **`"Approved"`** (or suggest adjustments).
  - Once approved, the AI implements the entire feature, runs the verification gates, and presents an **Acceptance Report (`sen-delivery-report`)**.

### Tier 3 Example — New Project, Architecture, Database, Auth, or Payments
- **What you type:**
  > `Build a new mobile app for booking appointments`
- **What you see:**
  1. The AI starts its reply with **`[Tier 3 - Design & plan]`**.
  2. **Clarification & Design Spec:** The AI asks focused questions to clarify your needs, then writes a **Design Spec** in `docs/specs/` complete with Mermaid diagrams and a list of required/optional development tools.
  3. **Implementation Plan & Execution Choice:** After you approve the design, the AI writes a step-by-step **Implementation Plan** and automatically picks the execution mode in one line (without asking you a confusing technical question):
     - **Native (single agent):** when there are fewer than ~5 tasks or tasks are tightly coupled.
     - **Subagent-driven (specialist team):** when there are many independent tasks or high-risk areas, noting that subagents use roughly **2–3x** the token usage of Native execution.
  4. **Environment Check & Team Execution:** The AI checks your installed tools (`sen-environment`), coordinates specialist roles (BA, Scout, Dev, Tester, Security/Legal Reviewers), updates `docs/CONTEXT.md`, and finishes with an acceptance report.
- **What you do:**
  - Answer the brief clarifying questions, review and approve the **Design** and **Plan**, and inspect the final acceptance report when the team finishes.

---

## 5. How to Steer the AI in Plain Language

You never need special syntax to change how the AI works. Just say what you want in natural language:

| What You Want to Do | What to Say | What the AI Does |
|---|---|---|
| **Approve a Tier 2 approach or Tier 3 plan** | `"Approved"`, `"Go ahead"`, `"Looks good"` | Proceeds immediately to complete the implementation. |
| **Fast-track a task to Tier 1** | `"just do it"` (e.g., `"Add dark mode, just do it"`) | Overrides the current request to Tier 1 and executes right away without waiting for plan approval. |
| **Safety rule on `"just do it"` for risky tasks** | e.g., `"Switch auth to JWT, just do it"` | For data deletion, databases, authentication, or payments, the AI **never skips writing a design and plan**. It asks you to confirm once; if confirmed, it still writes the design + plan for your records and only skips waiting for their approval. |
| **Escalate a task to full Tier 3 design & plan** | `"this is Tier 3"`, `"let's design this carefully"` | Treats the current request as Tier 3 with full design spec, diagrams, and implementation plan. |
| **Switch Tier 3 execution mode (save quota vs. speed)** | `"do it yourself"` (switch to Native) or `"use subagents"` (switch to Subagent-driven) | Switches between single-agent execution (saves token quota) and parallel specialist subagents. |
| **Check for Sen updates anytime** | `"check Sen updates"` | Runs `sen-update` to check `sen-method`, `superpowers`, `security-audit`, and `vn-law-check`, shows a changelog summary, and waits for your approval before updating. |
| **Run pre-release checks before shipping** | `"check release readiness"` | Runs parallel checks across security, legal, licenses, accessibility, performance, SEO, and operations (`sen-release-readiness`), producing a `PASS / WARN / BLOCK` report. |
| **Open the 3D AI Office & Dual-Phase Visualizer** | `"open office"` (or `"eco mode"`, `"full mode"`, `"turn off office"`) | Opens the `sen-office` 3D Chibi command center (`office/index.html`) showing 9 AI roles + Boss on the red sofa, zero-token hook telemetry, 6-counter Inspector Drawer, Replay Scrubber, and Design vs. Delivery visualizer. |

---

## 6. Reading AI-Generated Documents

During Tier 2 and Tier 3 work, Sen keeps your project organized with clear Markdown documents:

1. **Design Specs (`docs/specs/YYYY-MM-DD-<topic>.md`):**
   - Created in Tier 3. Explains goals, architecture choices, data flow, and required/optional tools before any code is written.
2. **Implementation Plans (`docs/plans/`):**
   - Breaks a large project into small checkbox tasks (`- [ ]`), listing exact file paths and verification commands for each step.
3. **Mermaid Diagrams:**
   - Embedded directly inside design specs and reports (business flows, system architecture, state machines, data models, task dependencies). Antigravity renders them visually as clean flowcharts.
4. **Acceptance Reports (`sen-delivery-report`):**
   - Delivered at the end of every Tier 2 and Tier 3 job. Summarizes what changed, links to modified files, shows real test/build/security/legal gate outputs, and notes any follow-up items.
5. **Project State Checkpoints (`docs/CONTEXT.md`):**
   - Acts as your project's "short-term memory", updated after milestones or when a chat grows long. It records *where we are*, *locked decisions*, and *next immediate steps*. When you start a fresh chat session, the AI reads `docs/CONTEXT.md` to resume work immediately without wasting tokens re-reading old chat logs.

---

## 7. Editing `profile.md` and Adding Project Quality Gates (`AGENTS.md`)

### 7.1 Viewing and Editing Your Profile (`.agents/rules/profile.md`)
The file `<workspace>/.agents/rules/profile.md` tells the AI who you are and how you like to work. You can open and edit it anytime in Antigravity (template at [`templates/profile.template.md`](../templates/profile.template.md)):

- **Name:** How the AI should address you (e.g., `Alex - Product Owner`).
- **Preferred Language:** Default reply language (e.g., `English` or `Tiếng Việt`).
- **Primary Tech Stack:** Your main tools or experience level (e.g., `Beginner, no coding background` or `TypeScript, Next.js, PostgreSQL`).
- **Working Style:** Your communication preference (e.g., `Concise summaries with step-by-step visual diagrams`).

### 7.2 Adding Project-Specific Quality Gates (`<project>/AGENTS.md`)
By default, Sen enforces passing tests, passing builds, and basic security checks on all Tier 2–3 work. If a specific project in `Code/<project-name>/` needs stricter rules (such as mandatory deep security audits, Vietnamese legal compliance, or custom E2E checks):

1. Copy [`templates/project-AGENTS.template.md`](../templates/project-AGENTS.template.md) into the root of that project as `Code/<project-name>/AGENTS.md`.
2. Fill in `{{PROJECT_NAME}}` and set `{{ENABLE_SECURITY_GATE}}` / `{{ENABLE_LEGAL_GATE}}` to `Yes` or `No`.
3. Before working inside that project folder, the AI automatically reads the project's `AGENTS.md` and enforces every gate you enabled.

---

## 8. Troubleshooting, Uninstalling, and Glossary

### 8.1 Common Issues & Quick Fixes

| Symptom | Cause | Quick Fix |
|---|---|---|
| **AI replies do not start with `[Tier 1/2/3]`** | You opened a subfolder or another directory instead of the Sen workspace root containing `.agents/plugins/sen-method`. | Click **File → Open Folder** in Antigravity and open the workspace root folder (the one containing `.agents/`). |
| **Network error or failed package download during install** | Temporary internet drop or GitHub connection issue. | Check your connection and tell the AI: `"Re-run Sen installation"`. The installer is idempotent: it keeps existing files untouched and only downloads what is missing. |
| **A package update behaves unexpectedly** | An upstream package change introduced an issue. | Tell the AI: **`"Restore package <package-id> to the previous version"`**. Sen keeps automatic backups and rolls back cleanly via `Restore-SenPackage`. |
| **Duplicate plugin or skill warning during setup** | Another copy of `superpowers` or `security-audit` already exists in a global config folder (`~/.gemini/...`). | Choose which copy to keep when prompted so Antigravity does not silently ignore one of them. |
| **Chat session becomes slow or uses many tokens** | The conversation history has grown very long. | Ask the AI to `"Update CONTEXT.md"`, then run `/compact` or open a new chat window. |

### 8.2 How to Uninstall Sen
Sen never locks in your code or overwrites your work:
- Your projects in `Code/`, documentation in `docs/`, and personal rules (`profile.md`, `safety.md`) live in standard folders independent of Sen.
- To **temporarily disable** Sen: disable the plugin in Antigravity's Plugin Manager or set `"disabled": true` in `.agents/plugins/sen-method/plugin.json`.
- To **completely remove** Sen from a workspace: close Antigravity and delete `<workspace>/.agents/plugins/sen-method` (and `.agents/sen.lock.json` if desired). All of your project code and documents remain 100% intact.

### 8.3 Beginner Glossary

| Term | Plain-English Meaning |
|---|---|
| **Workspace** | Your main working folder on disk containing `.agents/`, `Code/`, `Templates/`, and `docs/`. |
| **Tier (Tier 1 / 2 / 3)** | The size and risk level of a request, which determines whether the AI acts immediately, asks once, or writes a full design and plan. |
| **Token** | The unit of text length the AI reads and writes; saving tokens makes responses faster and preserves your account usage quota. |
| **Subagent** | A specialist AI helper (Scout, Dev, Tester, Reviewer) spawned by the lead AI during Tier 3 projects. |
| **Scout** | A read-only subagent running on a lightweight model (`flash_lite` / `flash`) to search across files without burning your main model's tokens. |
| **Quality Gate** | A mandatory verification step (tests, build, security audit, legal check) before a task can be marked complete. |
| **Lockfile (`sen.lock.json`)** | The file in `.agents/` that records the exact installed commit versions of Sen and its companion packages. |

---

## 9. Need Help? Contact & Support

If you need help setting up Sen, have questions, or want to support the project's development, reach out to the author:

```text
Mr Bòn Bon - tunbh.study@gmail.com
(+84) 793.166.866 - (+84) 96.158.1163
Donate: TPBank - 61.222.666.888
```
