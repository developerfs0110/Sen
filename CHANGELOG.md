# Changelog / Nhật ký phiên bản — Sen (`sen-method`)

All notable changes to the **Sen** plugin and its version roadmap are documented in this file.
Mọi thay đổi quan trọng của plugin **Sen** và lộ trình các phiên bản đều được ghi nhận tại đây.

---

## Version Roadmap / Lộ trình phiên bản

| Version / Phiên bản | Codename / Tên gọi | Status / Trạng thái | Key Capabilities / Tính năng chính |
|---|---|---|---|
| **0.1.0** | **Sen Core** (Phần lõi) | **Released / Đã phát hành** (2026-11-06) | Always-on 3-tier core rule (`rules/AGENTS.md`), 7 `sen-*` skills, `PreToolUse` destructive-command guard hook, zero-token weekly update checker (`sen.lock.json` + `sen-update-notice.md`), bilingual docs (`README.md`, `README.en.md`, `docs/huong-dan.md`, `docs/guide.md`). |
| **0.1.1** | **Sen Core Hardening** (Gia cố bảo vệ & Đa nền tảng) | **Released / Đã phát hành** (2026-11-06) | System-level workspace write boundary guard (`write_file` / `edit_file` blocked outside workspace), expanded destructive SQL/Python/find patterns, native POSIX hook rewiring in `install.sh`, explicit risk-over-file-count rule in `rules/AGENTS.md`, official MIT `LICENSE`, and GitHub Actions CI (`ci.yml`). |
| **0.2.0** | **Sen Office** (`sen-office`) | **Released / Đã phát hành** (2026-11-06) | 3D Chibi designer-toy AI Office (`office/index.html`), zero-token `PostToolUse` telemetry hook (`office-post.ps1`/`.sh`), Local Office Server (`start-office.ps1`/`.sh`), 6-counter Inspector Drawer, Dual-Phase Output Visualizer (Phase 1 vs. Phase 2), 2D Compact Table, Replay Timeline Scrubber, Streamer Redact Mode, Stuck Loop Breaker (`3x` identical failure circuit breaker), Denied Command Copy Cards, and read-only Antigravity Quota Pill. |
| **0.3.0** | **Sen Orchestrator & Control Center** | **Released / Đã phát hành** (2026-11-06) | Stateful Task Manager & DAG Engine (`.agents/office/tasks.json`), Execution Contracts with `allowedPaths` File Locking (`Start-SenTask`), Integration & Testing Gate (`Complete-SenTaskReview` + `Test-SenDeliveryGate`), Crash Recovery (`Get-SenRecoveryState`), Structured Risk Scoring Engine (`Get-SenTaskRiskScore` with 32/32 automated tier tests), Quality Metrics (`Get-SenQualityMetrics`), Backlog Workflow (`docs/TODO.md` + `Add-SenBacklogItem`), Auto Restore Points (`New-SenRestorePoint`), 3-Layer Memory (`lessons.json`), Supply-Chain Pinned Commits (`packages.json`), and `📊 Quản lý Task & DAG` Control Center in `office/index.html`. |
| **0.3.1** | **Legal-by-Design, Clean Code 6D & Security Hardening** | **Released / Đã phát hành** (2026-11-07) | Mandatory `vn-law-check` (`required: true`), native PowerShell Vietnamese legal scanner `Invoke-SenVnLawScan` (`scripts/Sen.Legal.psm1`) with 100% parity with `scan.sh` + expired law detection (`NĐ 13/2023`, `52/2013`, `85/2021`), 6-dimension Clean Code engine `Measure-SenCodeHealth` + `sen-clean-code` skill (`ISO/IEC 5055` + `SonarQube` + `PSScriptAnalyzer` + `AI-Native 800L/45KB`), 5-module PowerShell split, and 5 security hardening fixes (zero `Invoke-Expression`, DOM XSS `escapeHtml`, Localhost CSRF `Origin` check + 64KB cap, `.NET`/`Node` recursive delete guard). |
| **0.4.0** | **Multi-Harness & Auto-Orchestration Edition** | **Released / Đã phát hành** (2026-11-07) | Multi-Harness Adapter (`scripts/Sen.Harness.psm1`: `Install-SenHarness`, `Uninstall-SenHarness`, `Test-SenHarnessStatus`, `ConvertFrom-SenHookPayload`) projecting `.agents/` Single Source of Truth across **Antigravity**, **Claude Code** (`CLAUDE.md`, `.claude/settings.json`), **Cursor** (`.cursor/rules/sen-method.mdc`, `.cursor/hooks.json`), **GitHub Copilot** (`.github/copilot-instructions.md`), **Windsurf** (`.windsurfrules`), and **Codex CLI / OpenCode** (`AGENTS.md`); polymorphic `guard.ps1` & `office-post.ps1`; 2-way 0-token Markdown-to-DAG sync (`Sync-SenPlanToTasks` & `Sync-SenTasksToMarkdown`); and mandatory *Best-of-the-Best* Expert Proof + **Resource Cost** column in `rules/AGENTS.md`. |

