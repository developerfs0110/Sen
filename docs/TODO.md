# Danh Sách Việc Cần Làm (Backlog & Lộ Trình Nâng Cấp) — Sen (`sen-method`)

- **Cập nhật lần cuối:** 2026-11-10 (`v0.5.1` — Hoàn tất toàn bộ 27/27 hạng mục chính + 4 hạng mục bảo lưu chờ xác nhận)
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

- [x] **TASK-14 (P0): Hệ thống Kiểm toán Tuân thủ Quy trình 3 Tầng (`process-manifest.json`, Dự án `(*)` & Giai đoạn `(**)`) Không Lặp Vô Hạn**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu (2026-11-07).
  - **Nội dung:** Danh mục chuẩn `scripts/process-manifest.json` tự động cập nhật khi Sen lên phiên bản mới; lọc danh sách việc `(*)` cho từng dự án và `(**)` cho từng giai đoạn (`Stage 1..4`); kiểm tra bằng chứng vật lý đơn điệu (`Test-SenStageGate` & `Test-SenProjectCompliance`) ở từng giai đoạn và cuối dự án mà không bao giờ rơi vào vòng lặp vô hạn.

- [x] **TASK-15 (P0): Quy trình Thực thi Song song Lạc quan ("Trình bày trước — Làm luôn — Báo kết quả") & Cold-Start 1-File (`docs/CONTEXT.md`)**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu (2026-11-07).
  - **Nội dung:** Khi nhận yêu cầu mới (chỉ đọc duy nhất `docs/CONTEXT.md` khi mở phiên mới), trình bày đầy đủ phân tích *Best-of-the-Best* + bảng **Tài nguyên tiêu tốn**, tạo điểm khôi phục (`New-SenRestorePoint`) và lập tức triển khai song song ngay trong lúc người dùng đọc (ưu tiên Subagent chạy nền hoặc thực thi nối tiếp trong cùng lượt) mà không dừng chờ hỏi duyệt thông thường; hoàn tất báo cáo kèm hướng dẫn hoàn tác tức thì (`Restore-SenRestorePoint`).

- [x] **TASK-16 (P0): Vòng lặp Tự động Commit/Push & Kiểm tra – Sửa lỗi – Đẩy lại CI từ xa (`Get-SenRemoteCiStatus` & `Invoke-SenCiPushLoop`)**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu (2026-11-07).
  - **Nội dung:** Sau khi vượt qua cổng kiểm tra cục bộ (`Validate-Repo.ps1`, `Measure-SenCodeHealth`, `tests/run.ps1`), tự động commit (tiếng Việt) & push lên GitHub, kiểm tra trạng thái GitHub Actions CI từ xa (`Get-SenRemoteCiStatus`), nếu phát hiện lỗi CI thì tự động bóc tách bước lỗi (`FailedSteps`), sửa dứt điểm, chạy lại test và push lại (tối đa 3 vòng) cho đến khi CI xanh 100%.

- [x] **TASK-17 (P0): Khép kín Quy trình Mô phỏng Output 2 Giai đoạn (`Dual-Phase Output Simulation` — `Write-SenOfficeShowcase`) vào Luật lõi & Process Manifest**
  - **Nguồn:** Phát hiện phản biện trực tiếp của anh Gấu (2026-11-07) về việc bỏ sót bước Mô phỏng Output trong quy trình kiểm toán.
  - **Nội dung:** Đưa `Write-SenOfficeShowcase` (`.agents/office/showcase.json` — Giai đoạn 1: Blueprint kỳ vọng ở Stage 2 & Giai đoạn 2: Kết quả thực tế + 4 cổng ở Stage 4) vào Mục 8 của `rules/AGENTS.md`, `scripts/process-manifest.json` (`S2-DESIGN-SPEC`, `S4-CONTEXT-REPORT`), tự động hóa 0-token trong `Test-SenSingleStepEvidence` (`Sen.Harness.psm1`), và hiển thị đầy đủ trên `office/index.html` cùng bộ tài liệu hướng dẫn.

