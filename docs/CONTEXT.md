# Điểm Lưu Bối Cảnh Dự Án — Sen (`sen-method` `v0.3.0`)

- **Cập nhật lần cuối:** 2026-11-06
- **Cột mốc hiện tại:** `v0.3.0` (**Sen Orchestrator & Control Center** — Bộ máy Điều phối Agent & Quản lý Trạng thái Task thực sự, Chấm điểm Rủi ro xác định `32/32`, Quy trình Backlog `docs/TODO.md`, Điểm khôi phục tự động, Ghim Commit Chuỗi cung ứng & Bộ nhớ 3 Lớp) — **Đã hoàn tất & Kiểm chứng**
- **Kho mã nguồn:** `https://github.com/developerfs0110/Sen.git` (nhánh `main`)
- **Quy ước Git của dự án:** Tất cả nội dung bình luận khi commit/push Git (`git commit`) bắt buộc viết bằng **tiếng Việt** (xem [AGENTS.md](../AGENTS.md)).

---

## 1. Trạng thái hiện tại
Cả 3 giai đoạn lớn (**`v0.1.0`/`v0.1.1` Sen Core & Gia cố bảo mật**, **`v0.2.0` Sen Office 3D Chibi**, và **`v0.3.0` Sen Orchestrator & AI Control Center**) đều đã hoàn tất 100%, vượt qua toàn bộ **211/211 bài kiểm thử tự động trên 11 bộ test** (`tests/run.ps1` `0` lỗi) và `Validate-Repo.ps1` (`0` lỗi).

## 2. Các quyết định thiết kế đã chốt (`v0.1.0` → `v0.3.0`)
- **Bộ máy Điều phối & Quản lý Trạng thái Task (`v0.3.0`):** Lưu trạng thái công việc có cấu trúc tại `.agents/office/tasks.json` (`New-SenTask`, `Get-SenTasks`, `Get-SenReadyTasks`, `Start-SenTask`, `Submit-SenTaskForReview`, `Complete-SenTaskReview`, `Test-SenDeliveryGate`, `Get-SenRecoveryState`, `Get-SenQualityMetrics`), tự động chặn xung đột file (`File Lock` theo `allowedPaths`) khi nhiều Developer chạy song song.
- **Quy trình Backlog chuẩn hóa (`TASK-02`):** Mọi yêu cầu *"lưu vào task cần làm"* được ghi tự động vào [docs/TODO.md](./TODO.md) và `.agents/office/tasks.json` (`Add-SenBacklogItem`).
- **Bộ chấm điểm rủi ro xác định (`Get-SenTaskRiskScore`):** Chấm điểm theo yếu tố rủi ro + độ lan tỏa file (`SharedComponent`, `PublicApi`, `FileCount`, `Database/Auth/Payment/DataDeletion`), vượt qua tự động `32/32` kịch bản trong [tests/tier-scenarios.md](../tests/tier-scenarios.md).
- **An toàn Thực thi & Chuỗi cung ứng:** Ghim `pinnedCommit` trong [scripts/packages.json](../scripts/packages.json), tạo điểm khôi phục nhanh (`New-SenRestorePoint` / `Restore-SenRestorePoint`), chặn sửa `.git/config` và kiểm tra `allowedPaths` trong [scripts/guard.ps1](../scripts/guard.ps1).
- **Trung tâm Điều hành 3D AI Office & Control Center:** Giao diện [office/index.html](../office/index.html) tích hợp 5 chế độ xem (`🏢 Sàn 3D`, `📋 2D Gọn`, `📊 Quản lý Task & DAG`, `🎯 Đầu ra 2 Giai đoạn`, `🔀 Chia đôi`) và **Bộ nhớ 3 Lớp** (`User · Project · Execution Lessons`).

## 3. Các cổng chất lượng đã kiểm chứng
- `scripts/Validate-Repo.ps1`: **ĐẠT (0 lỗi)** (`rules/AGENTS.md` <= 6.000 bytes & <= 99 dòng; toàn bộ `.ps1`/`.psm1` chuẩn ASCII; `README.md` đồng bộ 100% với `README.vi.md`).
- `tests/run.ps1`: **ĐẠT (211 / 211 bài kiểm thử trên 11 bộ test, bao gồm `TierScenarios.Tests.ps1` và `Orchestrator.Tests.ps1`)**.
- `bash -n`: **ĐẠT** trên toàn bộ script `.sh`.

## 4. Bước tiếp theo & Danh sách Việc cần làm (`docs/TODO.md`)
- Toàn bộ 10 hạng mục (`TASK-01` → `TASK-10`) trong [docs/TODO.md](./TODO.md) đã đạt trạng thái `[x] Đã hoàn thành`.
- Sẵn sàng sử dụng thực tế hoặc mở `http://127.0.0.1:47890/` (bấm tab **📊 Quản lý Task & DAG**) để giám sát trực tiếp.