---

## [0.4.0] - 2026-11-07

### Added & Upgraded / Bổ sung & Nâng cấp — Multi-Harness Architecture (`Sen.Harness.psm1`), 2-Way 0-Token Plan/TODO Sync & Expert Evaluation Standard

- **VI:**
  1. **Kiến trúc Đa Nền Tảng & Đa Mô Hình (`scripts/Sen.Harness.psm1`):** Bổ sung `Get-SenSupportedHarnesses`, `Install-SenHarness`, `Uninstall-SenHarness`, `Test-SenHarnessStatus`, `Update-SenManagedBlock`, `Remove-SenManagedBlock` giúp chiếu quy tắc và kỹ năng từ `.agents/` sang **Antigravity**, **Claude Code**, **Cursor**, **GitHub Copilot**, **Windsurf**, và **Codex CLI / OpenCode** mà không nhân bản dữ liệu và bảo toàn 100% cấu hình sẵn có của người dùng.
  2. **Chuẩn hóa Đa hình Hook (`ConvertFrom-SenHookPayload` trong `guard.ps1` & `office-post.ps1`):** Tự động dịch tên công cụ và tham số của Antigravity (`run_command`, `write_file`), Claude Code (`Bash`, `Write`, `Edit`, `MultiEdit`, `Read`, `Grep`, `cwd`) và Cursor (`run_terminal_cmd`, `workspace_roots`, `target_file`) để duy trì lá chắn bảo mật và điều khiển chung một **3D AI Office**.
  3. **Đồng bộ Tự động 2 Chiều 0-Token (`Sync-SenPlanToTasks` & `Sync-SenTasksToMarkdown`):** Khi AI lưu file `docs/superpowers/plans/*.md` hoặc `docs/TODO.md`, `office-post.ps1` tự động bóc tách và nạp Task vào `.agents/office/tasks.json`; khi Task hoàn thành qua `Complete-SenTaskReview`, hệ thống tự động đánh dấu `[x]` ngược lại vào file Markdown.
  4. **Quy chuẩn Thẩm định Chuyên gia Khách quan & Cột Tài nguyên Tiêu tốn (`TASK-11` trong `rules/AGENTS.md`):** Bắt buộc chứng minh phương án đề xuất là *Best-of-the-Best* dưới góc nhìn chuyên gia độc lập và luôn hiển thị cột **Tài nguyên tiêu tốn (Resource Cost)** trong mọi bảng so sánh phương án.
  5. **Khóa Bằng chứng Theo Phiên (`TASK-20`), Bộ Thăm dò Sự sống 3 Tín hiệu & Thu dọn Chọn lọc (`TASK-21`, `TASK-22`: `Test-SenHungTasks` & `Clear-SenHungTasks`) & Cổng Đồng bộ Logic ↔ Tài liệu:** Khóa bằng chứng vật lý theo mốc `startedAt` của phiên kiểm toán, phát hiện hành vi bot/backend tự động chuyển tiếp tin nhắn/ảnh thiếu thông báo đồng ý (`BOT_DATA_FORWARDING_WITHOUT_CONSENT` theo NĐ 356/2025/NĐ-CP), thăm dò sự sống 3 tín hiệu (bảo vệ tuyệt đối task chạy lâu đang có `heartbeatAt`/sửa file trong `ActiveLongRunningIds`, bắt tức thì lỗi kẹt nhắc lệnh stdin `DeadlockedItems`, và thu dọn chọn lọc `StaleTaskIds`/`StaleSubagents`/`IdleSubagents`), chống treo `New-SenRestorePoint` (mặc định `$PWD.Path`, hỗ trợ `-WorkspacePath` và bỏ qua thư mục nặng), và kiểm tra đồng bộ bắt buộc giữa mã nguồn với `README.md`/`README.vi.md`, `CHANGELOG.md`, `docs/TODO.md`, `docs/CONTEXT.md` trong `Test-SenCapabilityParity`.

