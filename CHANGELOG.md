# Changelog / Nhật ký phiên bản — Sen (`sen-method`)

All notable changes to the **Sen** plugin and its version roadmap are documented in this file.
Mọi thay đổi quan trọng của plugin **Sen** và lộ trình các phiên bản đều được ghi nhận tại đây.

---

## Version Roadmap / Lộ trình phiên bản

| Version / Phiên bản | Codename / Tên gọi | Status / Trạng thái | Key Capabilities / Tính năng chính |
|---|---|---|---|
| **0.1.0** | **Sen Core** (Phần lõi) | **Released / Đã phát hành** (2026-11-06) | Always-on 3-tier core rule (`rules/AGENTS.md`), 7 `sen-*` skills, `PreToolUse` destructive-command guard hook, zero-token weekly update checker (`sen.lock.json` + `sen-update-notice.md`), bilingual docs (`README.md`, `README.en.md`, `docs/huong-dan.md`, `docs/guide.md`). |
| **0.1.1** | **Sen Core Hardening** (Gia cố bảo vệ & Đa nền tảng) | **Released / Đã phát hành** (2026-11-06) | System-level workspace write boundary guard (`write_file` / `edit_file` blocked outside workspace), expanded destructive SQL/Python/find patterns, native POSIX hook rewiring in `install.sh`, explicit risk-over-file-count rule in `rules/AGENTS.md`, official MIT `LICENSE`, and GitHub Actions CI (`ci.yml`). |
| **0.2.0** | **Sen Office** (`sen-office`) | **Planned / Kế hoạch tiếp theo** | 3D isometric virtual office monitor (browser tab), zero-token hook event telemetry + `PostToolUse` evidence log + optional AI narrative layer, click-on-agent inspector, `Tắt / Tiết kiệm / Chi tiết` token-mode switch with warning modal, real-time clock & comms duration log, Boss on red sofa + female Tester avatar, and dual-phase domain output simulation (post-design & post-delivery). |

---

## [0.1.1] - 2026-11-06

### Added & Hardened / Bổ sung & Gia cố (từ 3 bài đánh giá độc lập)

- **EN:**
  1. **System-level Workspace Write Boundary (`hooks.json`, `guard.ps1`, `guard.sh`):** Expanded `PreToolUse` matcher to `"run_command|write_file|edit_file"`. Any `write_file` or `edit_file` call targeting a path outside `workspacePaths` (and `~/.gemini`) is now hard-blocked (`decision: "deny"`) at the IDE hook level.
  2. **Expanded Destructive Command Patterns:** Added blocks for `find ... -delete`, `shutil.rmtree(`, and `DROP DATABASE / TABLE / SCHEMA` or `TRUNCATE TABLE`.
  3. **Cross-Platform Hook Wiring (`scripts/install.sh`):** On macOS/Linux, `install.sh` automatically rewrites `.agents/plugins/sen-method/hooks.json` to invoke `bash scripts/guard.sh` natively without requiring PowerShell.
  4. **Explicit Risk-First Priority (`rules/AGENTS.md`):** Clarified in Section 2 that risk signals override file count (*"even a 1-file change touching DB, auth, payments, or data deletion is Tier 3"*), while keeping `rules/AGENTS.md` under the `<= 6,000` byte cap.
  5. **Official MIT License & GitHub Actions CI:** Replaced placeholder `LICENSE` with full MIT License + Author block, added `.github/workflows/ci.yml` to run `Validate-Repo.ps1` and `tests/run.ps1` on every push/PR, and added CI status badge to all README files.
- **VI:**
  1. **Chặn cứng ghi file ngoài Workspace ở tầng Hook (`hooks.json`, `guard.ps1`, `guard.sh`):** Mở rộng matcher sang `"run_command|write_file|edit_file"`, tự động từ chối (`decision: "deny"`) mọi thao tác tạo/sửa file nằm ngoài thư mục workspace đang mở.
  2. **Mở rộng mẫu lệnh nguy hiểm:** Chặn thêm `find ... -delete`, `shutil.rmtree(`, và các lệnh SQL xóa bảng/cơ sở dữ liệu (`DROP DATABASE/TABLE/SCHEMA`, `TRUNCATE TABLE`).
  3. **Tự động chuyển Hook sang Bash trên macOS/Linux (`scripts/install.sh`):** Khi cài trên macOS/Linux, `install.sh` tự động cấu hình `hooks.json` chạy `bash scripts/guard.sh` mà không cần cài PowerShell.
  4. **Quy tắc "Rủi ro ghi đè số lượng file" (`rules/AGENTS.md`):** Nêu rõ trong Mục 2: dù chỉ sửa 1 file nhưng chạm CSDL, xác thực, thanh toán hoặc xóa dữ liệu thì vẫn bắt buộc là Cấp 3 (giữ nguyên dung lượng `< 6.000` byte).
  5. **Giấy phép MIT chính thức & GitHub Actions CI (`.github/workflows/ci.yml`):** Hoàn thiện file `LICENSE` chuẩn MIT kèm thông tin Tác giả và tự động chạy hơn 150 bài test trên GitHub Actions sau mỗi lần push.

---

## [0.1.0] - 2026-11-06

### Added / Tính năng mới