- [x] **TASK-18 (P0): Gói Kỹ Năng Chuyên Ngành Sáng Tạo (`Sen Creative Domain Packs`: Thiết kế Ảnh / Dựng Video / 3D với Git Sparse-Checkout, Tự động Dò Runtime & Lá Chắn Media Không Phá Hủy)**
  - **Nguồn:** Đề xuất tích hợp chọn lọc từ hệ sinh thái `vie-agentic-skills` (2026-11-07).
  - **Nội dung:** Tích hợp 3 gói kỹ năng tùy chọn (`media-image`: `store-screenshots`, `media-video`: `ffmpeg-skill`, `media-3d`: `blender-director`) qua `Install-SenCreativePack` sử dụng Git Sparse-Checkout (`--filter=blob:none --no-checkout` + `sparse-checkout set`) ghim commit bất biến; bổ sung dò tìm và lập kế hoạch cài đặt tự động cho `ffmpeg`, `imagemagick`, `blender` trong `scripts/tools.json` & `Get-SenToolStatus`; và bổ sung quy tắc bảo vệ chống ghi đè trực tiếp file media gốc (`ffmpeg -i <file> ... <same_file>`) trong `scripts/guard.ps1` & `scripts/guard.sh`.

- [x] **TASK-19 (P0): Giao thức Phản hồi Chờ Lịch sự Tức thì (`Instant-Ack Zero-Wait Protocol`) trước khi Phân tích / Tìm kiếm / Thực thi**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu (2026-11-07).
  - **Nội dung:** Bổ sung quy tắc bắt buộc `Instant-Ack` vào Mục 2 của `rules/AGENTS.md`, `scripts/process-manifest.json` (`S1-RISK`) và cổng đẳng cấu 5 tầng (`Test-SenCapabilityParity`): trước khi gọi bất kỳ công cụ nào (`read_file`, `run_command`, `search_web`, `invoke_subagent`) để phân tích, tra cứu hoặc thực thi, Sen bắt buộc phát ngay 1 câu thông báo chờ lịch sự có tên người dùng (ví dụ: *"Chào anh Gấu, chờ mình chút nhé, mình đang phân tích/tìm hiểu <nội dung>..."*); với tác vụ tra cứu/phân tích nặng (>2 lần gọi tool), phát thông báo chờ, đẩy sang Subagent nền (`research`/`self`) ở Turn 1 và kết thúc Turn 1 ngay để người dùng không bao giờ phải chờ trong im lặng.

- [x] **TASK-20 (P0): Khắc phục triệt để 4 lỗ hổng kiểm toán Sen `v0.4.0` (`Session-Scoped Evidence & Latching` trong `Test-SenStageGate`, `DeliveryGate` 0-new-task bypass, `Write-SenOfficeShowcase` Phase 2 overwrite, và `VnLawScan` Bot/Backend forwarding)**
  - **Nguồn:** Phản biện kiểm toán thực chiến của anh Gấu sau dự án `@ll25usBot` (2026-11-07).
  - **Kết quả (`v0.4.0`):** Đã khóa bằng chứng vật lý theo mốc thời gian phiên kiểm toán (`startedAt` / `SessionStartedAt` / `-PreserveLatched`) trong `Initialize-SenProcessAudit`, `Test-SenSingleStepEvidence` và `Test-SenStageGate`; chặn `Test-SenDeliveryGate` báo `PASS` giả khi không có Task mới trong phiên hiện tại; sửa `Write-SenOfficeShowcase` hợp nhất bảo toàn cả `phase1` và `phase2`; và mở rộng `Invoke-SenVnLawScan` phát hiện hành vi thu thập/chuyển tiếp tin nhắn & ảnh hóa đơn (`BOT_FORWARDING` / `BOT_DATA_FORWARDING_WITHOUT_CONSENT`) theo NĐ 356/2025/NĐ-CP.