---

## [0.3.1] - 2026-11-07

### Added & Hardened / Bổ sung & Gia cố — Legal-by-Design (`Invoke-SenVnLawScan`), 6D Clean Code (`sen-clean-code`) & Security Hardening

- **VI:**
  1. **Tuân thủ Pháp lý Việt Nam xuyên suốt vòng đời (`Legal-by-Design` & `Invoke-SenVnLawScan` trong `scripts/Sen.Legal.psm1`):** Nâng `vn-law-check` thành gói bắt buộc (`required: true`), tích hợp bộ quét tự động 10 tín hiệu pháp lý Web/App (`FORM`, `TRACKING`, `TRACKING_PRELOAD`, `CONSENT_GATE`, `COMMERCE`, `AUTH`, `MARKETPLACE`, `AI`, `PERMISSIONS`, `SDK_TRACKING`, `ADS_SDK`, `FOREIGN_HOST`, `MOBILE_APP`, `ACCOUNT_DELETE`) và bắt lỗi trích dẫn văn bản hết hiệu lực (`NĐ 13/2023`, `NĐ 52/2013`, `NĐ 85/2021`) ngay tại cổng `Test-SenDeliveryGate -CheckVnLaw`.
  2. **Động cơ Kiểm định Clean Code 6 Chiều (`Measure-SenCodeHealth` & skill `sen-clean-code`):** Kiểm tra tự động 6 tiêu chuẩn công nghiệp (`ISO/IEC 5055 CWE-1080/1064/1121/1041/1069/561`, `SonarQube S104/S138/S134/CPD/S108/S1144`, `PSScriptAnalyzer`, và ngưỡng `AI-Native 800 dòng / 45 KB`); tách lõi PowerShell thành 5 mô-đun đạt điểm tuyệt đối `100/100`.
  3. **Gia cố 5 Điểm yếu Bảo mật Kỹ thuật Phần mềm:** Loại bỏ `Invoke-Expression` trong `Sen.psm1` (`CWE-78`), bọc `escapeHtml()` chống DOM XSS trong `office/index.html` (`CWE-79`), khóa `Origin` localhost chống CSRF (`CWE-352`) và giới hạn `Content-Length <= 64KB` (`CWE-400`) trong `start-office.ps1`, bổ sung chặn `.NET Directory::Delete` và `fs.rmSync` trong `guard.ps1`.

---

## [0.3.0] - 2026-11-06

### Added & Upgraded / Bổ sung & Nâng cấp — Stateful Agent Orchestrator, Risk Engine & AI Control Center

