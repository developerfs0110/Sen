# Changelog

All notable changes to the Sen plugin will be documented in this file.

## [0.1.0] - 2026-11-06

### Added
- Initial plugin scaffold (`plugin.json`, `LICENSE`, `.gitattributes`), custom PowerShell 5.1 test runner (`tests/run.ps1`, `tests/Assert.ps1`), and repository validator (`scripts/Validate-Repo.ps1`).
- Always-on core rule `rules/AGENTS.md` (<= 6,000 bytes, < 100 lines) with 3-tier classification, localized labels, safety gates, token economy, and 32 manual tier scenarios (`tests/tier-scenarios.md`).
- Workspace and drive helpers (`Get-SenDriveCandidates`, `New-SenWorkspace`, `New-SenFileFromTemplate`) and workspace templates (`templates/safety.template.md`, `templates/profile.template.md`, `templates/CONTEXT.template.md`).
- Environment detection and install planner (`scripts/tools.json`, `Get-SenToolStatus`, `Get-SenInstallPlan`) supporting `PATH`, `extraPaths`, and version managers (`nvm`, `fnm`, `pyenv`).
- Package installer, `sen.lock.json` version lock, and non-interactive installers (`scripts/packages.json`, `scripts/install.ps1`, `scripts/install.sh`).
- Weekly zero-token update checker (`scripts/check-updates.ps1`, `scripts/check-updates.sh`), atomic backup/restore (`Get-SenUpdateStatus`, `Update-SenPackages`, `Restore-SenPackage`), and Windows Task Scheduler registration (`scripts/register-schedule.ps1`).
- Agent-facing `INSTALL.md` and 7 core `sen-*` skills (`sen-setup`, `sen-environment`, `sen-update`, `sen-onboarding`, `sen-delivery-report`, `sen-release-readiness` with 6 domain checklists, and `sen-skill-capture`) (TODO: replace `<owner>` placeholder in `INSTALL.md` and guides once the public GitHub repository URL is finalized).
- Bilingual documentation (`README.md`, `README.vi.md`) and complete beginner guides (`docs/guide.md`, `docs/huong-dan.md`).
- Bundled `PreToolUse` destructive-command guard hook (`hooks.json`, `scripts/guard.ps1`, `scripts/guard.sh`) to hard-block `git push --force`, `git reset --hard`, recursive deletes (`rm -rf`, `Remove-Item -Recurse`, `rmdir /s`), disk formatting, and repository deletion.
