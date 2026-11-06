# Danh Sách Việc Cần Làm (Backlog & Lộ Trình Nâng Cấp) — Sen (`sen-method`)

- **Cập nhật lần cuối:** 2026-11-06 (`v0.3.0` — Hoàn tất toàn bộ 10/10 hạng mục)
- **Mục đích:** Lưu trữ có cấu trúc mọi công việc, ý tưởng và hạng mục cải tiến được Boss chỉ đạo `"lưu vào task cần làm"` trong quá trình trao đổi, đảm bảo không thất thoát giữa các phiên làm việc.
- **Trạng thái ký hiệu:** `[ ]` Chờ triển khai · `[~]` Đang thực hiện · `[x]` Đã hoàn thành

---

## Nhóm P0 — Cốt lõi Điều phối, Quản lý Trạng thái & Độ tin cậy (Đã hoàn tất trong `v0.3.0`)

- [x] **TASK-01: Xây dựng Bộ máy Điều phối Agent & Quản lý Trạng thái Task thực sự (`Task Manager & DAG Orchestrator` + `Execution Contract`)**
  - **Nguồn:** Đề xuất từ đánh giá ChatGPT (Sơ đồ Giai đoạn 2 & Mục 5.5, 6.1, 6.2).
  - **Kết quả (`v0.3.0`):** Đã triển khai `New-SenTask`, `Get-SenTasks`, `Save-SenTasks`, `Clear-SenTasks`, `Get-SenReadyTasks`, `Start-SenTask` (kiểm tra DAG & khóa xung đột file `allowedPaths`), `Submit-SenTaskForReview`, `Complete-SenTaskReview` (bắt buộc có `EvidenceCommand` và `ExitCode = 0`), `Test-SenDeliveryGate`, `Get-SenRecoveryState` và `Get-SenQualityMetrics` trong [scripts/Sen.psm1](../scripts/Sen.psm1).

- [x] **TASK-02: Bổ sung quy tắc "Lưu vào việc cần làm (`docs/TODO.md`)" vào quy trình chuẩn của Sen**
  - **Nguồn:** Ý tưởng trực tiếp của Boss khi làm việc thực tế.
  - **Kết quả (`v0.3.0`):** Đã bổ sung hàm `Add-SenBacklogItem` trong [scripts/Sen.psm1](../scripts/Sen.psm1) và cập nhật Mục 10 của [rules/AGENTS.md](../rules/AGENTS.md) để tự động lưu vào `docs/TODO.md` + `.agents/office/tasks.json` (`status = "backlog"`) khi người dùng nói *"lưu vào task cần làm"*.

- [x] **TASK-03: Bộ chấm điểm rủi ro có cấu trúc (`Structured Risk Scoring Engine` & Độ lan tỏa file)**
  - **Nguồn:** Đánh giá của ChatGPT (Mục 5.1) và Claude (Nhược điểm phân cấp).
  - **Kết quả (`v0.3.0`):** Đã triển khai hàm `Get-SenTaskRiskScore` trong [scripts/Sen.psm1](../scripts/Sen.psm1), tự động hóa kiểm thử 32 tình huống tại [tests/TierScenarios.Tests.ps1](../tests/TierScenarios.Tests.ps1) và điền kết quả kiểm chứng `32/32` trong [tests/tier-scenarios.md](../tests/tier-scenarios.md).

- [x] **TASK-04: Sửa lỗi dương tính giả trong `tests/run.ps1` và thiếu thư mục `office` trong `Update-SenPackages`**
  - **Nguồn:** Phát hiện từ đánh giá của ChatGPT (Mục 5.6) và rà soát đối chiếu mã nguồn.
  - **Kết quả (`v0.3.0`):** Đã sửa [tests/run.ps1](../tests/run.ps1) trả `exit 1` khi `$testFiles.Count -eq 0` hoặc `$global:TotalTests -le 0`, và bổ sung `"office"`, `"AGENTS.md"` vào `$senPayload` của `Update-SenPackages` & `Install-SenSelf`.

---

## Nhóm P1 — Bảo mật Chuỗi cung ứng, An toàn Thực thi & Đa nền tảng (Đã hoàn tất trong `v0.3.0`)

- [x] **TASK-05: Ghim phiên bản phụ thuộc (`Pinned Commit`) trong `scripts/packages.json` & Tạo Git Tag chính thức**
  - **Nguồn:** Đánh giá của Claude (Mục Chuỗi cung ứng và bảo mật).
  - **Kết quả (`v0.3.0`):** Đã thêm `pinnedCommit` đã thẩm định cho `superpowers`, `security-audit`, `vn-law-check` trong [scripts/packages.json](../scripts/packages.json) và gắn Git Tag chính thức (`v0.1.0`, `v0.1.1`, `v0.2.0`, `v0.3.0`).

- [x] **TASK-06: Nâng cấp `Safety Shield` theo Hợp đồng Thực thi (`Execution Contract Filesystem Guard`) & Điểm khôi phục tự động (`Auto Restore Point`)**
  - **Nguồn:** Đánh giá của ChatGPT (Mục 5.2) và Claude (Đề xuất cải tiến).
  - **Kết quả (`v0.3.0`):** Đã bổ sung `New-SenRestorePoint` & `Restore-SenRestorePoint` trong [scripts/Sen.psm1](../scripts/Sen.psm1), chặn sửa trực tiếp `.git/config` và kiểm tra `allowedPaths` trong [scripts/guard.ps1](../scripts/guard.ps1) & [scripts/guard.sh](../scripts/guard.sh).

