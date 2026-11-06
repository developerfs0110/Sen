# Quy tắc dự án Sen (`sen-method`)

Tệp quy tắc cấp dự án áp dụng cho kho mã nguồn `sen-method` (`developerfs0110/Sen`).

## 1. Quy ước Git & Commit Message
- **Bắt buộc dùng tiếng Việt:** Tất cả nội dung bình luận khi commit và push Git (`git commit -m "..."`) đối với dự án này **phải được viết hoàn toàn bằng tiếng Việt**.
- **Định dạng khuyến nghị:** `<loại>: <mô tả ngắn gọn bằng tiếng Việt>`
  - Ví dụ:
    - `feat: bổ sung tính năng kiểm tra hạn mức token trong Sen Office`
    - `fix: xử lý lỗi đường dẫn khoảng trắng trên Windows`
    - `docs: cập nhật tài liệu hướng dẫn và điểm lưu trạng thái CONTEXT.md`
    - `chore: đồng bộ cấu hình plugin và kịch bản kiểm định`
- **Không tự ý viết lại lịch sử nhánh chính:** Không dùng `git push --force` hoặc `git filter-branch` trên nhánh `main`.

## 2. Cổng chất lượng bắt buộc (Quality Gates)
Trước khi tuyên bố hoàn thành hoặc thực hiện `git commit` / `git push`:
1. Chạy `powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Validate-Repo.ps1 .` — phải đạt **0 lỗi** (`rules/AGENTS.md` <= 6.000 bytes và <= 99 dòng; tất cả tệp `.ps1`/`.psm1` chỉ dùng mã ASCII; không rò rỉ đường dẫn cá nhân; không đứt liên kết Markdown).
2. Chạy `powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/run.ps1` — phải vượt qua **100% bài kiểm thử**.
3. Sau khi cập nhật mã nguồn, đồng bộ bản cài đặt trực tiếp tại `.agents/plugins/sen-method/` trong workspace.

