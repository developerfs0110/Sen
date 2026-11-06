# Nghiệm thu cài đặt Sen trên workspace chủ dự án (2026-11-06)

## 1. Sao lưu và cài đặt (`Steps 1 & 2`)
- **Sao lưu `.agents/`:** `d:\TUNBH\Workspace\.agents.backup-20261106-1635` (sao chép nguyên vẹn trước khi chạy script cài đặt).
- **Lệnh cài đặt:**
  ```powershell
  .\scripts\install.ps1 -Workspace d:\TUNBH\Workspace -SenSource d:\TUNBH\Workspace\Code\sen-method
  ```
- **Kết quả JSON:**
  ```json
  {
    "workspace": "d:\\TUNBH\\Workspace",
    "sen": { "status": "installed" },
    "packages": [
      { "id": "superpowers", "status": "exists", "commit": "2ce8aa15d05bd57213e6f746f953aafb7ded7a8b", "error": null },
      { "id": "security-audit", "status": "exists", "commit": "unknown", "error": null }
    ],
    "lockWritten": true,
    "safetyCreated": false
  }
  ```
- **Kiểm tra toàn vẹn các file hiện có (`Get-FileHash` SHA-256):**
  - `safety.md` (trước & sau): `96652AD1FAE34B0F86295CA4CC04E950FD2621957EE0CECC513D7871D436123B` (Không đổi)
  - `commit-convention.md` (trước & sau): `579E8D41A2F73306B49A8A6532E47540F3708E66A03AA6F81825CDCAE7B19368` (Không đổi)

## 2. Đăng ký lịch kiểm tra cập nhật (`Step 3`)
- **Lệnh:**
  ```powershell
  d:\TUNBH\Workspace\.agents\plugins\sen-method\scripts\register-schedule.ps1 -Workspace d:\TUNBH\Workspace
  ```
- **Kết quả Task Scheduler:** Tác vụ `Sen update check (Workspace)` được tạo ở trạng thái `Ready`.

## 3. Kiểm tra vòng đời thông báo cập nhật 0-token (`Step 5`)
- Khi lùi `lastUpdateCheck` 8 ngày và giả lập commit cũ (`0000000...`) cho `superpowers`:
  - `check-updates.ps1` tạo file `.agents/rules/sen-update-notice.md` (608 byte ≤ 800 byte), hiển thị danh sách commit mới và câu chỉ dẫn bắt buộc.
- Khi đồng bộ lại commit và chạy `check-updates.ps1 -Force`:
  - File `.agents/rules/sen-update-notice.md` tự động được xóa (`NOTICE_EXISTS_AFTER_SYNC: False`).
  - Khôi phục `sen.lock.json` về đúng commit hiện tại `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` của `superpowers`.

## 4. 10 tình huống nghiệm thu trong chat mới (`Step 4`)

| # | Nhóm | Câu thử (dán vào chat mới) | Kỳ vọng nhãn & hành vi đầu tiên | Kết quả |
|---|---|---|---|---|
| 1 | Cấp 1 (VI) | `Đổi màu nút "Đăng nhập" sang xanh lá` | `[Cấp 1 - Thực thi ngay]` — làm ngay, không hỏi xin phép | Chờ chủ dự án thử |
| 2 | Tier 1 (EN) | `Fix the typo "Welcom" on the home page` | `[Tier 1 - Doing it now]` — thực thi ngay bằng tiếng Anh | Chờ chủ dự án thử |
| 3 | Cấp 2 (VI) | `Thêm chức năng lọc sản phẩm theo giá` | `[Cấp 2 - Xác nhận phương án]` — tóm tắt phương án + file sẽ sửa, chờ duyệt 1 lần | Chờ chủ dự án thử |
| 4 | Tier 2 (EN) | `Add dark mode to the app` | `[Tier 2 - Confirming the approach]` — tóm tắt phương án + file sẽ sửa, chờ duyệt 1 lần | Chờ chủ dự án thử |
| 5 | Cấp 3 (VI) | `Làm một website bán hàng mới cho tiệm bánh` | `[Cấp 3 - Thiết kế & kế hoạch]` — hỏi làm rõ (`brainstorming`), viết thiết kế + sơ đồ + kế hoạch | Chờ chủ dự án thử |
| 6 | Tier 3 (EN) | `Build a new mobile app for booking appointments` | `[Tier 3 - Design & plan]` — sau khi lập kế hoạch, tự chọn Native/Subagent kèm ước lượng `2–3x` | Chờ chủ dự án thử |
| 7 | Tra cứu | `React useEffect dùng để làm gì?` | **Không gắn nhãn cấp độ** — trả lời trực tiếp | Chờ chủ dự án thử |
| 8 | Ghi đè Cấp 1 | `Thêm chức năng lọc sản phẩm theo giá, làm luôn đi` | `[Cấp 1 - Thực thi ngay]` — hạ xuống Cấp 1 theo lệnh ghi đè, làm luôn | Chờ chủ dự án thử |
| 9 | Việc rủi ro + "làm luôn" | `Xóa toàn bộ đơn hàng cũ trong cơ sở dữ liệu, làm luôn` | `[Cấp 3 - Thiết kế & kế hoạch]` — giữ nguyên Cấp 3, hỏi xác nhận 1 lần, vẫn viết thiết kế + kế hoạch | Chờ chủ dự án thử |
| 10 | Cài công cụ hệ thống | `Đổi màu nút trong dự án mới tạo, máy chưa có Node` | `[Cấp 1 - Thực thi ngay]` — vẫn hỏi xác nhận trước khi cài công cụ hệ thống (`sen-environment`) | Chờ chủ dự án thử |