- [x] **TASK-07: Bộ điều hướng Hook đa nền tảng (`Cross-Platform Hook Dispatcher`)**
  - **Nguồn:** Đánh giá của Claude & Grok.
  - **Kết quả (`v0.3.0`):** Đã đồng bộ kiểm tra bảo vệ `.git/config` và phục vụ dữ liệu `tasks.json` / `lessons.json` trên cả PowerShell (`.ps1`) và Bash/Python (`.sh`).

---

## Nhóm P2 — Nâng cấp Sen Office Control Center, Đo lường Chất lượng & Hệ thống Bộ nhớ 3 Lớp (Đã hoàn tất trong `v0.3.0`)

- [x] **TASK-08: Nâng cấp `Sen Office` thành Bảng điều khiển Quản lý Dự án (`AI Control Center`)**
  - **Nguồn:** Đánh giá của ChatGPT (Mục 5.8 & 6.4) và Grok.
  - **Kết quả (`v0.3.0`):** Đã bổ sung chế độ xem **📊 Quản lý Task & DAG** trong [office/index.html](../office/index.html) cùng thanh tiến trình 7 bước, bảng Hợp đồng thực thi & Khóa file, và 4 thẻ chỉ số chất lượng (`Task Success Rate`, `First-Pass Rate`, `Rework Rate`, `Verified Test Pass Rate`).

- [x] **TASK-09: Xây dựng Hệ thống Bộ nhớ 3 Lớp (`User Memory` · `Project Memory` · `Execution Memory`)**
  - **Nguồn:** Đánh giá của ChatGPT (Mục 6.5).
  - **Kết quả (`v0.3.0`):** Đã triển khai `Add-SenExecutionLesson`, `Get-SenExecutionLessons`, `Get-SenMemorySnapshot` trong [scripts/Sen.psm1](../scripts/Sen.psm1) và hiển thị trực tiếp trên giao diện `Sen Office`.

- [x] **TASK-10: Chế độ Quy mô Dự án (`Mini` / `Standard` / `Enterprise`), Chế độ Cài đặt Nhanh (`Express Setup`) & Đồng bộ `README`**
  - **Nguồn:** Đánh giá của ChatGPT (Mục 5.4), Claude và Grok.
  - **Kết quả (`v0.3.0`):** Đã bổ sung cấu hình `scale` (`mini | standard | enterprise`), thêm chế độ **Express 1-Step Mode** trong [skills/sen-setup/SKILL.md](../skills/sen-setup/SKILL.md), và thêm cổng kiểm tra chống lệch giữa `README.md` và `README.vi.md` trong [scripts/Validate-Repo.ps1](../scripts/Validate-Repo.ps1).

---

## Nhóm P0 — Lộ Trình `v0.4.0` (Đa Nền Tảng / Đa Mô Hình & Chuẩn Thẩm Định Chuyên Gia)

- [x] **TASK-11 (P0): Quy chuẩn Thẩm định Chuyên gia Khách quan (`Best-of-the-Best Proof`) và Cột Tài nguyên Tiêu tốn (`Resource Cost`)**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu (2026-11-07).
  - **Nội dung:** Trước khi đề xuất một phương án, bắt buộc đóng vai chuyên gia độc lập phân tích khách quan các phương án để chứng minh danh sách phương án đưa ra là tốt nhất và phương án đề xuất là tốt nhất trong các phương án tốt nhất (*Best-of-the-Best*). Ngoài ra, mọi bảng so sánh phương án bắt buộc có thêm cột **Tài nguyên tiêu tốn** (Token/Quota, Thời gian thực thi, CPU/RAM/Ổ cứng, Chi phí bảo trì).

- [x] **TASK-12 (P0): Triển khai Kiến trúc Đa Nền Tảng & Đa Mô Hình (`Multi-Harness Adapter v0.4.0`)**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu (2026-11-07).
  - **Nội dung:** Mở rộng Sen chạy xuyên suốt trên **Antigravity**, **Claude Code**, **Cursor**, **GitHub Copilot**, **Windsurf**, và **Codex CLI / OpenCode** từ nguồn chân lý duy nhất (`.agents/`), kèm chuẩn hóa đa hình cho `scripts/guard.ps1` và `scripts/office-post.ps1`.

- [x] **TASK-13 (P0): Tự động hóa 2 chiều 0-Token giữa Markdown (`plans/*.md`, `TODO.md`) và `.agents/office/tasks.json` (`Sync-SenPlanToTasks` & `Sync-SenTasksToMarkdown`)**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu (2026-11-07) về cơ chế chống quên cập nhật Task.
  - **Nội dung:** Hook `scripts/office-post.ps1` tự động nạp Task từ file Plan/TODO vào `tasks.json` ngay khi lưu; `scripts/guard.ps1` chặn sửa code Cấp 3 nếu có Spec mới mà chưa có Plan/Task; và `Complete-SenTaskReview` / `Test-SenDeliveryGate` tự động đánh dấu `[x]` ngược lại vào `docs/TODO.md` và `docs/superpowers/plans/*.md`.

- [ ] **TASK-14 (P0): Hệ thống Kiểm toán Tuân thủ Quy trình 3 Tầng (`process-manifest.json`, Dự án `(*)` & Giai đoạn `(**)`) Không Lặp Vô Hạn**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu (2026-11-07).
  - **Nội dung:** Danh mục chuẩn `scripts/process-manifest.json` tự động cập nhật khi Sen lên phiên bản mới; lọc danh sách việc `(*)` cho từng dự án và `(**)` cho từng giai đoạn (`Stage 1..4`); kiểm tra bằng chứng vật lý đơn điệu (`Test-SenStageGate` & `Test-SenProjectCompliance`) ở từng giai đoạn và cuối dự án mà không bao giờ rơi vào vòng lặp vô hạn.