#### 1. Core Rule & Tier Classification / Rule lõi & Phân cấp tự động
- **EN:** Always-on core rule `rules/AGENTS.md` (`<= 6,000` bytes, `< 100` lines) with automatic 3-tier classification (`Tier 1 - Doing it now`, `Tier 2 - Confirming the approach`, `Tier 3 - Design & plan`), localized labels, safety gates, token economy, and 32 manual tier scenarios (`tests/tier-scenarios.md`).
- **VI:** Rule lõi luôn bật `rules/AGENTS.md` (`<= 6.000` byte, `< 100` dòng) tự động phân cấp mọi yêu cầu thành 3 cấp (`[Cấp 1 - Thực thi ngay]`, `[Cấp 2 - Xác nhận phương án]`, `[Cấp 3 - Thiết kế & kế hoạch]`), tiết kiệm token, cổng kiểm duyệt chất lượng và bộ 32 tình huống kiểm thử (`tests/tier-scenarios.md`).

#### 2. Two-Layer Safety Shield (Guard Hook + Safety Rule) / Khiên bảo vệ 2 lớp
- **EN:** Bundled `PreToolUse` destructive-command guard hook (`hooks.json`, `scripts/guard.ps1`, `scripts/guard.sh`) to hard-block (`decision: "deny"`) `git push --force`, `git reset --hard`, recursive deletes (`rm -rf`, `Remove-Item -Recurse`, `rmdir /s`), disk formatting, and repository deletion, paired with workspace boundary rules in `templates/safety.template.md`.
- **VI:** Tích hợp sẵn Hook chặn lệnh nguy hiểm `PreToolUse` (`hooks.json`, `scripts/guard.ps1`, `scripts/guard.sh`) chặn cứng ở tầng IDE các lệnh xóa đệ quy, format ổ đĩa, `git push --force`, `git reset --hard`, xóa nhánh/repo, kết hợp cùng rule giới hạn phạm vi thư mục `safety.md`.

#### 3. Seven Core Skills (`sen-*`) & Visual Roadmap Onboarding / 7 Skill lõi & Bản đồ quy trình trực quan
- **EN:** Agent-facing `INSTALL.md` and 7 core `sen-*` skills:
  - `sen-setup`: 9-step guided installer with an upfront visual roadmap & permission preview so beginners always know what step is running and why.
  - `sen-onboarding`: Interactive workspace tour, visual workflow map, and live Tier 1 hands-on exercise.
  - `sen-environment`: Deep tool detection (`PATH`, `extraPaths`, `nvm`, `fnm`, `pyenv`) and single-prompt multi-select installer (`winget` / `brew`).
  - `sen-update`: Version & changelog viewer, one-click updater (`sen-method`, `superpowers`, `security-audit`, `vn-law-check`), and atomic rollback (`Restore-SenPackage`).
  - `sen-delivery-report`: Evidence-backed acceptance report generator (`report.template.md`) + `docs/CONTEXT.md` checkpointing.
  - `sen-release-readiness`: Parallel 8-domain pre-release audit (`security-audit`, `vn-law-check`, plus 6 checklists under `checklists/`).
  - `sen-skill-capture`: Captures repeated workflows into workspace-local skills (`.agents/skills/<name>/`).
- **VI:** File khởi chạy `INSTALL.md` cho AI và 7 skill `sen-*` (`sen-setup` kèm bản đồ lộ trình 4 chặng cho người mới, `sen-onboarding`, `sen-environment`, `sen-update`, `sen-delivery-report`, `sen-release-readiness` kèm 6 bộ checklist, và `sen-skill-capture`).

#### 4. Installer, Lockfile & Zero-Token Weekly Update Check / Bộ cài đặt, Khóa phiên bản & Kiểm tra cập nhật 0-Token
- **EN:** PowerShell module `scripts/Sen.psm1`, non-interactive installers (`scripts/install.ps1`, `scripts/install.sh`), `sen.lock.json` version lock (tracking `sen-method` and companion packages), weekly zero-token update checker (`scripts/check-updates.ps1`, `scripts/check-updates.sh` writing `.agents/rules/sen-update-notice.md` only when updates exist), and Windows Task Scheduler registration (`scripts/register-schedule.ps1`).
- **VI:** Module `scripts/Sen.psm1`, script cài đặt (`install.ps1`, `install.sh`), file khóa phiên bản `sen.lock.json` (theo dõi cả `sen-method` và các gói đi kèm), script kiểm tra cập nhật định kỳ 0-token (`check-updates.ps1`, `check-updates.sh`) và đăng ký lịch tự động (`register-schedule.ps1`).

#### 5. Bilingual Documentation & Test Suite / Tài liệu song ngữ & Bộ kiểm thử
- **EN:** Bilingual `README.md` / `README.vi.md`, beginner guides `docs/guide.md` / `docs/huong-dan.md`, custom PowerShell 5.1 test runner (`tests/run.ps1`), and repository validator (`scripts/Validate-Repo.ps1`).
- **VI:** Tài liệu `README.vi.md` / `README.md`, cẩm nang cho người mới bắt đầu `docs/huong-dan.md` / `docs/guide.md`, và hơn 150 bài kiểm thử tự động.