- [x] **TASK-21 (P0): Bộ Giám sát & Thu dọn Tiến trình/Task Treo (`Test-SenHungTasks` & `Clear-SenHungTasks`), Chống Treo `New-SenRestorePoint` (`[Alias("WorkspacePath")]` & Bỏ qua Thư mục Nặng) và Cổng Đồng bộ Logic ↔ Tài liệu (`Test-SenCapabilityParity` L5 DocSync)**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu khi phát hiện phiên chat treo do lệnh chạy nền và yêu cầu đồng bộ Logic ↔ Tài liệu + Push Git trong quy trình chuẩn (2026-11-07).
  - **Kết quả (`v0.4.0`):** Đã triển khai `Test-SenHungTasks` & `Clear-SenHungTasks` trong `Sen.Orchestrator.psm1` và tích hợp thẳng vào `Test-SenDeliveryGate` + `S3-TDD-VERIFY`; nâng cấp `New-SenRestorePoint` nhận giá trị mặc định `$PWD.Path`, hỗ trợ `[Alias("WorkspacePath", "Path")]` và tự động bỏ qua thư mục nặng (`node_modules`, `.git`, `.agents`, `Code`, `dist`, `build`) để không bao giờ treo chờ stdin hoặc quét đệ quy; bổ sung quy tắc **Anti-Hang & Teardown** + **Logic-Doc Sync** vào `rules/AGENTS.md` và kiểm tra tự động `README_SYNC`, `VERSION_DOC_SYNC`, `TODO_CONTEXT_SYNC` trong `Test-SenCapabilityParity`.

- [x] **TASK-22 (P0): Bộ Thăm dò Sự sống 3 Tín hiệu & Thu dọn Chọn lọc (`3-Signal Liveness Probe & Selective Teardown` trong `Test-SenHungTasks` / `Clear-SenHungTasks`) — Bảo vệ Tuyệt đối Task Chạy Lâu Đang Hoạt động (`ActiveLongRunningIds`), Bắt Tức thì Stdin Deadlock (`DeadlockedItems`) và Thu dọn Zombie Idle (`IdleSubagents`)**
  - **Nguồn:** Phản biện chuyên sâu của anh Gấu về việc phân biệt tác vụ chạy lâu thực sự với tác vụ bị treo chết để không bao giờ giết nhầm tiến trình đang làm việc (2026-11-07).
  - **Kết quả (`v0.4.0`):** Đã nâng cấp `Test-SenHungTasks` kiểm tra 3 tín hiệu sự sống (`heartbeatAt`, thay đổi file thực tế trong `allowedPaths`, hoặc `lastStepTime` của subagent) để đưa các tác vụ chạy lâu hợp lệ vào danh sách được bảo vệ `ActiveLongRunningIds`; bắt tức thì lỗi kẹt nhắc lệnh tương tác stdin (`Supply values for the following parameters:`, `[Y/n]`, `Overwrite?`) vào `DeadlockedItems`; phân loại rõ `StaleSubagents` và `IdleSubagents`; và nâng cấp `Clear-SenHungTasks` + `rules/AGENTS.md` sang cơ chế **Selective Teardown** (`ProtectedLongRunningIds`) tuyệt đối không chạm vào tác vụ đang tiến triển.

---

## Nhóm `v0.5.1` — Truy Vết Yêu Cầu 7 Mắt Xích (RTM Engine), Bằng Chứng Sống (Stale Evidence), Phân Tích Tác Động Thay Đổi & Cổng Ghi Chú Phát Hành Song Ngữ (Đã hoàn tất trong `v0.5.1`)

- [x] **TASK-23 (P0): Động cơ Truy vết Yêu cầu Toàn trình 7 Mắt xích (`Register-SenRequirement`, `Get-SenRequirementTraceability`) & Động cơ Bằng chứng Sống (`Register-SenEvidence`, `Test-SenEvidenceValidity`)**
  - **Nguồn:** Tổng hợp đánh giá chuyên sâu từ 3 báo cáo độc lập (ChatGPT EPIC 01/02/03, Claude, Grok) và chỉ đạo của anh Gấu (2026-11-08).
  - **Kết quả (`v0.5.1`):** Đã triển khai trong `scripts/Sen.Governance.psm1` và tích hợp vào `Test-SenDeliveryGate`: quản lý đầy đủ chuỗi `REQ -> DESIGN -> TASK -> CODE -> TEST -> EVIDENCE -> ACCEPTANCE` (`.agents/office/requirements.json`, `.agents/office/evidence.json`), khử trùng lặp yêu cầu, phát hiện xung đột (`conflictWith`), chặn bàn giao khi còn `NEEDS_CLARIFICATION` hoặc thiếu kiểm thử, và tự động vô hiệu hóa bằng chứng (`status = "STALE"`, `verified = $false`) ngay khi file mã nguồn liên quan bị sửa sau mốc thời gian tạo bằng chứng.

