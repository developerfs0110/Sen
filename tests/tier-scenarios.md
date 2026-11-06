# Tier scenarios / Bộ tình huống phân cấp

Manual check for `rules/AGENTS.md`. / Kiểm tra thủ công rule lõi.

## How to run / Cách chạy
1. Open a **new chat** in a workspace with Sen installed, for each request. / Mở **chat mới** cho từng yêu cầu.
2. Paste the request as-is. / Dán nguyên văn yêu cầu.
3. Record the label of the first reply and whether the behaviour matches "Ghi chú". Stop the agent after the first reply if it starts real work. / Ghi nhãn của câu trả lời đầu và hành vi có khớp "Ghi chú" không. Dừng agent sau câu trả lời đầu nếu nó bắt đầu làm thật.
4. Pass = correct tier (or no label for lookups) and matching behaviour. / Đạt = đúng cấp (hoặc không nhãn với câu tra cứu) và đúng hành vi.

## Tier 1 / Cấp 1

| Yêu cầu | Cấp đúng | Ghi chú |
|---|---|---|
| Đổi màu nút "Đăng nhập" sang xanh lá | Cấp 1 | Làm luôn, không hỏi |
| Fix the typo "Welcom" on the home page | Tier 1 | Do it, no questions |
| Tăng cỡ chữ tiêu đề trang chủ lên 24px | Cấp 1 | CSS only |
| The footer overlaps the content on mobile, fix the CSS | Tier 1 | Self-check, report |
| Lỗi null ở `formatDate` khi ngày rỗng, thêm kiểm tra null | Cấp 1 | Bug with known cause |
| Rename variable `tmp` to `userCount` in `stats.js` | Tier 1 | Small refactor, 1 file |
| Sửa câu chào trong email xác nhận thành "Xin chào bạn" | Cấp 1 | Content change |
| Extract the repeated price formatting in `cart.js` into a helper in the same file | Tier 1 | 1 file, no data-flow change |

## Tier 2 / Cấp 2

| Yêu cầu | Cấp đúng | Ghi chú |
|---|---|---|
| Thêm chức năng lọc sản phẩm theo giá | Cấp 2 | Phương án + danh sách file, chờ duyệt một lần |
| Add dark mode to the app | Tier 2 | New feature |
| Cài thư viện `dayjs` để xử lý ngày | Cấp 2 | New library |
| Change the internal `getUser` API to return the avatar too | Tier 2 | Internal API change |
| Thêm nút xuất danh sách đơn hàng ra file Excel | Cấp 2 | New feature |
| Refactor error handling across the controllers, services and routes | Tier 2 | 3+ files |
| Thêm phân trang cho trang danh sách bài viết | Cấp 2 | New feature, several files |
| Add form validation with `zod` to the signup form | Tier 2 | New library |

## Tier 3 / Cấp 3

| Yêu cầu | Cấp đúng | Ghi chú |
|---|---|---|
| Làm một website bán hàng mới cho tiệm bánh | Cấp 3 | Dự án mới: brainstorming, thiết kế, kế hoạch |
| Add login with Google | Tier 3 | Auth |
| Tích hợp thanh toán MoMo | Cấp 3 | Payments |
| Migrate the database from SQLite to PostgreSQL | Tier 3 | Database, data-loss risk |
| Chuyển app từ kiến trúc monolith sang microservices | Cấp 3 | Architecture |
| Add a "delete my account and all data" feature | Tier 3 | Data deletion |
| Thêm bảng `orders` và quan hệ với `users` trong cơ sở dữ liệu | Cấp 3 | Database |
| Build a new mobile app for booking appointments | Tier 3 | New project; after plan, AI picks Native/Subagent-driven with "2–3x" note, no question |

## Exceptions / Ngoại lệ

| Yêu cầu | Cấp đúng | Ghi chú |
|---|---|---|
| React `useEffect` dùng để làm gì? | Không nhãn | Lookup: answer directly |
| What does HTTP 404 mean? | No label | Lookup |
| Lệnh git nào để xem lịch sử commit? | Không nhãn | Lookup |
| Thêm chức năng lọc sản phẩm theo giá, làm luôn đi | Cấp 1 | Override, không hỏi |
| Add dark mode, just do it | Tier 1 | Override |
| Xóa toàn bộ đơn hàng cũ trong cơ sở dữ liệu, làm luôn | Cấp 3 | Hỏi xác nhận một lần; nếu xác nhận vẫn viết thiết kế + kế hoạch, chỉ bỏ bước chờ duyệt |
| Switch auth to JWT, just do it | Tier 3 | Ask to confirm once; still write design + plan |
| Đổi màu nút trong dự án mới tạo, máy chưa có Node | Cấp 1 | Vẫn hỏi trước khi cài Node (`sen-environment`) |

## Results / Kết quả

| Date / Ngày | Model | Passed / Đạt | Notes / Ghi chú |
|---|---|---|---|
| | | /35 | |
