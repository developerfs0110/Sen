---
name: sen-update
description: Checks for and applies updates to Sen and companion packages (superpowers, security-audit, vn-law-check) with atomic backups and rollback. Trigger when user says "kiểm tra cập nhật Sen", "check Sen updates", or when sen-update-notice.md is present.
---

# `sen-update` — Inspect, Apply, and Roll Back Sen Updates

## When to Trigger
- The user says **"kiểm tra cập nhật Sen"**, **"cập nhật Sen"**, **"check Sen updates"**, **"update Sen"**, or asks to roll back a Sen package.
- The file `<WORKSPACE>/.agents/rules/sen-update-notice.md` exists in the workspace and the user agrees to review or install the available updates.

## Language & Safety Rules
- Always communicate in the user's language (Vietnamese if they write in Vietnamese, English otherwise, or as set in `profile.md`).
- Never apply updates silently. Always list the packages with available updates and wait for explicit user approval before calling `Update-SenPackages`.
- Let `<WORKSPACE>` be the root of the current Sen workspace.

---

## Step-by-Step Workflow

### Step 1: Check Update Status (`Get-SenUpdateStatus`)
1. If `<WORKSPACE>/.agents/rules/sen-update-notice.md` exists, you may read it first for a quick preview, then verify live status via `Get-SenUpdateStatus`:
   ```powershell
   Import-Module -Name "<WORKSPACE>/.agents/plugins/sen-method/scripts/Sen.psm1" -Force
   $status = @(Get-SenUpdateStatus -Workspace "<WORKSPACE>")
   $available = @($status | Where-Object { $_.HasUpdate -eq $true })
   ```
2. If any package returned an `Error` (e.g., network offline), report the error clearly in the user's language.
3. If `$available.Count -eq 0`:
   - Inform the user that all installed Sen packages (`sen-method`, `superpowers`, `security-audit`, and `vn-law-check` if installed) are already on the latest commit.
   - If `.agents/rules/sen-update-notice.md` still exists, run `check-updates.ps1 -Force` (Step 4) to clean it up and refresh `lastUpdateCheck`.

---

### Step 2: Present Available Updates and Ask Once
When `$available.Count -gt 0`:
1. Display a clear summary for each package in `$available`:
   - **Package ID** (`Id`)
   - **Current commit → Latest commit** (first 7 characters of `Current` and `Latest`)
   - **Recent changes (`Summary`)**: translate or summarize the commit log lines into plain language so the user knows what changed.
2. Ask the user **once** (for example via `ask_question` with `is_multi_select: true` or a direct confirmation prompt) which packages they want to update:
   - `(Recommended) Update all` / `(Khuyên dùng) Cập nhật tất cả`
   - Individual package IDs (`sen-method`, `superpowers`, `security-audit`, `vn-law-check`)
   - Skip / Not now
3. If the user chooses **Skip / Not now**, remove `<WORKSPACE>/.agents/rules/sen-update-notice.md` if present so the notice rule stops appearing on every turn, and stop here.

---

### Step 3: Apply Selected Updates (`Update-SenPackages`)
Run `Update-SenPackages` for the package IDs approved by the user:

```powershell
Import-Module -Name "<WORKSPACE>/.agents/plugins/sen-method/scripts/Sen.psm1" -Force
$results = @(Update-SenPackages -Workspace "<WORKSPACE>" -Ids @("<id1>", "<id2>"))
$results | Format-Table Id, Status, Commit, Error -AutoSize
```

What `Update-SenPackages` does automatically for each package:
- Creates an atomic backup of the current version in `<WORKSPACE>/.agents/.sen-backup/<id>-<commit>-<timestamp>/`.
- Clones the latest upstream commit and swaps the destination directory safely via sibling rename (`.sen-old`), automatically restoring the live directory if cloning or copying fails.
- Updates `<WORKSPACE>/.agents/sen.lock.json` and `.sen-commit` with the new commit hash and timestamp.
- When `sen-method` itself is updated, read `<WORKSPACE>/.agents/plugins/sen-method/CHANGELOG.md` and summarize the latest version highlights + roadmap for the user in their language.

---

### Step 4: Clear `sen-update-notice.md` (`check-updates.ps1` / `check-updates.sh`)
After `Update-SenPackages` completes, run the update checker with `-Force` so `<WORKSPACE>/.agents/rules/sen-update-notice.md` is automatically removed when all packages are up to date (and updated if the user only updated a subset):

- **Windows:**
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File "<WORKSPACE>/.agents/plugins/sen-method/scripts/check-updates.ps1" -Workspace "<WORKSPACE>" -Force
  ```
- **macOS / Linux:**
  ```bash
  bash "<WORKSPACE>/.agents/plugins/sen-method/scripts/check-updates.sh" -Workspace "<WORKSPACE>" -Force
  ```

*(If the user intentionally skipped some packages and does not want the notice to remain active, delete `<WORKSPACE>/.agents/rules/sen-update-notice.md` after `check-updates` runs.)*

Report the final update results (`Status`, new `Commit`) to the user and mention that they can roll back anytime if needed.

---

## Rollback Procedure (`Restore-SenPackage`)
If an updated package behaves unexpectedly or the user asks to revert a package to its previous version:

1. Run `Restore-SenPackage` for the target package ID:
   ```powershell
   Import-Module -Name "<WORKSPACE>/.agents/plugins/sen-method/scripts/Sen.psm1" -Force
   $restore = Restore-SenPackage -Workspace "<WORKSPACE>" -Id "<packageId>"
   $restore | Format-List Id, Status, Commit, Error
   ```
2. How `Restore-SenPackage` works:
   - Finds the most recent valid backup for `<packageId>` inside `<WORKSPACE>/.agents/.sen-backup/` (matched by `.sen-backup-meta.json`).
   - Backs up the currently installed directory first (so even a rollback can be undone).
   - Restores the previous snapshot into the package destination and updates `<WORKSPACE>/.agents/sen.lock.json` with the restored commit hash.
3. Confirm the restored commit hash (`$restore.Commit`) to the user in their language.