- [x] **TASK-24 (P0): Máy Trạng thái Công việc Bất biến (`Invoke-SenTaskTransition`), Khóa Named Mutex Đa Tiến trình (`Save-SenTasks`), Phân tích Tác động Thay đổi DAG (`Invoke-SenChangeImpactAnalysis`) & Phục hồi Sau Sự cố (`Invoke-SenCheckpointResume`)**
  - **Nguồn:** Báo cáo ChatGPT (EPIC 04/05/06) và Claude P0 (2026-11-08).
  - **Kết quả (`v0.5.1`):** Đã bọc `Save-SenTasks` trong Named Mutex liên tiến trình (`Local\SenTasksMutex_*`) kèm hợp nhất task mới phát sinh song song; kiểm soát chuyển đổi trạng thái hợp lệ với nhật ký bất biến (`history`) và hạn khóa (`lockExpiresAt`); tự động lan truyền trạng thái `stale` cho toàn bộ task và bằng chứng phụ thuộc phía sau khi một yêu cầu/task thay đổi; và phục hồi sau crash kết hợp `git status --porcelain` (`UncommittedFiles`, `ExpiredLocks`, `PreventDuplicateIds`).

- [x] **TASK-25 (P0): Bảo vệ Đường dẫn Nhạy cảm/Symlink (`Test-SenSafeWorkspacePath`, `Resolve-SenWorkspaceRoot`), Chống Sửa Xóa Test (`Test-SenSuiteIntegrity`), Tự động Nâng Cấp Độ Giữa Chừng (`Test-SenMidTaskEscalation`), Chế độ Cấp 2 Nhanh (`ExpressMode`) & Cổng Ghi chú Phát hành Song ngữ Bắt buộc (`New-SenReleaseNote`, `Test-SenReleaseNoteGate`)**
  - **Nguồn:** Báo cáo Claude (P0/P1/P2), Grok (`ExpressMode`, `Set-SenEdition`, `Measure-SenTokenEstimate`), ChatGPT (EPIC 07) và chỉ đạo trực tiếp của anh Gấu về Ghi chú Phát hành Song ngữ (2026-11-08).
  - **Kết quả (`v0.5.1`):** Đã bổ sung `read_file` vào `PreToolUse` hook; chặn truy cập `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `id_rsa` và thoát khỏi workspace qua Symlink/Junction (`ReparsePoint`); tự động tìm gốc workspace từ thư mục con (`Resolve-SenWorkspaceRoot`); kiểm tra toàn vẹn số lượng `Assert-` (`Test-SenSuiteIntegrity`); nâng cấp `Invoke-SenVnLawScan` lên 3 trạng thái (`PASS`/`FAIL`/`UNKNOWN` kèm `LegalDisclaimer`); bổ sung `ExpressMode` (`ComplexityLevel` `C1`–`C4`), `Set-SenEdition` (`core`/`full`), `Uninstall-SenSelf` (`uninstall.ps1`/`.sh`, `register-schedule.sh`), và cổng kiểm duyệt Ghi chú Phát hành Song ngữ bắt buộc (`docs/releases/v0.5.1.vi.md`, `v0.5.1.en.md`, `RELEASE-NOTES.vi.md`, `RELEASE-NOTES.en.md`).

- [x] **TASK-26 (P0): Kiểm toán Bảo đảm Vận hành (`Sen-Audit.docx`), Vá 10 lỗ hổng Red-Team (`F-01..F-10` / `AT-01..AT-10`) & Đóng 3 Chốt Chặn Vật Lý Chống Quên (`Initialize-SenIntake`, `Test-SenIntakeCompleteness`, `Dirty-Tree Watchdog`)**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu khi thực hiện Operational Assurance Audit & FMEA theo `Sen-Review/Sen-Audit.docx` (2026-11-09).
  - **Kết quả (`v0.5.1`):** Đã vá toàn bộ 10 lỗ hổng `F-01..F-10` (bật mặc định `-EnforcePhysicalDiff = $true`, đóng lỗ hổng `If-Exists` cho task Cấp 2/3, nối cáp `claims.json`/`falsification-plans.json`, chặn nhảy cóc trạng thái và lệnh giả trong `Complete-SenTaskReview`, chặn `.NET`/`Python` ghi đè `.agents/office/*.json` trong `guard.ps1`, sửa Incremental Auto-Restore Point cho các file thứ 2..N, sửa Regex đường dẫn ổ đĩa Windows trong `Sync-SenPlanToTasks`, xóa hành vi tự tạo giả `showcase.json` trong `Test-SenSingleStepEvidence`), đồng thời bổ sung `Initialize-SenIntake` & `Test-SenIntakeCompleteness` và cảnh báo `[SEN WATCHDOG]` trong `office-post.ps1` (vượt qua 10/10 bài kiểm thử tấn công `AT-01..AT-10` với 0 lỗ hổng).

- [x] **TASK-27 (P0): Tối ưu Singleton 3D Office (`Get-SenOfficeTabStatus`), Thanh Tiêu Đề Tiến Trình 3 Tầng (`#processTitleBanner`), Chuẩn Hóa Quy Trình SDLC 8 Bước (`Get-SenProjectTechStack` & Approval-First Handshake) và Hàng Đợi Tự Động Chống Đụng Độ (`Test-SenTargetCollision` & `Register-SenTaskQueue`)**
  - **Nguồn:** Chỉ đạo trực tiếp của anh Gấu về tối ưu chống mở trùng tab Văn phòng 3D, hiển thị rõ tiêu đề công việc chính trên Văn phòng 3D, bổ sung khái niệm Tech Stack + quy trình SDLC chờ người dùng gật đầu trước khi code, và tự động xếp hàng đợi khi có phiên khác đang sửa cùng đích (2026-11-10).
  - **Kết quả (`v0.5.1`):** Đã triển khai `Get-SenOfficeTabStatus` & `Update-SenOfficeTabHeartbeat` (`.agents/office/tab-session.state` + beacon `/api/client-bye`) để nhận diện trình duyệt/profile/tab đang mở và chỉ mở tab mới khi tab cũ đã đóng; bổ sung thanh tiêu đề 3 tầng `#processTitleBanner` (`Mission` · `SDLC Stage` · `Live Action & Queue`) trong `office/index.html` và chặn `AUTO-WORK` ghi đè tên nhiệm vụ chính; bổ sung `Get-SenProjectTechStack` (khảo sát/đề xuất 5 tầng công nghệ `Frontend`, `Backend`, `Database`, `Infrastructure`, `Testing`) và chuẩn hóa quy trình SDLC Approval-First trong `rules/AGENTS.md` + `scripts/process-manifest.json`; đồng thời triển khai `Test-SenTargetCollision` (khóa hoàn tất 4 tín hiệu: `WorkingTreeClean`, `PushSynced`, `QuietWindowPassed`, `ActiveTaskLockFree`) và hàng đợi FIFO bền vững `Register-SenTaskQueue` (`.agents/office/task-queue.state`).

---

## Danh Sách Chờ Xác Nhận / Bảo Lưu (Deferred & Pending Review — `.agents/office/deferred-items.json` & Đề Xuất Từ 6 Repo GitHub)

> Các hạng mục dưới đây được tách riêng từ bảng tổng hợp 3 nguồn đánh giá (**Grok**, **ChatGPT**, **Claude**) và đợt phân tích **6 kho mã nguồn GitHub** (`remotion-shorts-skill`, `quivr`, `free-services`, `pm-kit`, `cc-skills`, `dereknguyen269`), lưu trữ minh bạch để nhắc anh Gấu xem xét và quyết định:

- [ ] **REPO-01 (`The-Vibe-Company/quivr` — `docs.py` & `denylist.py`) — [CHỜ ANH GẤU XÁC NHẬN]: Bổ sung `Test-SenDocPathIntegrity` (quét đường dẫn file trong Markdown & khóa báo cáo lịch sử) và `Test-SenDenylist` (băm `Salted SHA-256` chống lộ tên khách hàng/dự án mật khi commit)**
- [ ] **REPO-02 (`kv0906/cc-skills` — `ui-ux` & `no-ai-slop`) — [CHỜ ANH GẤU XÁC NHẬN]: Xây dựng cổng `Invoke-SenUiContextAudit` 3 tầng (quét `DESIGN.md`, `package.json` và Component có sẵn chống đẻ trùng `Button`/`Modal`) + áp dụng chuẩn câu ngắn `ASD-STE100 80%`**
- [ ] **REPO-03 (`dereknguyen269/free-services` — `services.yaml`) — [CHỜ ANH GẤU XÁC NHẬN]: Tích hợp danh mục 7 bộ kiến trúc `$0 Stack` kèm cảnh báo điểm nghẽn hạ tầng (`Where you hit the wall`) vào bước Thẩm định Chi phí Cấp 3 (`S2-EXPERT-COST`)**
- [ ] **REPO-04 (`social-media-skills/remotion-shorts-skill`) — [CHỜ ANH GẤU XÁC NHẬN]: Tích hợp gói sáng tạo tùy chọn thứ 4 `media-shorts` (`Install-SenCreativePack -Pack "media-shorts"`) biến Release Notes / số liệu thành video dọc `1080x1920` (TikTok/Reels/Shorts) có kiểm tra Safe Zone tự động**
- [ ] **REPO-05 (`kv0906/pm-kit` & `cc-skills/creating-client-proposals`) — [CHỜ ANH GẤU XÁC NHẬN]: Trang bị Ma trận `Product Judgment` (4 rủi ro sản phẩm + JTBD/RICE/Kano) cho BA Subagent ở Cấp 3 và mẫu xuất Proposal/Báo giá Tiếng Việt chuẩn PDF 16:10**
- [x] **W-09 (Grok Report) — [CHỜ ANH GẤU XÁC NHẬN]: Rút gọn văn phong marketing ("bán hàng") trong `README.md` sang thuần kỹ thuật**
  - **Lý do bảo lưu:** Tạm giữ nguyên bố cục và văn phong truyền cảm hứng, gần gũi hiện tại của anh Gấu; chờ anh Gấu xác nhận có muốn rút gọn sang văn phong kỹ thuật khô khan hay không.
- [x] **W-26 / IMP-19 (Claude Report) — [CHỜ ANH GẤU XÁC NHẬN]: Ẩn hoặc thay thế thông tin cá nhân công khai (SĐT, Email, STK ngân hàng nhận Donate) trong `README.md` và `docs/huong-dan.md`**
  - **Lý do bảo lưu:** Tuyệt đối không tự ý xóa thông tin liên hệ và tài khoản nhận ủng hộ (donate) của tác giả khi chưa có sự đồng ý của anh Gấu.
- [x] **IMP-13 / IMP-05 (Grok Report) — [KHÔNG ĐỒNG Ý / TỪ CHỐI]: Viết lại toàn bộ Core PowerShell sang Node.js/TypeScript hoặc Python runtime**
  - **Lý do từ chối:** Bảo toàn triết lý Core Zero-Dependency (không bắt cài `node_modules` cho phần lõi như chính Claude đã khen); vấn đề đa nền tảng đã được giải quyết triệt để bằng bộ script `.sh` và Hook Dispatcher.
- [ ] **IMP-10 / IMP-29 (Grok & Claude Report) — [KHÔNG ĐỒNG Ý / TỪ CHỐI]: Tách `Sen.Legal.psm1` và `sen-office` thành các Git repo độc lập bên ngoài**
  - **Lý do từ chối:** Tránh phân mảnh repo và đứt gãy kiểm thử đồng bộ; đã giải quyết bằng công tắc `Set-SenEdition -Edition core | full` ngay trong cùng một bộ cài.
