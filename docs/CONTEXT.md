# Điểm Lưu Bối Cảnh Dự Án — Sen (`sen-method` `v0.2.0`)

- **Cập nhật lần cuối:** 2026-11-06
- **Cột mốc hiện tại:** `v0.2.0` (**Sen Office** — Trung tâm điều hành AI 3D Chibi, 10 nâng cấp UI/Quản trị & Bộ hiển thị đầu ra 2 giai đoạn) — **Đã phát hành & đẩy lên GitHub**
- **Kho mã nguồn:** `https://github.com/developerfs0110/Sen.git` (nhánh `main`)
- **Quy ước Git của dự án:** Tất cả nội dung bình luận khi commit/push Git (`git commit`) bắt buộc viết bằng **tiếng Việt** (xem [AGENTS.md](../AGENTS.md)).

---

## 1. Trạng thái hiện tại
Cả **Phần 1 (`v0.1.0` + `v0.1.1` Sen Core & Gia cố bảo mật)** và **Phần 2 (`v0.2.0` `sen-office`)** đều đã hoàn tất, vượt qua toàn bộ bài kiểm thử (`170/170` bài test, `Validate-Repo.ps1` `0` lỗi), đã đẩy lên `origin/main` và đồng bộ vào thư mục plugin trực tiếp của workspace.

## 2. Các quyết định thiết kế đã chốt
- **Kiến trúc đóng gói tích hợp (Bundled Architecture):** `sen-office` nằm trực tiếp trong `developerfs0110/Sen` ([office/index.html](../office/index.html), [skills/sen-office/SKILL.md](../skills/sen-office/SKILL.md), [scripts/office-post.ps1](../scripts/office-post.ps1), [scripts/start-office.ps1](../scripts/start-office.ps1) và [scripts/Sen.psm1](../scripts/Sen.psm1)).
- **Dàn nhân vật 3D Chibi Designer-Toy:** Tất cả 9 vai trò AI + Boss sử dụng mô hình Chibi đổ bóng 3D với vòng trạng thái dưới mặt sàn (không có vòng màu che mặt), trang phục/phụ kiện đặc trưng theo vai trò, chớp mắt và hiệu ứng thở/gõ phím.
- **10/10 Cải tiến Thực tiễn Tốt nhất (tham khảo từ `khanh020905/my-office`, giấy phép MIT):**
  1. Biểu tượng và màu màn hình máy tính động theo trạng thái (`</>`, `✓_`, `🔍`, `!`)
  2. Thẻ thông tin khu vực phòng & tủ rack Phòng Server (`Place Cards`)
  3. Ngăn kiểm tra 6 chỉ số (`Read · Edit · Cmd · Time · Model · State` + bằng chứng xác thực từ hệ thống)
  4. Cốc cà phê bốc khói + Chế độ Ngày/Đêm (`🌙/☀️`)
  5. Bộ chuyển chế độ xem (`🏢 Sàn 3D | 📋 2D Gọn | 🎯 Đầu ra 2 Giai đoạn | 🔀 Chia đôi`) + Ẩn thông tin nhạy cảm (`🔒`)
  6. Thanh tua lại lịch sử sự kiện (`⏪`)
  7. Bộ ngắt vòng lặp kẹt lệnh (`Test-SenStuckLoop` — tự động chặn ở lần thử thứ 4 sau 3 lần thất bại liên tiếp trên cùng công cụ + mục tiêu)
  8. Tự động che giấu khóa bí mật (`Protect-SenRedactedText` trước khi ghi vào `events.jsonl`)
  9. Thẻ cảnh báo lệnh bị chặn (`🛑 LỆNH BỊ CHẶN` + nút Copy Command khi `guard` chặn lệnh nguy hiểm)
  10. Hiển thị hạn mức Antigravity chỉ đọc (`Get-SenAntigravityQuota`)
- **Bộ hiển thị đầu ra 2 giai đoạn (Dual-Phase Output Visualizer):** Đối chiếu Giai đoạn 1 (Bản thiết kế & Kế hoạch sau khi chốt phương án) với Giai đoạn 2 (Kết quả thực tế đã kiểm chứng & 4 Cổng chất lượng).

## 3. Các cổng chất lượng đã kiểm chứng
- `scripts/Validate-Repo.ps1`: **ĐẠT (0 lỗi)** (`rules/AGENTS.md` = `5,968 / 6,000` bytes, `80 / 99` dòng; toàn bộ `.ps1`/`.psm1` chuẩn ASCII; toàn bộ 8 kỹ năng `sen-*` hợp lệ).
- `tests/run.ps1`: **ĐẠT (170 / 170 bài kiểm thử trên 9 bộ test)**.
- `bash -n`: **ĐẠT** trên `guard.sh`, `office-post.sh`, `start-office.sh`, `install.sh`, `check-updates.sh`.
- Cổng Bảo mật & Bản quyền: **ĐẠT** (Giấy phép MIT [LICENSE](../LICENSE) + ghi công đầy đủ cho `obra/superpowers`, `cloudflare/security-audit-skill`, `mhfed/vn-law-check`, và `khanh020905/my-office`).

## 4. Bước tiếp theo
- Sẵn sàng sử dụng cho các dự án thực tế trong workspace.
- Gõ `"mở văn phòng"` bất cứ lúc nào để mở Trung tâm điều hành 3D AI Office, hoặc mở phiên trò chuyện mới (chỉ cần đọc tệp `docs/CONTEXT.md` này để khôi phục ngữ cảnh).
- Mọi lần commit/push Git tiếp theo của dự án này đều viết bình luận bằng **tiếng Việt**.
