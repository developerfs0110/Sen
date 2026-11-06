# Sen — Agent Installation Instructions (`INSTALL.md`)

> **Audience:** AI coding agents running inside Antigravity IDE.
> **Language rule:** Converse with the user in the language they used to prompt you (Vietnamese if they wrote in Vietnamese, English otherwise).

When a user asks you to install **Sen** from `https://github.com/developerfs0110/Sen` (or a fork/mirror URL they provided), follow these exact bootstrap steps:

## 1. Determine the Repository URL
- If the user provided a concrete repository URL in their prompt, use that URL.
- Otherwise, use `https://github.com/developerfs0110/Sen.git` (or replace `developerfs0110/Sen` with the fork URL you fetched this `INSTALL.md` from).

## 2. Fetch Sen into a Temporary Directory
Create a clean temporary directory on the user's machine and download the repository into it:

### Option A: `git` is available (preferred)
- **Windows (PowerShell):**
  ```powershell
  $senTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("sen-install-" + [System.Guid]::NewGuid().ToString("N"))
  git clone --depth 1 https://github.com/developerfs0110/Sen.git "$senTemp"
  ```
- **macOS / Linux (Bash):**
  ```bash
  SEN_TEMP="$(mktemp -d 2>/dev/null || mktemp -d -t sen-install)"
  git clone --depth 1 https://github.com/developerfs0110/Sen.git "$SEN_TEMP"
  ```

### Option B: `git` is NOT installed yet (ZIP fallback)
Download and extract the repository archive so you can read `skills/sen-setup/SKILL.md` (which will guide you through installing `git` in Step 1):
- **Windows (PowerShell):**
  ```powershell
  $senTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("sen-install-" + [System.Guid]::NewGuid().ToString("N"))
  $zipPath = "$senTemp.zip"
  Invoke-WebRequest -Uri "https://github.com/developerfs0110/Sen/archive/refs/heads/main.zip" -OutFile $zipPath
  Expand-Archive -LiteralPath $zipPath -DestinationPath $senTemp -Force
  Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
  $senTemp = (Get-ChildItem -LiteralPath $senTemp -Directory | Select-Object -First 1).FullName
  ```
- **macOS / Linux (Bash):**
  ```bash
  SEN_TEMP="$(mktemp -d 2>/dev/null || mktemp -d -t sen-install)"
  curl -fsSL "https://github.com/developerfs0110/Sen/archive/refs/heads/main.zip" -o "$SEN_TEMP/sen.zip"
  unzip -q "$SEN_TEMP/sen.zip" -d "$SEN_TEMP"
  rm -f "$SEN_TEMP/sen.zip"
  SEN_TEMP="$(find "$SEN_TEMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  ```

## 3. Execute `sen-setup`
Immediately read and follow [skills/sen-setup/SKILL.md](skills/sen-setup/SKILL.md) inside the downloaded directory (`$senTemp/skills/sen-setup/SKILL.md` or `$SEN_TEMP/skills/sen-setup/SKILL.md`).

- Pass `-SenSource "$senTemp"` (or `--sen-source "$SEN_TEMP"`) when running `scripts/install.ps1` / `scripts/install.sh` so Sen installs directly from the downloaded copy.
- Once setup completes, clean up the temporary folder by deleting the individual files or letting the OS temp cleaner remove it (never run destructive wildcard deletes on user directories).
