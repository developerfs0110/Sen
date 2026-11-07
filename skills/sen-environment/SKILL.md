---
name: sen-environment
description: Checks required and optional developer tools (including version managers like nvm, fnm, pyenv), prompts once via multi-select checklist for missing or outdated tools, and installs them from official sources (winget, brew).
---

# `sen-environment` — Environment & Tooling Setup

## When to Use
Run `sen-environment` right after the technology stack for a project is decided and **before writing code** (applicable to Node.js, Python, Flutter, Android SDK, Git, and any other runtime or CLI tool). Also invoked by `sen-setup` when Git is missing.

## Language & Safety Rules
- Always communicate with the user in the language they use (Vietnamese if they write in Vietnamese, English otherwise, or the language fixed in `profile.md`).
- Installing system tools or runtimes modifies the machine outside the workspace. This is an explicit, permitted exception to `.agents/rules/safety.md`, **but you must ALWAYS ask for user confirmation first**, even during a Tier 1 task.
- Only install from official sources (`winget`, `brew`, or the vendor's official `ManualUrl`). Never download or execute binaries from untrusted third-party URLs.

---

## Step-by-Step Workflow

### Step 1: Identify Tools for the Stack
1. Determine the list of tool IDs needed for the project (supported catalog IDs in `scripts/tools.json`: `git`, `node`, `python`, `flutter`, `android-sdk`, plus optional creative domain tools `ffmpeg`, `imagemagick`, and `blender`).
2. When the user installs or uses **Sen Creative Domain Packs** via `Install-SenCreativePack`:
   - `media-image` (`store-screenshots`) pairs with `imagemagick` (`ImageMagick.ImageMagick` on winget / `imagemagick` on brew, min `7.1.0`).
   - `media-video` (`ffmpeg-skill`) pairs with `ffmpeg` (`Gyan.FFmpeg` on winget / `ffmpeg` on brew, min `6.0.0`) and `node`.
   - `media-3d` (`blender-director`) pairs with `blender` (`BlenderFoundation.Blender` on winget / `--cask blender` on brew, min `4.0.0`).
3. At Tier 3, read the project's design document section **"Required Tools"** / **"Công cụ cần có"**.
4. Classify each tool as **`Required`** (mandatory for the project to build/run) or **`Optional`** (helpful extras, with a brief reason).

---

### Step 2: Probe the Machine Thoroughly (`Get-SenToolStatus` & `Get-SenInstallPlan`)
Do not rely solely on `<tool> --version` in the current `PATH`. Use `scripts/Sen.psm1`, which probes `PATH`, common installation directories (`extraPaths`), and version managers (`nvm`, `fnm`, `pyenv`):

```powershell
Import-Module -Name "<WORKSPACE>/.agents/plugins/sen-method/scripts/Sen.psm1" -Force

# Check individual status if needed: returns Status ('ok', 'outdated', 'missing'), Version, Source
$status = Get-SenToolStatus -Id "node"

# Build the filtered install plan (only returns 'missing' or 'outdated' tools)
$plan = @(Get-SenInstallPlan -Ids @("git", "node", "python") -Required @("git", "node"))
```

*(On macOS/Linux without PowerShell, pass `-Platform "macos"` to `Get-SenInstallPlan` if `pwsh` is available, or check `PATH`, `~/.nvm`, `~/.fnm`, `~/.pyenv`, and `/opt/homebrew/bin` before concluding a tool is missing.)*

1. Group the results into three categories when reporting briefly to the user:
   - **Already installed & meets minimum version (`ok`):** No action needed (mention detected version and source, e.g., `PATH` or `nvm`).
   - **Installed but needs upgrade (`outdated`):** Include in the checklist.
   - **Not installed (`missing`):** Include in the checklist.
2. If `$plan.Count -eq 0` (all tools are `ok`), report that the environment is ready and proceed immediately to coding without showing a prompt.

---

### Step 3: Ask Once with a Multi-Select Checklist (`ask_question`)
Present a **single** prompt covering the entire list of missing/outdated tools using `ask_question` with `is_multi_select: true`:

1. **Reminder right above the question:**
   Include this reminder at the top of the `question` text:
   - **English:** *"All items marked Required must be installed for this project to run."*
   - **Vietnamese:** *"Các mục có nhãn Bắt buộc đều cần cài thì dự án mới chạy được."*
2. **Pre-selection / Default-All Handling:**
   - Antigravity's `ask_question` supports `is_multi_select: true` but does not pre-check boxes by default. Keep the "default is install all" behavior by making the **first option**:
     - **English:** `(Recommended) Install all`
     - **Vietnamese:** `(Khuyên dùng) Cài tất cả`
   - *(If a future version of `ask_question` supports pre-checked options, pre-select all items and omit the "Install all" option.)*
3. **Individual Tool Options:**
   Follow the first option with one option per item in `$plan`, showing display name, target version, approximate size (`ApproxSizeMB`), and `Required` / `Optional` label:
   - **English format:** `Node.js 20 LTS · ~150 MB · Required` or `Android Studio / SDK · ~2500 MB · Optional — emulator & debugging`
   - **Vietnamese format:** `Node.js 20 LTS · ~150 MB · Bắt buộc (Required)` or `Android Studio / SDK · ~2500 MB · Tùy chọn (Optional — máy ảo & gỡ lỗi)`

**Example `ask_question` call:**
```json
{
  "questions": [
    {
      "question": "All items marked Required must be installed for this project to run. Which tools should I install now?",
      "is_multi_select": true,
      "options": [
        "(Recommended) Install all",
        "Node.js 18+ LTS · ~150 MB · Required",
        "Python 3.12 · ~100 MB · Optional — data scripts"
      ]
    }
  ]
}
```

4. **Handling Unchecked `Required` Items:**
   - If the user selects `(Recommended) Install all` (or `(Khuyên dùng) Cài tất cả`), install every item in `$plan`.
   - If the user selects specific items and omits a tool marked **`Required`**, state the consequence in **one single line** (for example: *"Không có Node.js thì không chạy được dự án này."* / *"Without Node.js, this project cannot run."*), then immediately respect their choice and continue **without asking again**.

---

### Step 4: Install Selected Tools via Official Package Managers (`winget` / `brew`)
For each selected tool in `$plan`:
1. **If `$item.Command` is present:**
   - **Windows (`winget`):** Run the command generated by `Get-SenInstallPlan`, e.g.:
     ```powershell
     winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements
     ```
   - **macOS / Linux (`brew`):** Run the Homebrew command, e.g.:
     ```bash
     brew install node
     ```
2. **If `$item.Command` is `$null` and `$item.ManualUrl` is present** (for example, Flutter on Windows):
   - Provide the official `ManualUrl` (`https://docs.flutter.dev/get-started/install`) and clear step-by-step instructions in the user's language.

---

### Step 5: Verify Installation (`-v` / `--version`)
After installation finishes:
1. Refresh `PATH` in the current PowerShell session so newly installed binaries can be found immediately:
   ```powershell
   $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
   ```
2. Run the tool's version command to confirm it works (e.g., `node -v`, `git --version`, `python --version`, `flutter --version`, `adb --version`) or re-run `Get-SenToolStatus -Id <id>`.
3. Report the verified version to the user. If the OS requires restarting the terminal or Antigravity IDE for the updated `PATH` to take effect across all shells, state that clearly in one line.
