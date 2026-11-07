# Điểm Lưu Bối Cảnh Dự Án — Sen (`sen-method` `v0.4.0`)

- **Cập nhật lần cuối:** 2026-11-07
- **Cột mốc hiện tại:** `v0.4.0` (**Multi-Harness & Multi-Model Edition + Thực Thi Song Song Lạc Quan + Vòng Lặp Tự Chữa Lành CI Từ Xa + Đồng Bộ 2 Chiều 0-Token + Kiểm Toán Quy Trình 3 Tầng**) — **Đã hoàn tất & Kiểm chứng**
- **Kho mã nguồn:** `https://github.com/developerfs0110/Sen.git` (nhánh `main`)
- **Quy ước Git của dự án:** Tất cả nội dung bình luận khi commit/push Git (`git commit`) bắt buộc viết bằng **tiếng Việt** (xem [AGENTS.md](../AGENTS.md)).

---

## 1. Trạng thái hiện tại
Toàn bộ 4 giai đoạn lớn (**`v0.1.x` Sen Core & Safety Shield**, **`v0.2.0` Sen Office 3D Chibi & Dual-Phase Output Simulation**, **`v0.3.x` Sen Orchestrator, Clean Code 6D & Legal-by-Design**, và **`v0.4.0` Multi-Harness Adapter, Instant-Ack & 2-Turn Optimistic Parallel Execution, Dialectical Proof-Critique Loop, Zero-Amnesia 5-Layer Parity & Logic-Doc Sync Gate, Hung Task Watchdog, CI Auto-Heal Loop, 2-Way Auto-Sync, 3-Tier Session-Scoped Process Compliance Engine & Creative Domain Packs**) đều đã hoàn tất 100% (`21/21` hạng mục `TASK-01` → `TASK-21`), vượt qua toàn bộ **236/236 bài kiểm thử tự động trên 12 bộ test** (`tests/run.ps1` `0` lỗi), `Validate-Repo.ps1` (`0` lỗi), `Test-SenCapabilityParity` (`5/5` tầng, `73/73` hàm phủ Unit Test `100%`), `Measure-SenCodeHealth` đạt điểm tuyệt đối **`100/100`**, và GitHub Actions CI từ xa đạt trạng thái **`success` (100% xanh)**.

## 2. Các quyết định thiết kế đã chốt (`v0.1.0` → `v0.4.0`)
- **Giao thức Phản hồi Chờ Lịch sự Tức thì (`Instant-Ack`), Thực thi Song song 2 Nhịp (`2-Turn Handshake` — "Trình bày trước — Làm luôn — Báo kết quả"), Cổng Chặn `Pre-Edit Restore Point` & Cold-Start 1-File (`TASK-15`, `TASK-17`, `TASK-19` — [rules/AGENTS.md](../rules/AGENTS.md)):**
  - **Instant-Ack & Cold-Start Gate:** Trước khi gọi bất kỳ công cụ nào để phân tích, tìm kiếm hoặc làm việc, luôn phát ngay 1 câu thông báo chờ lịch sự có tên người dùng (ví dụ: *"Chào anh Gấu, chờ mình chút nhé, mình đang phân tích/tìm hiểu <X>..."*); với tác vụ nghiên cứu nặng (>2 lần gọi tool), phát thông báo chờ, khởi chạy Subagent nền (`research`/`self`) ở Turn 1 và kết thúc Turn 1 ngay lập tức. Khi mở phiên mới chỉ đọc duy nhất `docs/CONTEXT.md`; câu hỏi chẩn đoán/tra cứu trả lời thẳng với `0 file edits`.
  - **2-Turn Handshake (Xóa bỏ `"or inline"`):** Với yêu cầu Cấp 2–3, **Turn 1** trình bày phân tích *Best-of-the-Best* + Phản biện 7 mũi nhọn (`Invoke-SenDialecticalAudit`) + bảng **Tài nguyên tiêu tốn (Resource Cost)**, chụp điểm khôi phục (`New-SenRestorePoint`), khởi chạy Subagent nền (`invoke_subagent`) và **kết thúc Turn 1 ngay lập tức** để người dùng đọc ngay trên màn hình; **Turn 2** báo cáo kết quả đã kiểm chứng kèm lệnh hoàn tác (`Restore-SenRestorePoint`).
  - **Khóa Đẳng Cấu 5 Tầng (`Test-SenCapabilityParity`) & Mô phỏng Output 2 Giai đoạn (`Write-SenOfficeShowcase`):** Tự động kiểm tra đối chiếu 5 tầng trong `Validate-Repo.ps1` và tự động đồng bộ 0-token `.agents/office/showcase.json` (Phase 1 ở `S2-DESIGN-SPEC`, Phase 2 ở `S4-CONTEXT-REPORT`).
- **Vòng lặp Tự động Commit/Push & Tự Chữa Lành CI Từ Xa (`TASK-16` — `Get-SenRemoteCiStatus` & `Invoke-SenCiPushLoop` trong [Sen.Harness.psm1](../scripts/Sen.Harness.psm1)):**
  - Sau khi vượt qua cổng kiểm tra cục bộ (`Validate-Repo.ps1`, `Measure-SenCodeHealth`, `tests/run.ps1`), tự động commit (tiếng Việt) & push lên GitHub, kiểm tra trạng thái GitHub Actions CI từ xa (`Get-SenRemoteCiStatus`), nếu phát hiện lỗi CI thì tự động bóc tách bước lỗi (`FailedSteps`), sửa dứt điểm, chạy lại test và push lại (tối đa 3 vòng) cho đến khi CI xanh 100%.
