# Điểm Lưu Bối Cảnh Dự Án — Sen (`sen-method` `v0.4.0`)

- **Cập nhật lần cuối:** 2026-11-07
- **Cột mốc hiện tại:** `v0.4.0` (**Multi-Harness & Multi-Model Edition + 2-Way 0-Token Plan/TODO Auto-Sync + Kiểm Toán Quy Trình 3 Tầng + Chuẩn Thẩm Định Chuyên Gia Khách Quan**) — **Đã hoàn tất & Kiểm chứng**
- **Kho mã nguồn:** `https://github.com/developerfs0110/Sen.git` (nhánh `main`)
- **Quy ước Git của dự án:** Tất cả nội dung bình luận khi commit/push Git (`git commit`) bắt buộc viết bằng **tiếng Việt** (xem [AGENTS.md](../AGENTS.md)).

---

## 1. Trạng thái hiện tại
Toàn bộ 4 giai đoạn lớn (**`v0.1.x` Sen Core & Safety Shield**, **`v0.2.0` Sen Office 3D Chibi**, **`v0.3.x` Sen Orchestrator, Clean Code 6D & Legal-by-Design**, và **`v0.4.0` Multi-Harness Adapter, 2-Way Auto-Sync & 3-Tier Process Compliance Engine**) đều đã hoàn tất 100%, vượt qua toàn bộ **226/226 bài kiểm thử tự động trên 12 bộ test** (`tests/run.ps1` `0` lỗi), `Validate-Repo.ps1` (`0` lỗi), và `Measure-SenCodeHealth` đạt điểm tuyệt đối **`100/100`**.

## 2. Các quyết định thiết kế đã chốt (`v0.1.0` → `v0.4.0`)
- **Kiến trúc Đa Nền Tảng & Đa Mô Hình (`v0.4.0` — `scripts/Sen.Harness.psm1`):**
  - Giữ `.agents/` làm **Nguồn Chân Lý Duy Nhất (Single Source of Truth)** và chiếu cầu nối mỏng (`Install-SenHarness`, `Uninstall-SenHarness`, `Test-SenHarnessStatus`) sang 6 nền tảng: **Antigravity** (`.agents/rules/AGENTS.md`), **Claude Code** (`CLAUDE.md` + `.claude/settings.json`), **Cursor** (`.cursor/rules/sen-method.mdc` + `.cursor/hooks.json`), **GitHub Copilot** (`.github/copilot-instructions.md`), **Windsurf** (`.windsurfrules`), và **Codex CLI / OpenCode** (`AGENTS.md` gốc).
  - Bảo toàn 100% nội dung riêng của người dùng bằng khối quản lý `<!-- SEN-METHOD:START --> ... <!-- SEN-METHOD:END -->` và gộp JSON không phá hủy.
  - Chuẩn hóa đa hình Hook (`ConvertFrom-SenHookPayload` trong [guard.ps1](../scripts/guard.ps1) và [office-post.ps1](../scripts/office-post.ps1)) cho phép mọi IDE/CLI dùng chung lá chắn bảo mật và điều khiển chung một **3D AI Office**.
- **Đồng bộ 2 Chiều Tự động 0-Token chống quên (`v0.4.0` — `TASK-13`):**
  - **Chiều xuôi (`Sync-SenPlanToTasks` trong `office-post.ps1`):** Ngay khi AI vừa lưu file `docs/superpowers/plans/*.md` hoặc `docs/TODO.md`, Hook tự động bóc tách các mục `### Task N:` và `- [ ] **TASK-xx...**` nạp thẳng vào `.agents/office/tasks.json` mà không cần AI gõ lệnh thủ công.
  - **Chiều ngược (`Sync-SenTasksToMarkdown` trong `Complete-SenTaskReview`):** Ngay khi một Task vượt qua cổng nghiệm thu (`ExitCode = 0`), hệ thống tự động đánh dấu `- [x]` ngược lại vào `docs/TODO.md` và `docs/superpowers/plans/*.md`.
- **Hệ thống Kiểm toán Tuân thủ Quy trình 3 Tầng Không Lặp Vô Hạn (`v0.4.0` — `TASK-14`):**
  - **Tầng 0 ([process-manifest.json](../scripts/process-manifest.json)):** Danh mục tổng 12 bước quy trình chuẩn của Sen thuộc 4 giai đoạn (`Intake`, `Design & Plan`, `Execution & TDD`, `Handover & Final Gates`), tự động cập nhật khi Sen lên phiên bản mới (`Get-SenProcessCatalog`).
  - **Tầng 1 `(*)` & Tầng 2 `(**)` (`.agents/office/process-audit.json`):** Khởi tạo danh sách việc được chọn cho từng dự án `(*)` theo `Tier` và `ProjectScope`, phân bổ vào 4 giai đoạn `(**)` (`Initialize-SenProcessAudit`).
  - **Kiểm tra đơn điệu chống lặp vô hạn (`Test-SenStageGate` & `Test-SenProjectCompliance`):** Kiểm tra bằng chứng vật lý trên ổ đĩa ở từng giai đoạn và cuối dự án (`0 token`, `< 20ms`, `Read-Only Predicate` + `Monotonic Latch`), tích hợp trực tiếp vào `Test-SenDeliveryGate`.
- **Quy chuẩn Thẩm định Chuyên gia Khách quan & Cột Tài nguyên Tiêu tốn (`v0.4.0` — `TASK-11`):**
  - Tích hợp vào [rules/AGENTS.md](../rules/AGENTS.md): Trước khi đề xuất phương án (Tier 2–3), bắt buộc đóng vai chuyên gia độc lập phân tích khách quan chứng minh phương án chọn là *Best-of-the-Best*, kèm cột **Tài nguyên tiêu tốn (Resource Cost: Token, Thời gian, CPU/RAM/Ổ cứng, Bảo trì)**.
- **Bộ máy Điều phối, Clean Code 6 Chiều & Pháp lý Việt Nam (`v0.3.0`–`v0.3.1`):**
  - Quản lý DAG và khóa file `allowedPaths` tại `.agents/office/tasks.json`, kiểm định 6 chiều `Measure-SenCodeHealth`, và quét 10 tín hiệu pháp lý Việt Nam `Invoke-SenVnLawScan` ([Sen.Legal.psm1](../scripts/Sen.Legal.psm1)).

## 3. Các cổng chất lượng đã kiểm chứng
- `scripts/Validate-Repo.ps1`: **ĐẠT (0 lỗi)** (`rules/AGENTS.md` = `5.966 bytes` <= 6.000 bytes & <= 99 dòng; toàn bộ `.ps1`/`.psm1` chuẩn ASCII; `README.md` đồng bộ 100% với `README.vi.md`).
- `Measure-SenCodeHealth`: **ĐẠT (`Healthy = True`, `Score = 100/100` trên 28 tệp mã nguồn)**.
- `tests/run.ps1`: **ĐẠT (226 / 226 bài kiểm thử trên 12 bộ test, bao gồm `Harness.Tests.ps1`)**.

## 4. Bước tiếp theo & Danh sách Việc cần làm (`docs/TODO.md`)
- Toàn bộ 14 hạng mục (`TASK-01` → `TASK-14`) trong [docs/TODO.md](./TODO.md) đã đạt trạng thái `[x] Đã hoàn thành`.
