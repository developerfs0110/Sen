📘 **Readme** | 🖥️ **[Sen-Tổng quan](https://raw.githack.com/developerfs0110/Sen/main/docs/sen-pitch-deck.html)** | 🏢 **[Sen-Office](https://raw.githack.com/developerfs0110/Sen/main/office/index.html)** | 🌐 **[English](README.en.md)**

# Sen

[![Sen CI](https://github.com/developerfs0110/Sen/actions/workflows/ci.yml/badge.svg)](https://github.com/developerfs0110/Sen/actions/workflows/ci.yml)

*"Sen: làm việc với đội AI một cách gọn, rõ, nhẹ."*

## Sen là gì

**Sen (`sen-method` `v0.5.1`)** là phương pháp luận và hệ điều hành điều phối đội ngũ AI agent đa nền tảng (**Google Antigravity IDE**, **Claude Code**, **Cursor**, **GitHub Copilot**, **Windsurf**, **Codex CLI / OpenCode**), kết hợp **Luật lõi siêu gọn (`<= 5.75 KB`)** với **Runtime thực thi tất định (`117` cmdlets, `9` kỹ năng `sen-*`, `0` phụ thuộc ngoài)**. Mọi yêu cầu công việc đều tự động được chấm điểm rủi ro (`Get-SenTaskRiskScore`) và phân thành 3 cấp độ để AI biết lúc nào làm ngay, lúc nào thực thi song song lạc quan kèm chứng minh — phản biện, và lúc nào cần thiết kế, lập kế hoạch cùng đội ngũ agent chuyên trách. Bạn luôn nắm quyền kiểm soát tiến độ, chất lượng mã nguồn, pháp lý và chi phí token bằng ngôn ngữ tự nhiên mà không cần học thuộc câu lệnh phức tạp.

## Vấn đề Sen giải quyết

- **Mất cân bằng kiểm soát:** AI hoặc hỏi quá nhiều với việc nhỏ nhặt, hoặc tự ý làm ẩu với việc lớn nhiều rủi ro (như xóa bảng dữ liệu, sửa xác thực, thanh toán).
- **Thiên kiến xác nhận (Confirmation Bias):** AI thông thường chỉ cố khen phương án đầu tiên của nó là đúng mà không tự phản biện, dễ bỏ sót trường hợp biên (Edge Cases), xung đột đồng thời (Race Conditions) và lỗ hổng bảo mật.
- **Thiếu minh bạch & Quên việc:** Người dùng không biết AI đang làm gì, dễ bị trôi việc giữa file kế hoạch Markdown và trạng thái thực tế, hoặc báo cáo "xong" giả tạo khi chưa chạy test thực chất.
- **Lãng phí token & Điểm mù chất lượng/pháp lý:** Token bị đốt vào việc đọc tràn lan hàng chục file ngay đầu phiên; mã nguồn sinh ra phình to vượt ngưỡng đọc của AI, hoặc vi phạm quy định bảo vệ dữ liệu cá nhân & nhãn AI theo pháp luật Việt Nam mới nhất (`Luật 91/2025/QH15`, `NĐ 356/2025/NĐ-CP`, `Luật AI 134/2025/QH15`, `Luật TMĐT 122/2025/QH15`).

## Năm nguyên lý

1. **Đúng mức kiểm soát:** Việc nhỏ tự chạy ngay (`Cấp 1`), việc vừa trình bày chứng minh kèm bảng chi phí rồi làm luôn song song (`Cấp 2`), việc lớn/rủi ro cao có thiết kế, phản biện 7 mũi nhọn và kế hoạch chi tiết (`Cấp 3` với sàn cứng `HardFloorTier3`).
2. **Minh bạch:** Mọi việc đều hiển thị rõ qua nhãn cấp độ, bảng **Tài nguyên tiêu tốn**, sơ đồ Mermaid, đồng bộ 2 chiều tự động (`[x]`), báo cáo nghiệm thu, và **Văn phòng 3D Chibi (`sen-office`)**.
3. **Có bằng chứng mới báo xong:** Không có kết quả kiểm thử thực tế (`ExitCode = 0`), chưa vượt qua cổng Clean Code 6 chiều (`100/100`), cổng Pháp lý Việt Nam và cổng Kiểm toán quy trình 12 bước (`Test-SenDeliveryGate`) thì tuyệt đối không được nói "xong".
4. **Gọn nhẹ mặc định:** Khởi động phiên chỉ đọc 1 file duy nhất (`Cold-Start 1-File` với `docs/CONTEXT.md`), luật lõi luôn dưới `5.75 KB`, dùng đúng model (`flash_lite`/`flash` cho Trinh sát, `pro`/`inherit` cho Kiến trúc/Bảo mật) và ghi nhận sự kiện bằng Hook `0 token`.
5. **Tích lũy:** Lưu bài học thực thi vào bộ nhớ 3 tầng (`Add-SenExecutionLesson`) và đóng gói quy trình lặp lại thành kỹ năng (`sen-skill-capture`) để dự án càng làm lâu càng thông minh hơn.

## Sen hoạt động thế nào

```mermaid
flowchart LR
    A["Yêu cầu công việc"] --> B["Phân cấp tất định (Get-SenTaskRiskScore)"]
    B --> C["Chứng minh - Phản biện & Chụp Restore Point"]
    C --> D["Thực thi Song song & Đồng bộ 2 Chiều (DAG / File Lock / _rev)"]
    D --> E["Cổng Kiểm duyệt (Clean Code 6D + STRIDE + Luật VN + 12 Bước)"]
    E --> F["Bàn giao, Báo cáo Nghiệm thu & Tự chữa lành CI (Invoke-SenCiPushLoop)"]
```

| Cấp độ | Nhãn hiển thị | Khi nào áp dụng | Cơ chế "Trình bày trước — Làm luôn — Báo kết quả" của Sen |
|---|---|---|---|
| **Tier 1 (Cấp 1)** | `[Cấp 1 - Thực thi ngay]` | Sửa giao diện/CSS, đổi nội dung chữ, sửa lỗi đã rõ nguyên nhân, refactor nhỏ trong 1–2 file, không đổi luồng dữ liệu | **AI làm ngay**, tự chạy kiểm tra (lint/test/build nếu có) và báo kết quả. **Bạn không cần chờ duyệt bước phụ.** |
| **Tier 2 (Cấp 2)** | `[Cấp 2 - Xác nhận phương án]` | Thêm tính năng mới, sửa logic chạm từ 3 file trở lên, cài thư viện mới, đổi API/component dùng chung | AI trình bày **Chứng minh *Best-of-the-Best* + Phản biện + Bảng Tài nguyên tiêu tốn**, chụp điểm khôi phục (`New-SenRestorePoint`), **thực thi ngay song song** trong lúc bạn đọc, qua cổng kiểm duyệt và gửi báo cáo nghiệm thu kèm lệnh hoàn tác 1-chạm (`Restore-SenRestorePoint`). |
| **Tier 3 (Cấp 3)** | `[Cấp 3 - Thiết kế & kế hoạch]` | Dự án mới, đổi kiến trúc, đụng cơ sở dữ liệu, xác thực, thanh toán, hoặc có nguy cơ mất dữ liệu (`HardFloorTier3`) | AI viết **Thiết kế (`brainstorming`) + Mô phỏng Output Phase 1 (`Write-SenOfficeShowcase`) + Phản biện 7 mũi nhọn (`Invoke-SenDialecticalAudit`) + Kế hoạch (`writing-plans`)**, chụp điểm khôi phục, điều phối Task DAG / khóa file `allowedPaths` / chống ghi đè tương tranh (`_rev`), đồng bộ `[x]` 2 chiều, cập nhật **Mô phỏng Output Phase 2** và kiểm toán đủ 12 bước trước khi bàn giao. |

*(Câu hỏi tra cứu thông tin thuần túy được AI trả lời thẳng, không gắn nhãn cấp độ — nhưng nếu câu hỏi ẩn chứa lệnh xóa dữ liệu/DB thì Sen vẫn tự động chặn ở Cấp 3.)*

### 9 Trụ cột Kỹ thuật Đã Kiểm chứng Thực nghiệm (`v0.5.1`)

1. **Vòng lặp Biện chứng "Chứng minh — Phản biện — Tối ưu" (`Invoke-SenDialecticalAudit`):** Bắt buộc chứng minh phương án đề xuất là *Best-of-the-Best* kèm cột **Tài nguyên tiêu tốn** (Token, Thời gian, CPU/RAM/Ổ cứng, Bảo trì), sau đó tự đóng vai Nhà phản biện tấn công phương án qua 7 mũi nhọn (Phản ví dụ, Biên BVA, Socratic, Karl Popper, Bảng quyết định, Tương tranh, Bảo mật STRIDE) rồi mới chốt phương án tối ưu không thể bác bỏ.
2. **Điều phối Task DAG, Khóa File, Kiểm soát Tương tranh Lạc quan & Thăm dò Sự sống 3 Tín hiệu (`Sen.Orchestrator.psm1`):** Quản lý tiến độ tại `.agents/office/tasks.json` (bảo vệ bằng khóa `Named Mutex` liên tiến trình trong `Save-SenTasks`), tự động mở khóa task khi xong phụ thuộc, khóa `allowedPaths` chống 2 Dev sửa đè cùng 1 file, kiểm soát phiên bản `_rev` trên từng Task chống mất dữ liệu đồng thời, giải phóng khóa treo qua `Unlock-SenTask`, và thăm dò sự sống 3 tín hiệu (`Test-SenHungTasks` & `Clear-SenHungTasks`: bảo vệ tuyệt đối task chạy lâu đang có heartbeat/sửa file trong `ActiveLongRunningIds`, bắt tức thì lỗi kẹt tương tác stdin trong `DeadlockedItems`, và thu dọn chọn lọc `StaleTaskIds` / `IdleSubagents`).
3. **Đồng bộ 2 Chiều Tự động 0-Token, Kiểm toán Quy trình 3 Tầng & Khóa Đẳng Cấu 6 Tầng (`Sen.Harness.psm1`):** Tự động nạp mọi file kế hoạch `docs/superpowers/plans/*.md` (hỗ trợ cả task tuần tự lẫn task song song) và `docs/TODO.md` vào `tasks.json` ngay khi lưu file (`Sync-SenPlanToTasks`), tự động tích `[x]` ngược lại Markdown khi hoàn thành (`Sync-SenTasksToMarkdown`), kiểm toán 12 bước theo phiên (`Test-SenStageGate` / `Test-SenProjectCompliance`), và **Khóa Đẳng Cấu 6 Tầng (`Test-SenCapabilityParity` — bao gồm `README_SYNC`, `VERSION_DOC_SYNC`, `TODO_CONTEXT_SYNC`, `L6-DocsParity` và `Test-SenReleaseNoteGate` tự động khóa đồng bộ tài liệu hướng dẫn & ghi chú phát hành)**.
4. **Cổng Clean Code 6 Chiều (`Measure-SenCodeHealth`):** Tự động quét giới hạn kích thước AI-Native (`<= 800 dòng / 45 KB` cho logic, `<= 1500 dòng` cho UI), hàm quá dài (`> 100 dòng`), lồng ghép quá sâu (`> 4 tầng`), khối `catch {}` rỗng, hàm chết và khối code trùng lặp (cả liên tệp lẫn nội tệp) theo chuẩn **ISO/IEC 5055 + SonarQube + PSScriptAnalyzer/ESLint**.
5. **Pháp lý Việt Nam Nội sinh (`Invoke-SenVnLawScan` — Legal-by-Design):** Quét 12 nhóm tín hiệu mã nguồn theo hệ thống luật Việt Nam mới nhất có hiệu lực **2025–2026** (**Luật Bảo vệ dữ liệu cá nhân `91/2025/QH15`**, **Nghị định `356/2025/NĐ-CP`**, **Luật Thương mại điện tử `122/2025/QH15`**, **Luật Trí tuệ nhân tạo `134/2025/QH15`**) với kết quả 3 trạng thái (`PASS` / `FAIL` / `UNKNOWN` kèm `LegalDisclaimer`): chặn nạp tĩnh script theo dõi trước khi xin phép, bắt buộc luồng xóa tài khoản (`ACCOUNT_DELETE`) trên Mobile App có đăng nhập, yêu cầu nhãn minh bạch AI và chặn dẫn chiếu văn bản hết hiệu lực (`NĐ 13/2023`, `NĐ 52/2013`, `NĐ 85/2021`).
6. **Lá chắn Bảo mật Tầng Hook & Bảo vệ Đường dẫn Nhạy cảm/Symlink (`guard.ps1` / `guard.sh` / `Test-SenSafeWorkspacePath`):** Chặn cứng 21 nhóm lệnh hủy dữ liệu/force-push/IEX/pipe (`curl|sh`), bảo vệ cả `read_file`/`write_file`/`edit_file` trước đường dẫn nhạy cảm (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `id_rsa`) và thoát khỏi workspace qua Symlink/Junction (`ReparsePoint`), tự động tìm gốc workspace từ thư mục con (`Resolve-SenWorkspaceRoot`), che giấu khóa bí mật (`Protect-SenRedactedText`), và ngắt vòng lặp lỗi 3 lần liên tiếp (`Test-SenStuckLoop`).
7. **Cầu nối Đa Nền tảng 6 Adapter / 7 IDE & CLI (`Install-SenHarness`):** Giữ `.agents/` làm Nguồn Chân Lý Duy Nhất và đồng bộ Luật, Kỹ năng cùng Ma trận Khả năng (`CapabilityLevel`: `full`, `partial` / `rules-and-skills`, `rules-only`) qua **6 bộ adapter phủ 7 nền tảng**: Antigravity, Claude Code, Cursor, GitHub Copilot, Windsurf, và Codex CLI / OpenCode.
8. **Vòng lặp Tự động Commit/Push & Tự Chữa lành CI Từ xa (`Invoke-SenCiPushLoop`):** Kiểm tra cổng cục bộ $\rightarrow$ commit & push $\rightarrow$ theo dõi GitHub Actions CI từ xa (`Get-SenRemoteCiStatus`) $\rightarrow$ nếu CI đỏ thì tự động bóc tách bước lỗi, sửa lỗi, test lại và push lại (tối đa 3 vòng) cho đến khi CI xanh 100%.
9. **Động cơ Truy vết Yêu cầu 7 Mắt xích (RTM), Bằng chứng Sống, Phân tích Tác động Thay đổi & Cổng Ghi chú Phát hành Song ngữ (`Sen.Governance.psm1`):** Quản lý ma trận truy vết `REQ -> DESIGN -> TASK -> CODE -> TEST -> EVIDENCE -> ACCEPTANCE` (`Register-SenRequirement`, `Get-SenRequirementTraceability`), tự động vô hiệu hóa bằng chứng (`STALE`) khi file mã nguồn thay đổi sau thời điểm kiểm thử (`Register-SenEvidence`, `Test-SenEvidenceValidity`), lan truyền trạng thái `stale` trên đồ thị DAG khi mở lại yêu cầu/task (`Invoke-SenChangeImpactAnalysis`), phục hồi sau sự cố kết hợp `git status` (`Invoke-SenCheckpointResume`), chống xóa `Assert-` (`Test-SenSuiteIntegrity`), tự động nâng cấp độ giữa chừng (`Test-SenMidTaskEscalation`), chế độ Cấp 2 Nhanh (`ExpressMode`), và bắt buộc xuất bản Ghi chú Phát hành Song ngữ Việt–Anh (`New-SenReleaseNote`, `Test-SenReleaseNoteGate` tại `docs/releases/`).
10. **Động cơ Kiểm chứng Đối kháng, Quản trị Bằng chứng, Phản biện Có Giới hạn & Tự động Đóng gói Kỹ năng (`Sen.Adversarial.psm1` & `Sen.BoundedLoop.psm1` — `AV-01..AV-10` & `BVC-01..BVC-10`):** Tách biệt 4 vai trò độc lập (`Proposer`, `Verifier`, `Adversary`, `Independent Judge`), bắt buộc Kế hoạch Làm sai 7 phần (`New-SenFalsificationPlan`, `Test-SenFalsificationPlan`), thực thi bằng chứng gắn mã băm SHA256 (`Register-SenClaim`, `Invoke-SenExecutableEvidence`, `Register-SenCounterexample`), lọc đánh giá mù (`Get-SenBlindReviewPackage`), phán quyết 4 trạng thái (`VERIFIED / CONDITIONAL / INCONCLUSIVE / REJECTED` qua `Invoke-SenIndependentVerdict`), khóa chống gian lận chỉ số (`Lock-SenQualityBaseline`, `Test-SenAntiMetricGaming`), kiểm thử âm (`Invoke-SenGovernanceNegativeTest`), điều khiển vòng lặp phản biện có giới hạn 11 trạng thái (`Set-SenVerificationPolicy`, `Invoke-SenFindingTriage` phân loại `C0..C3` + tách `Gate 1 / Gate 2`, `Measure-SenAdversarialProgress`, `Invoke-SenBoundedRepairRound`, `New-SenEscalationDossier`, cô lập hiện trường & tự động chạy tiếp việc độc lập `Invoke-SenEscalationQuarantine`, `Invoke-SenBoundedVerificationScenarios`), và động cơ phát hiện chuỗi hành động lặp lại liên phiên kèm đóng gói kép `SKILL.md` + script `0-token` (`Register-SenActionPattern`, `New-SenCapturedSkill, Invoke-SenPostCodePipeline`).

<!-- office screenshot: added with sen-office -->

🏢 **Văn phòng 3D Chibi (`sen-office` `v0.5.1` tích hợp sẵn — Tự động Mở/Đề xuất ở Turn 1 cho Cấp 2–3):** Với việc Cấp 2–3, Sen tự động khởi động hoặc đề xuất mở Văn phòng 3D ngay ở Turn 1 (`officeAction: auto_start / offer_enable` qua `start-office.ps1`), hoặc bạn có thể gõ `"mở văn phòng"` bất kỳ lúc nào để mở sàn 3D trực quan theo dõi 9 nhân vật Chibi AI + Boss trên ghế sofa đỏ, bộ đàm bằng chứng thực thi (`0 token` ở chế độ Tiết kiệm), ngăn kéo 6 ô đếm, thanh tua lại lịch sử, đồng hồ hạn mức trực tiếp từ `state.vscdb` và khung **Đầu ra 2 Giai đoạn** (Đối chiếu Thiết kế vs. Nghiệm thu). Xem trực tiếp tại **[Sen Office](https://raw.githack.com/developerfs0110/Sen/main/office/index.html)**.

## Bắt đầu nhanh

1. **Cài Antigravity IDE (hoặc Claude Code / Cursor / Copilot / Windsurf / Codex):** Mở IDE trên máy của bạn.
2. **Dán một câu cài đặt vào khung chat của AI:**
   ```text
   Hãy đọc https://github.com/developerfs0110/Sen/blob/main/INSTALL.md và cài Sen cho tôi.
   ```
3. **Làm theo hướng dẫn trên màn hình:** Chọn ổ đĩa đặt workspace, trả lời 4 câu ngắn để tạo hồ sơ cá nhân (`profile.md`), rồi gõ `"hướng dẫn tôi"` để trải nghiệm việc Cấp 1 đầu tiên.

👉 **Hệ thống Tài liệu & Trình chiếu Trực quan:**
- 🖥️ **[Sen-Tổng quan](https://raw.githack.com/developerfs0110/Sen/main/docs/sen-pitch-deck.html)** & 🏢 **[Sen Office](https://raw.githack.com/developerfs0110/Sen/main/office/index.html)**
- 📘 **[Hướng dẫn đầy đủ cho người mới bắt đầu](docs/huong-dan.md)**
- 📋 **[Ghi chú Phát hành Song ngữ (Release Notes VI)](docs/releases/RELEASE-NOTES.vi.md)** · **[Release Notes (EN)](docs/releases/RELEASE-NOTES.en.md)**
- 🎓 **[Cẩm nang Sinh viên Năm 1 IT: Giải bài toán khó Step-by-Step](docs/SINH-VIEN-IT-STEP-BY-STEP.md)**
- 📊 **[Tài liệu Showcase & Thuyết trình Chiến lược](docs/SEN-SHOWCASE-PITCH.md)**
- 🛡️ **[Báo cáo Kiểm chứng Hình thức & Phản biện Đối kháng Red-Team](docs/ADVERSARIAL-AUDIT-REPORT.md)** *(Đạt `251/251` tests, `110/110` hàm phủ Unit Test `100%`, `25/25` tasks hoàn tất)*

## Sen dùng những gì

Khi cài đặt, Sen tự động tải các gói kỹ năng mã nguồn mở uy tín từ kho gốc của tác giả (không sao chép mã nguồn vào repo Sen):

- **[superpowers](https://github.com/obra/superpowers)** — Tác giả: **Jesse Vincent** · Giấy phép: **MIT License** (bắt buộc).
- **[security-audit](https://github.com/cloudflare/security-audit-skill)** (`skills/security-audit`) — Tác giả: **Cloudflare** · Giấy phép: **MIT License** (bắt buộc).
- **[vn-law-check](https://github.com/mhfed/vn-law-check)** (`plugins/vn-law-check/skills/vn-law-check`) — Tác giả: **Contributors to vn-web-compliance-audit** (`mhfed`) · Giấy phép: **MIT License** (bắt buộc cho cổng kiểm duyệt pháp lý Việt Nam).
- **[vie-agentic-skills](https://github.com/huytran1120/vie-agentic-skills)** (`store-screenshots`, `ffmpeg-skill`, `blender-director`) — Tác giả: **Huy Trần (`huytran1120`)** · Giấy phép: **MIT License** (tùy chọn theo gói chuyên ngành sáng tạo **Creative Domain Packs**: `Install-SenCreativePack -Pack @("media-image", "media-video", "media-3d")` qua Git Sparse-Checkout, tự động dò runtime `imagemagick`/`ffmpeg`/`blender` và bảo vệ chống ghi đè file gốc `ffmpeg`).

## Tác giả & Ủng hộ

```text
Mr Bòn Bon - tunbh.study@gmail.com
(+84) 793.166.866 - (+84) 96.158.1163
Donate: TPBank - 61.222.666.888
```
