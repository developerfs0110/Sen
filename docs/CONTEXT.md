# Điểm Lưu Bối Cảnh Dự Án — Sen (`sen-method` `v0.4.0`)

- **Cập nhật lần cuối:** 2026-11-07
- **Cột mốc hiện tại:** `v0.4.0` (**Multi-Harness & Multi-Model Edition + Thực Thi Song Song Lạc Quan + Vòng Lặp Tự Chữa Lành CI Từ Xa + Đồng Bộ 2 Chiều 0-Token + Kiểm Toán Quy Trình 3 Tầng**) — **Đã hoàn tất & Kiểm chứng**
- **Kho mã nguồn:** `https://github.com/developerfs0110/Sen.git` (nhánh `main`)
- **Quy ước Git của dự án:** Tất cả nội dung bình luận khi commit/push Git (`git commit`) bắt buộc viết bằng **tiếng Việt** (xem [AGENTS.md](../AGENTS.md)).

---

## 1. Trạng thái hiện tại
Toàn bộ 4 giai đoạn lớn (**`v0.1.x` Sen Core & Safety Shield**, **`v0.2.0` Sen Office 3D Chibi**, **`v0.3.x` Sen Orchestrator, Clean Code 6D & Legal-by-Design**, và **`v0.4.0` Multi-Harness Adapter, Optimistic Parallel Execution, CI Auto-Heal Loop, 2-Way Auto-Sync & 3-Tier Process Compliance Engine**) đều đã hoàn tất 100%, vượt qua toàn bộ **227/227 bài kiểm thử tự động trên 12 bộ test** (`tests/run.ps1` `0` lỗi), `Validate-Repo.ps1` (`0` lỗi), `Measure-SenCodeHealth` đạt điểm tuyệt đối **`100/100`**, và GitHub Actions CI từ xa đạt trạng thái **`success` (100% xanh)**.

## 2. Các quyết định thiết kế đã chốt (`v0.1.0` → `v0.4.0`)
- **Thực thi Song song Lạc quan ("Trình bày trước — Làm luôn — Báo kết quả") & Cold-Start 1-File (`TASK-15` — [rules/AGENTS.md](../rules/AGENTS.md)):**
  - **Cold-Start 1-File:** Khi bắt đầu hoặc tiếp tục phiên trò chuyện mới, chỉ đọc duy nhất `docs/CONTEXT.md` trước khi phản hồi — không quét hàng loạt tệp làm chậm câu trả lời đầu tiên.
  - **Trình bày trước — Làm luôn — Báo kết quả:** Trình bày đầy đủ giải thích, chứng minh chuyên gia độc lập *Best-of-the-Best* + bảng **Tài nguyên tiêu tốn (Resource Cost)**, chụp điểm khôi phục (`New-SenRestorePoint`) và lập tức triển khai song song ngay trong lúc người dùng đọc (bằng Subagent chạy nền hoặc thực thi nối tiếp trong cùng lượt) mà không dừng chờ duyệt thông thường; báo cáo hoàn tất kèm lệnh hoàn tác tức thì (`Restore-SenRestorePoint`).
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

## 3. Các cổng chất lượng đã kiểm chứng
- `scripts/Validate-Repo.ps1`: **ĐẠT (0 lỗi)** (`rules/AGENTS.md` <= 5.750 bytes & <= 95 dòng; toàn bộ `.ps1`/`.psm1` chuẩn ASCII; `README.md` đồng bộ 100% với `README.vi.md`).
- `Measure-SenCodeHealth`: **ĐẠT (`Healthy = True`, `Score = 100/100` trên 28 tệp mã nguồn)**.
- `tests/run.ps1`: **ĐẠT (227 / 227 bài kiểm thử trên 12 bộ test, bao gồm `Harness.Tests.ps1`)**.

## 4. Bước tiếp theo & Danh sách Việc cần làm (`docs/TODO.md`)
- Toàn bộ 16 hạng mục (`TASK-01` → `TASK-16`) trong [docs/TODO.md](./TODO.md) đã đạt trạng thái `[x] Đã hoàn thành`.