- **VI:**
  1. **Bộ máy Điều phối Agent & Quản lý Trạng thái Task (`New-SenTask`, `Get-SenTasks`, `Get-SenReadyTasks`, `Start-SenTask`, `Submit-SenTaskForReview`, `Complete-SenTaskReview`, `Test-SenDeliveryGate`, `Get-SenRecoveryState`):** Lưu trạng thái công việc có cấu trúc tại `.agents/office/tasks.json`, quản lý đồ thị phụ thuộc (DAG), khóa xung đột file (`File Lock` theo `allowedPaths`) khi nhiều Developer chạy song song, bắt buộc qua cổng `INTEGRATION & TESTING` (`ExitCode = 0`) trước khi nghiệm thu, và tự động khôi phục tiến độ sau khi đóng IDE.
  2. **Quy trình Backlog & Lưu việc cần làm (`Add-SenBacklogItem`, `docs/TODO.md`, `rules/AGENTS.md`):** Tự động lưu ý tưởng/công việc vào `docs/TODO.md` và `.agents/office/tasks.json` (`status = "backlog"`) khi người dùng nói *"lưu vào việc cần làm"*.
  3. **Bộ chấm điểm rủi ro xác định (`Get-SenTaskRiskScore`) & Tự động hóa 32/32 kịch bản phân cấp (`tests/TierScenarios.Tests.ps1`):** Chấm điểm rủi ro theo yếu tố và độ lan tỏa file (`SharedComponent`, `PublicApi`, `FileCount`, `Database/Auth/Payment/DataDeletion`), đạt `32/32` bài kiểm thử tự động trong `tests/tier-scenarios.md`.
  4. **Gia cố Khiên bảo vệ, Điểm khôi phục tự động (`New-SenRestorePoint` / `Restore-SenRestorePoint`) & Chuỗi cung ứng (`packages.json`):** Ghim `pinnedCommit` cho toàn bộ gói phụ thuộc (`superpowers`, `security-audit`, `vn-law-check`), chặn sửa trực tiếp `.git/config`, kiểm tra `allowedPaths` của Hợp đồng thực thi, tạo điểm khôi phục nhanh không cần `git reset --hard`, và sửa `tests/run.ps1` trả mã lỗi khác `0` khi thiếu file test.
  5. **Nâng cấp `Sen Office` thành `AI Control Center` (`office/index.html`) & Hệ thống Bộ nhớ 3 Lớp (`lessons.json`):** Bổ sung chế độ xem **📊 Quản lý Task & DAG**, hiển thị 4 chỉ số chất lượng (`Task Success Rate`, `First-Pass Rate`, `Rework Rate`, `Test Pass Rate`), quy mô dự án (`Mini / Standard / Enterprise`), chế độ cài nhanh (`Express Setup`), và Bộ nhớ 3 Lớp (`User · Project · Execution Lessons`).

---

## [0.2.0] - 2026-11-06

### Added / Tính năng mới — `sen-office` 3D Chibi AI Command Center & Dual-Phase Visualizer

