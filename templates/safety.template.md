# System Safety Rules and Command Constraints (SAFETY RULES)

This document defines mandatory safety rules that apply to all interactions and command executions within the workspace.

---

### 1. Git and Source Code Safety (GIT SAFETY)
- **STRICTLY FORBIDDEN:** Running `git push --force` or `git push -f` under any circumstances.
- **STRICTLY FORBIDDEN:** Running `git reset --hard` unless the user explicitly requests it in writing and specifies the exact commit hash to reset to.
- **STRICTLY FORBIDDEN:** Deleting branches on remote repositories (`git push <remote> --delete <branch>`) or deleting tags (`git push <remote> :refs/tags/<tag>`).
- **RECOMMENDATION:** Always prefer checking status with `git status`, inspecting changes with `git diff`, and creating clear new commits rather than rewriting history.

---

### 2. Filesystem and System Resources Safety (FILESYSTEM SAFETY)
- **OPERATIONAL SCOPE:** Read and write operations are strictly restricted to the designated workspace root (`{{WORKSPACE_ROOT}}`). Never operate on outside drives, arbitrary system directories (`C:\Windows`, `C:\Program Files`, root `C:\`, root `D:\`, `%USERPROFILE%`), or other user locations.
- **SOFTWARE INSTALLATION EXCEPTION:** Installing developer tools and packages via official package managers (`winget`, `brew`) or official vendor homepages is permitted as an exception to the workspace boundary. However, agents **MUST ALWAYS ASK FOR EXPLICIT USER CONFIRMATION FIRST**, even for Tier 1 tasks.
- **DELETE AND REMOVE COMMANDS:**
  - **STRICTLY FORBIDDEN:** Using dangerous wildcard commands such as `rmdir /s /q *`, `Remove-Item * -Recurse -Force`, or `del /f /s /q *.*` at directory roots or critical folders.
  - When cleaning up temporary or scratch files, agents MUST specify the exact, targeted file path (for example: `scratch_test.ts`, `.next/cache`).
  - Never arbitrarily delete folders containing user data or version control metadata (`.git`, `docs/`, `src/`, `data/`).

---

### 3. Database and Secrets Safety (DATABASE & SECRETS)
- **STRICTLY FORBIDDEN:** Running commands that drop or wipe entire databases (e.g. `drop database`, `prisma migrate reset --force`) in production or without explicit prior confirmation from the user.
- **STRICTLY FORBIDDEN:** Outputting, logging, or displaying sensitive information (API keys, secret tokens, private keys, passwords) to the console, terminal, or committing them into version control.

---

### 4. Explicit Confirmation for Risky Operations (EXPLICIT CONFIRMATION)
- If an unavoidable task requires deleting substantial directories or running any command carrying risk of irreversible data loss, the AI MUST pause and seek explicit confirmation from the user before executing.