- **Kiến trúc Đa Nền Tảng & Đa Mô Hình (`v0.4.0` — `TASK-12`, [Sen.Harness.psm1](../scripts/Sen.Harness.psm1)):**
  - Giữ `.agents/` làm **Nguồn Chân Lý Duy Nhất (Single Source of Truth)** và chiếu cầu nối mỏng (`Install-SenHarness`, `Uninstall-SenHarness`, `Test-SenHarnessStatus`) sang 6 nền tảng: **Antigravity** (`.agents/rules/AGENTS.md`), **Claude Code** (`CLAUDE.md` + `.claude/settings.json`), **Cursor** (`.cursor/rules/sen-method.mdc` + `.cursor/hooks.json`), **GitHub Copilot** (`.github/copilot-instructions.md`), **Windsurf** (`.windsurfrules`), và **Codex CLI / OpenCode** (`AGENTS.md` gốc).
  - Chuẩn hóa đa hình Hook (`ConvertFrom-SenHookPayload` trong [guard.ps1](../scripts/guard.ps1) và [office-post.ps1](../scripts/office-post.ps1)) cho phép mọi IDE/CLI dùng chung lá chắn bảo mật và điều khiển chung một **3D AI Office**.
- **Đồng bộ 2 Chiều Tự động 0-Token chống quên (`v0.4.0` — `TASK-13`):**
  - **Chiều xuôi (`Sync-SenPlanToTasks` trong `office-post.ps1`):** Tự động nạp Task từ file Plan mới nhất và `docs/TODO.md` vào `.agents/office/tasks.json` ngay khi lưu, đồng thời gán bằng chứng xác thực cho các mục `[x]`.
  - **Chiều ngược (`Sync-SenTasksToMarkdown` trong `Complete-SenTaskReview`):** Tự động đánh dấu `- [x]` ngược lại vào `docs/TODO.md` và `docs/superpowers/plans/*.md` ngay khi Task hoàn thành.
- **Hệ thống Kiểm toán Tuân thủ Quy trình 3 Tầng Không Lặp Vô Hạn (`v0.4.0` — `TASK-14`):**
  - Danh mục chuẩn 12 bước tại [process-manifest.json](../scripts/process-manifest.json) (`Get-SenProcessCatalog`), lọc danh sách việc `(*)` và `(**)` tại `.agents/office/process-audit.json` (`Initialize-SenProcessAudit`), và kiểm tra bằng chứng vật lý đơn điệu (`Test-SenStageGate` & `Test-SenProjectCompliance`).
- **Gói Kỹ năng Chuyên ngành Sáng tạo (`Sen Creative Domain Packs` — `TASK-18`, [Sen.Packages.psm1](../scripts/Sen.Packages.psm1), [guard.ps1](../scripts/guard.ps1)):**
  - Tích hợp 3 gói tùy chọn (`media-image`: `store-screenshots`, `media-video`: `ffmpeg-skill`, `media-3d`: `blender-director`) qua `Install-SenCreativePack` dùng Git Sparse-Checkout (`--filter=blob:none --no-checkout` + `sparse-checkout set`) ghim commit bất biến; tự động dò runtime `imagemagick`, `ffmpeg`, `blender` trong [tools.json](../scripts/tools.json); và chặn cứng lệnh `ffmpeg` ghi đè trực tiếp lên chính file nguồn (`-i <file> ... <same_file>`).

## 3. Các cổng chất lượng đã kiểm chứng
- `scripts/Validate-Repo.ps1` & `Test-SenCapabilityParity`: **ĐẠT (0 lỗi, 5/5 tầng đẳng cấu + Logic-Doc Sync)** (`rules/AGENTS.md` <= 5.950 bytes & <= 95 dòng; toàn bộ `.ps1`/`.psm1` chuẩn ASCII; `README.md` đồng bộ 100% với `README.vi.md`; `TODO.md` đồng bộ với `CONTEXT.md` & `CHANGELOG.md`).
- `Measure-SenCodeHealth`: **ĐẠT (`Healthy = True`, `Score = 100/100` trên 28 tệp mã nguồn)**.
- `tests/run.ps1`: **ĐẠT (236 / 236 bài kiểm thử trên 12 bộ test, 73/73 hàm phủ Unit Test 100%)**.

## 4. Bước tiếp theo & Danh sách Việc cần làm (`docs/TODO.md`)
- Toàn bộ 21 hạng mục (`TASK-01` → `TASK-21`) trong [docs/TODO.md](./TODO.md) đã đạt trạng thái `[x] Đã hoàn thành` (bao gồm `Test-SenHungTasks` & `Clear-SenHungTasks` chống treo tiến trình/task, chống treo `New-SenRestorePoint`, cổng đồng bộ Logic ↔ Tài liệu trong `Test-SenCapabilityParity`, khóa bằng chứng theo phiên `startedAt`, và quét `BOT_FORWARDING` theo NĐ 356/2025/NĐ-CP).