- **EN:**
  1. **3D Chibi Designer-Toy AI Cast (`office/index.html`):** Upgraded all 9 AI roles + Boss to 3D-shaded Chibi characters (`radialGradient` skin/hair, blinking eyes with catchlights, rosy cheeks, chunky sneakers, role-specific outfits/props: Boss on red velvet sofa with aviator sunglasses & cigar, PM in purple blazer with tablet, BA with round glasses & blueprint, Scouts with beret/goggles & magnifier, Dev FE in hoodie & headphones, Dev BE in curly hair & glasses, female Tester with ponytail & clipboard, Security with visor & shield, Legal in suit & lawbook) with floor-level status rings, steaming coffee cups, dynamic desk monitors (`</>`, `✓_`, `🔍`, `!`), and Day/Night mode (`🌙/☀️`).
  2. **Zero-Token Hook Telemetry & Local Office Server (`hooks.json`, `scripts/office-post.ps1`/`.sh`, `scripts/start-office.ps1`/`.sh`):** Bundled `PostToolUse` hook maps tool calls (`grep_search`, `find_by_name`, `read_file`, `write_file`, `edit_file`, `run_command`) to 3D office roles with **0 LLM token cost** in `eco` mode; `start-office.ps1`/`.sh` serves live `/api/state` and `/api/config` on `127.0.0.1:47890` with automatic fallback to interactive Demo Mode when opened via `file://`.
  3. **10 Governance & UI Upgrades (inspired by [`khanh020905/my-office`](https://github.com/khanh020905/my-office), MIT License):**
     - **6-Counter Inspector Drawer & Clickable Place Cards:** Click any Chibi character or room zone (Server Room racks, Boss sofa, QA gate) to inspect `Read · Edit · Cmd · Time · Model · State` and system-verified file evidence.
     - **View Switcher & Replay Scrubber:** Switch between **🏢 3D Floor**, **📋 2D Compact Table**, **🎯 Dual-Phase Outputs**, and **🔀 Split View**, or scrub back through session steps (`⏪ Replay`).
     - **Stuck Loop Breaker (`Test-SenStuckLoop`):** Detects 3 consecutive identical failing tool+target calls and blocks the 4th attempt in `PreToolUse` so the agent stops burning tokens and asks the user.
     - **Automatic Secret Redaction (`Protect-SenRedactedText`) & Streamer Mode (`🔒`):** Masks Bearer tokens, `sk-`/`ghp_`/`xoxb-` keys, JWTs, `api_key=`, `password=`, and URL credentials before writing to `events.jsonl`, plus a UI blur toggle for screen-sharing.
     - **Denied Command Card with Copy Button:** Whenever `guard` blocks a destructive command, the walkie-talkie feed displays a red `🛑 BLOCKED` card with a 1-click Copy Command button for manual terminal execution.
     - **Read-Only Antigravity Quota Pill (`Get-SenAntigravityQuota`):** Displays model quota status in the top bar without modifying IDE files.
  4. **Dual-Phase Domain Output Visualizer (`Write-SenOfficeShowcase`, `skills/sen-office/SKILL.md`):** Side-by-side comparison of **Phase 1 (Post-Design & Plan Blueprint)** vs. **Phase 2 (Post-Delivery Verified Outputs & 4 Quality Gates: Tests, Build, Security, Legal)**.
- **VI:**
  1. **Dàn nhân vật Chibi 3D Designer-Toy (`office/index.html`):** Nâng cấp toàn bộ 9 vai trò AI + Boss lên phong cách Chibi 3D có khối cầu đổ bóng (`radialGradient`), mắt chớp long lanh, má hồng, giày sneaker đế trắng, trang phục/đạo cụ riêng biệt (Boss ngồi ghế sofa nhung đỏ đeo kính phi công hút xì gà, PM áo vest tím cầm tablet, BA tóc bob đeo kính tròn cầm bản vẽ, Scout đội mũ nồi/kính lúp, Dev FE mặc hoodie đeo tai nghe, Dev BE tóc xoăn đeo kính, nữ Tester cột tóc đuôi ngựa cầm bảng test, Bảo mật đeo kính chắn cầm khiên, Pháp lý mặc vest cầm sách luật), vòng trạng thái dưới sàn nhà, cốc cà phê bốc khói, màn hình máy tính đổi biểu tượng theo tác vụ và chế độ Ngày/Đêm (`🌙/☀️`).
  2. **Telemetry Hook 0-Token & Máy chủ Văn phòng Nội bộ (`hooks.json`, `scripts/office-post.ps1`/`.sh`, `scripts/start-office.ps1`/`.sh`):** Tự động ghi nhận bằng chứng công cụ thật ở chế độ `Tiết kiệm (0 token)` qua `PostToolUse` hook và phát trực tiếp tại `http://127.0.0.1:47890` (hoặc tự chuyển sang chế độ Demo khi mở trực tiếp file HTML).
  3. **Trọn bộ 10 nâng cấp hiển thị & quản trị (lấy cảm hứng từ [`khanh020905/my-office`](https://github.com/khanh020905/my-office), giấy phép MIT):** Ngăn kéo 6 ô đếm (`Đọc · Sửa · Lệnh · Thời gian · Model · Trạng thái`), đồ vật/phòng bấm được (`Place Cards`), bảng `📋 2D Gọn`, thanh tua lại lịch sử (`⏪ Replay`), cầu chì ngắt vòng lặp kẹt (`Test-SenStuckLoop` sau 3 lần lỗi liên tiếp), tự động che mật khẩu/API key (`Protect-SenRedactedText`) kèm nút `🔒 Ẩn nhạy cảm` khi chiếu màn hình, thẻ `🛑 LỆNH BỊ CHẶN` kèm nút chép lệnh, và ô báo hạn mức model (`Quota Pill`).
  4. **Khung Đầu ra 2 Giai đoạn (`Dual-Phase Output Visualizer`) & Skill `sen-office`:** So sánh trực quan **Giai đoạn 1 (Bản thiết kế & Kế hoạch dự kiến)** với **Giai đoạn 2 (Nghiệm thu thực tế & 4 cổng kiểm duyệt)**.

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
