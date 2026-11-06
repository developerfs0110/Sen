[English](guide.md) | **Tiếng Việt**

# Hướng dẫn đầy đủ cho người mới bắt đầu với Sen

Tài liệu này dành cho bất kỳ ai muốn làm việc cùng AI một cách rõ ràng, an toàn và hiệu quả — kể cả khi bạn chưa từng dùng Git, chưa từng viết code, hay chưa từng nghe về "skill" và "plugin".

---

## 1. Năm khái niệm cốt lõi (Giải thích đời thường)

| Khái niệm | Ví dụ đời thường (1 câu) | Ví dụ cụ thể trong Sen |
|---|---|---|
| **AI agent** | Giống như một nhân viên trợ lý biết tự đọc tài liệu, tự chạy công cụ và làm việc thay vì chỉ trả lời câu hỏi miệng. | Khi bạn bảo sửa lỗi nút bấm, AI agent tự mở file code, sửa màu, chạy kiểm tra rồi báo cáo kết quả cho bạn. |
| **Antigravity** | Giống như tòa nhà văn phòng nơi bạn và đội trợ lý AI ngồi làm việc chung trên các thư mục dự án. | Bạn mở ứng dụng Antigravity IDE trên máy tính, gõ yêu cầu bằng tiếng Việt vào ô chat bên cạnh các file dự án. |
| **Rule (Quy tắc)** | Giống như nội quy công ty luôn treo trên tường mà mọi nhân viên phải tuân theo mỗi ngày mà không cần nhắc lại. | File `rules/AGENTS.md` của Sen luôn bật để nhắc AI phân cấp mọi yêu cầu thành Cấp 1, Cấp 2 hoặc Cấp 3 ngay dòng đầu tiên. |
| **Skill (Kỹ năng)** | Giống như cuốn sổ tay hướng dẫn từng bước cho một nghiệp vụ chuyên môn, chỉ mở ra xem khi cần làm đúng việc đó. | Khi cần bàn giao việc Cấp 2/3, AI mở skill `sen-delivery-report` để lập báo cáo nghiệm thu đúng chuẩn; khi cần rà soát bảo mật, AI mở `security-audit`. |
| **Plugin (Gói mở rộng)** | Giống như một bộ đồ nghề đóng hộp sẵn gồm cả nội quy (rule) lẫn các sổ tay kỹ năng (skill) để lắp vào văn phòng chỉ trong một lần. | `sen-method` là một plugin chứa rule lõi cùng 7 skill `sen-*`, giúp bạn cài đặt hoặc bật/tắt toàn bộ phương pháp Sen chỉ bằng một thao tác. |

---

## 2. Cài đặt từng bước (Có cách tải ZIP khi không dùng Git)

### Bước chuẩn bị: Cài Antigravity IDE
1. Tải và cài đặt **Antigravity IDE** lên máy tính của bạn (Windows, macOS hoặc Linux).
2. Mở Antigravity IDE và đăng nhập tài khoản của bạn.

### Cách A (Khuyên dùng): Dán một câu vào khung chat Antigravity
Mở khung chat của Antigravity và dán nguyên văn câu sau:

```text
Hãy đọc https://github.com/developerfs0110/Sen/blob/main/INSTALL.md và cài Sen cho tôi.
```

AI sẽ tự động đọc chỉ dẫn trong `INSTALL.md` và dẫn bạn qua quy trình cài đặt 9 bước của `sen-setup`:
1. **Kiểm tra công cụ:** AI kiểm tra máy đã có `git` chưa. Nếu chưa có, AI hỏi ý kiến bạn để cài tự động qua `winget` (Windows) hoặc `brew` (macOS). *(Lưu ý: `Node.js` chỉ cần cho văn phòng giám sát 3D `sen-office` sau này, chưa bắt buộc cho phần lõi Sen).*
2. **Chọn ổ đĩa đặt Workspace:** AI liệt kê các ổ đĩa còn trống và đề xuất ổ trống nhiều nhất (ví dụ `D:\Sen-Workspace`). Bạn có thể chọn ổ được đề xuất, giữ thư mục đang mở, hoặc chỉ định thư mục khác.
3. **Chọn gói pháp lý tùy chọn:** AI hỏi bạn có muốn cài thêm `vn-law-check` (kiểm tra tuân thủ pháp luật Việt Nam cho web/ứng dụng) hay không.
4. **Tạo khung thư mục & tải các gói kỹ năng:** Script cài đặt tạo các thư mục `.agents/rules/`, `.agents/plugins/`, `.agents/skills/`, `Code/`, `Templates/`, `docs/` (không bao giờ ghi đè file bạn đã có), đặt Sen vào `.agents/plugins/sen-method/`, tải `superpowers` và `security-audit`, tạo `.agents/rules/safety.md` và ghi file khóa phiên bản `.agents/sen.lock.json`.
5. **Điền thông tin cá nhân (`profile.md`):** AI hỏi bạn 4 câu ngắn (tên gọi, ngôn ngữ ưu tiên, công nghệ hay dùng, phong cách làm việc) để lưu vào `.agents/rules/profile.md`.
6. **Đăng ký lịch kiểm tra cập nhật hàng tuần:** Cài lịch kiểm tra ngầm mỗi tuần một lần (tốn 0 token khi không có bản mới).
7. **Mở Workspace mới:** Nếu bạn cài Sen vào một thư mục mới khác với cửa sổ đang mở, hãy vào **File → Open Folder**, chọn thư mục Workspace vừa tạo, rồi gõ `"hướng dẫn tôi"` trong cuộc chat mới.

### Cách B: Tải file `.zip` thủ công (Dành cho máy chưa có Git hoặc mạng chặn Git)
Nếu bạn không muốn dùng lệnh Git ngay từ đầu, bạn có thể tải file nén `.zip`:
1. Mở trình duyệt web và truy cập địa chỉ:
   `https://github.com/developerfs0110/Sen/archive/refs/heads/main.zip`
2. Giải nén file `.zip` vừa tải về vào một thư mục tạm trên máy (ví dụ `D:\Sen-main`).
3. Mở Antigravity IDE, gõ vào khung chat:
   ```text
   Hãy đọc file D:\Sen-main\INSTALL.md và cài Sen từ thư mục D:\Sen-main cho tôi.
   ```
4. AI sẽ dùng ngay bản giải nén trên máy của bạn và chạy tiếp các bước thiết lập Workspace như Cách A.

---

## 3. Kiểm tra cài đặt

Sau khi đã mở đúng thư mục Workspace có cài Sen trong Antigravity IDE, hãy mở một cuộc trò chuyện mới và thử dán câu sau:

```text
Tạo file Code/hello/README.md ghi lời chào của Sen
```

**Kết quả mong đợi:**
- Dòng đầu tiên trong câu trả lời của AI bắt đầu bằng nhãn: **`[Cấp 1 - Thực thi ngay]`**.
- AI tạo ngay file `Code/hello/README.md` mà **không hỏi xin phép lắt nhắt**, tự kiểm tra file đã tạo thành công và gửi đường dẫn file cho bạn.
- Bạn cũng có thể gõ **`"hướng dẫn tôi"`** bất cứ lúc nào để AI chạy bài giới thiệu tương tác (`sen-onboarding`).

---

## 4. Việc đầu tiên theo từng cấp (3 ví dụ thực tế)

Mọi yêu cầu trong Sen đều được phân vào một trong 3 cấp độ (lấy từ bộ tình huống chuẩn [`tests/tier-scenarios.md`](../tests/tier-scenarios.md)):

### Ví dụ Cấp 1 — Việc nhỏ, rõ ràng, làm ngay
- **Bạn gõ yêu cầu:**
  > `Đổi màu nút "Đăng nhập" sang xanh lá`
- **Bạn sẽ thấy gì:**
  1. AI mở đầu câu trả lời bằng nhãn **`[Cấp 1 - Thực thi ngay]`**.
  2. AI tìm đúng file giao diện chứa nút "Đăng nhập", đổi mã màu sang xanh lá, tự chạy kiểm tra (lint/test/build nếu dự án có) và tóm tắt dòng code đã sửa kèm link tới file.
- **Bạn cần làm gì:**
  - **Không cần làm gì thêm.** Việc nhỏ được làm xong trọn vẹn trong một lượt mà không làm phiền bạn bằng các câu hỏi xác nhận thừa.

### Ví dụ Cấp 2 — Tính năng mới hoặc chạm từ 3 file trở lên
- **Bạn gõ yêu cầu:**
  > `Thêm chức năng lọc sản phẩm theo giá`
- **Bạn sẽ thấy gì:**
  1. AI mở đầu bằng nhãn **`[Cấp 2 - Xác nhận phương án]`**.
  2. AI trình bày ngắn gọn phương án xử lý (ví dụ: thêm ô chọn khoảng giá trên giao diện, lọc danh sách sản phẩm ở tầng xử lý, bổ sung test) kèm **danh sách các file dự kiến sẽ sửa**.
  3. AI dừng lại và hỏi bạn duyệt phương án **đúng một lần**.
- **Bạn cần làm gì:**
  - Xem qua phương án và trả lời **`"Duyệt"`** (hoặc góp ý chỉnh sửa nếu muốn).
  - Ngay sau khi bạn duyệt, AI tự làm một mạch cho đến khi xong, chạy cổng kiểm duyệt chất lượng và gửi **Báo cáo nghiệm thu (`sen-delivery-report`)**.

### Ví dụ Cấp 3 — Dự án mới, kiến trúc, cơ sở dữ liệu, xác thực hoặc thanh toán
- **Bạn gõ yêu cầu:**
  > `Làm một website bán hàng mới cho tiệm bánh`
- **Bạn sẽ thấy gì:**
  1. AI mở đầu bằng nhãn **`[Cấp 3 - Thiết kế & kế hoạch]`**.
  2. **Bước làm rõ & Thiết kế:** AI trao đổi ngắn gọn để làm rõ nhu cầu, sau đó viết bản **Thiết kế (Design Spec)** lưu trong `docs/specs/` kèm sơ đồ trực quan Mermaid và danh sách công cụ cần cài.
  3. **Bước lập kế hoạch:** Sau khi bạn đồng ý thiết kế, AI viết **Kế hoạch triển khai (Implementation Plan)** chia nhỏ thành từng task rõ ràng, và tự chọn chế độ thực thi phù hợp:
     - **Native (AI chính tự làm):** khi ít task (dưới ~5 task) hoặc các task phụ thuộc chặt vào nhau.
     - **Subagent-driven (Đội agent phụ):** khi có nhiều task độc lập hoặc đụng phần nhạy cảm (thanh toán, dữ liệu), kèm ghi chú ước tính chi phí token khoảng **2–3 lần** so với tự làm.
  4. **Bước chuẩn bị môi trường & Thực thi:** AI kiểm tra công cụ trên máy (`sen-environment`), điều phối các vai trò (BA, Trinh sát, Dev, Tester, Kiểm định bảo mật/pháp lý), cập nhật tiến độ vào `docs/CONTEXT.md` và kết thúc bằng báo cáo nghiệm thu.
- **Bạn cần làm gì:**
  - Trả lời câu hỏi làm rõ ban đầu, xem và duyệt **Thiết kế** cùng **Kế hoạch**, sau đó theo dõi đội AI hoàn thành và đọc báo cáo nghiệm thu cuối cùng.

---

## 5. Cách điều khiển AI bằng lời nói tự nhiên

Bạn không cần nhớ lệnh kỹ thuật. Chỉ cần nói tự nhiên trong khung chat:

| Bạn muốn làm gì | Câu cần nói với AI | Hành vi của AI |
|---|---|---|
| **Duyệt phương án Cấp 2 hoặc Kế hoạch Cấp 3** | `"Duyệt"`, `"OK làm đi"`, `"Đồng ý"` | AI bắt đầu thực thi ngay đến khi hoàn tất. |
| **Ép làm nhanh (chuyển về Cấp 1)** | `"làm luôn đi"` (hoặc kèm vào cuối câu: `"Thêm chức năng lọc sản phẩm theo giá, làm luôn đi"`) | AI bỏ qua bước hỏi duyệt phương án của Cấp 2 và thực thi ngay như Cấp 1. |
| **Lưu ý an toàn khi nói `"làm luôn đi"` với việc rủi ro** | Ví dụ: `"Xóa toàn bộ đơn hàng cũ trong cơ sở dữ liệu, làm luôn"` | Với việc xóa dữ liệu, sửa cơ sở dữ liệu, xác thực hoặc thanh toán, AI **không bao giờ bỏ qua thiết kế và kế hoạch**. AI hỏi xác nhận một lần; nếu bạn xác nhận, AI vẫn viết thiết kế + kế hoạch để lưu hồ sơ rồi mới chạy, chỉ bỏ bước chờ duyệt chúng. |
| **Nâng lên làm kỹ theo quy trình Cấp 3** | `"đây là Cấp 3"`, `"làm kỹ giúp tôi"` | AI chuyển yêu cầu hiện tại lên Cấp 3 (có thiết kế, sơ đồ và kế hoạch đầy đủ). |
| **Đổi cách chạy kế hoạch Cấp 3 để tiết kiệm token** | `"tự làm"` (chuyển sang Native) hoặc `"giao agent phụ"` (chuyển sang Subagent-driven) | Đổi ngay giữa chế độ một mình AI chính làm (tiết kiệm hạn mức) và chế độ gọi đội agent phụ chạy song song. |
| **Kiểm tra cập nhật Sen bất cứ lúc nào** | `"kiểm tra cập nhật Sen"` | AI gọi skill `sen-update`, kiểm tra phiên bản mới của `sen-method`, `superpowers`, `security-audit`, `vn-law-check`, tóm tắt thay đổi và chờ bạn bấm đồng ý mới cập nhật. |
| **Kiểm tra dự án trước khi phát hành thật** | `"kiểm tra sẵn sàng phát hành"` | AI chạy song song các bài kiểm tra bảo mật, pháp lý, giấy phép, hiệu năng, SEO, vận hành (`sen-release-readiness`) và tổng hợp thành báo cáo `PASS / WARN / BLOCK`. |
| **Mở Văn phòng 3D theo dõi đội AI & Đầu ra 2 Giai đoạn** | `"mở văn phòng"` (hoặc `"chế độ tiết kiệm"`, `"chế độ chi tiết"`, `"tắt văn phòng"`) | Mở giao diện `sen-office` 3D Chibi (`office/index.html`) hiển thị 9 vai trò AI + Boss trên sofa đỏ, bộ đàm bằng chứng Hook (`0 token`), ngăn kéo 6 ô đếm, thanh tua lại lịch sử và khung đối chiếu Thiết kế vs. Nghiệm thu. |

---

## 6. Cách đọc các tài liệu do AI sinh ra

Khi làm việc ở Cấp 2 và Cấp 3, Sen tạo ra các tài liệu gọn gàng trong thư mục dự án để bạn dễ theo dõi:

1. **Tài liệu thiết kế (`docs/specs/YYYY-MM-DD-<tên>.md`):**
   - Dùng ở Cấp 3. Ghi rõ mục tiêu, kiến trúc, luồng dữ liệu, danh sách công cụ cần có (Bắt buộc / Tùy chọn) và các quyết định quan trọng trước khi viết code.
2. **Kế hoạch triển khai (`docs/plans/`):**
   - Chia công việc lớn thành từng bước nhỏ có ô tích (`- [ ]`), nêu rõ file nào sẽ tạo/sửa và lệnh kiểm tra cho từng bước.
3. **Sơ đồ trực quan (Mermaid):**
   - Nằm ngay trong file thiết kế hoặc báo cáo (sơ đồ luồng nghiệp vụ, luồng hệ thống, trạng thái, dữ liệu, phụ thuộc giữa các task). Antigravity hiển thị trực tiếp thành hình vẽ có mũi tên rất dễ nhìn.
4. **Báo cáo nghiệm thu (`sen-delivery-report`):**
   - Xuất hiện ở cuối mỗi việc Cấp 2 và Cấp 3. Liệt kê những gì đã hoàn thành, link tới các file đã thay đổi, kết quả chạy lệnh kiểm tra thực tế (test/build/security/legal), và các lưu ý nếu có.
5. **Trạng thái dự án (`docs/CONTEXT.md`):**
   - Là "bộ nhớ ngắn gọn" của dự án, được AI cập nhật sau mỗi cột mốc hoặc khi cuộc chat đã dài. Ghi rõ: *đang ở đâu*, *đã chốt quyết định gì*, *việc tiếp theo là gì*. Khi bạn mở một cuộc trò chuyện mới hoàn toàn, AI chỉ cần đọc `docs/CONTEXT.md` là nắm lại toàn bộ mạch công việc mà không tốn token đọc lại lịch sử chat cũ.

---

## 7. Cá nhân hóa `profile.md` và thêm cổng kiểm duyệt cho dự án (`AGENTS.md`)

### 7.1 Xem và sửa hồ sơ cá nhân (`.agents/rules/profile.md`)
File `<workspace>/.agents/rules/profile.md` giúp AI hiểu bạn là ai và muốn làm việc thế nào. Bạn có thể mở file này bằng Antigravity để sửa bất cứ lúc nào (mẫu gốc tại [`templates/profile.template.md`](../templates/profile.template.md)):

- **Name:** Tên hoặc vai trò bạn muốn AI xưng hô (ví dụ: `Anh Minh - Chủ tiệm bánh`).
- **Preferred Language:** Ngôn ngữ trả lời mặc định (ví dụ: `Tiếng Việt`).
- **Primary Tech Stack:** Công nghệ bạn hay dùng hoặc mức độ kỹ thuật (ví dụ: `Người mới, không chuyên lập trình` hoặc `Python FastAPI, React`).
- **Working Style:** Phong cách làm việc mong muốn (ví dụ: `Giải thích ngắn gọn, dễ hiểu, ưu tiên ví dụ thực tế`).

### 7.2 Thêm cổng kiểm duyệt riêng cho một dự án (`<dự-án>/AGENTS.md`)
Mặc định, Sen đã kiểm tra test, build và lỗi bảo mật cơ bản cho mọi việc Cấp 2–3. Nếu một dự án trong `Code/<tên-dự-án>/` cần quy định nghiêm ngặt hơn (như bắt buộc kiểm tra pháp lý Việt Nam, hoặc chạy bộ kiểm tra riêng), hãy:

1. Sao chép file mẫu [`templates/project-AGENTS.template.md`](../templates/project-AGENTS.template.md) vào thư mục gốc của dự án thành `Code/<tên-dự-án>/AGENTS.md`.
2. Điền tên dự án vào `{{PROJECT_NAME}}` và đổi `{{ENABLE_SECURITY_GATE}}` / `{{ENABLE_LEGAL_GATE}}` thành `Yes` (Bắt buộc) hoặc `No`.
3. Trước khi làm việc trong thư mục dự án đó, AI sẽ tự động đọc `AGENTS.md` của dự án và áp dụng tất cả các cổng kiểm duyệt bạn đã bật.

---

## 8. Xử lý lỗi thường gặp, gỡ cài đặt và bảng thuật ngữ

### 8.1 Các tình huống & lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách khắc phục nhanh |
|---|---|---|
| **AI trả lời nhưng không có nhãn `[Cấp 1/2/3]` ở dòng đầu** | Bạn đang mở một thư mục con hoặc thư mục khác, không phải thư mục gốc của Workspace chứa `.agents/plugins/sen-method`. | Vào menu **File → Open Folder** trong Antigravity và chọn đúng thư mục gốc Workspace (nơi có thư mục `.agents/`). |
| **Cài đặt báo lỗi mạng hoặc không tải được gói phụ trợ** | Mạng Internet bị ngắt tạm thời hoặc Git chưa truy cập được GitHub. | Kiểm tra kết nối mạng rồi bảo AI: `"Chạy lại bước cài đặt Sen"`. Script cài đặt rất an toàn: chỉ tải tiếp gói còn thiếu, không làm hỏng phần đã tải. |
| **Bản cập nhật mới hoạt động không như ý** | Một gói vừa cập nhật có thay đổi không tương thích. | Nói với AI: **`"Khôi phục gói <tên-gói> về bản trước"`**. Sen luôn lưu bản sao lưu tự động và sẽ quay về phiên bản cũ qua `Restore-SenPackage`. |
| **Cảnh báo trùng lặp plugin hoặc skill khi cài đặt** | Máy của bạn đã có một bản `superpowers` hoặc `security-audit` ở thư mục cấu hình toàn cục (`~/.gemini/...`). | Chọn giữ lại một bản duy nhất theo câu hỏi của AI để tránh xung đột tên trong Antigravity. |
| **Cuộc trò chuyện quá dài, AI phản hồi chậm hoặc tốn nhiều token** | Ngữ cảnh cuộc chat đã tích tụ quá nhiều lượt trao đổi. | Bảo AI `"Cập nhật CONTEXT.md"`, sau đó gõ lệnh `/compact` hoặc mở một cuộc chat mới. |

### 8.2 Cách gỡ cài đặt Sen
Sen được thiết kế tôn trọng tuyệt đối dữ liệu của bạn:
- Toàn bộ dự án trong `Code/`, tài liệu trong `docs/` và các rule cá nhân của bạn (`profile.md`, `safety.md`) nằm độc lập với plugin.
- Để **tạm tắt** Sen: mở quản lý Plugin trong Antigravity hoặc đổi trường `"disabled": true` trong `.agents/plugins/sen-method/plugin.json`.
- Để **gỡ hẳn** Sen khỏi Workspace: đóng Antigravity, xóa thư mục `<workspace>/.agents/plugins/sen-method` (và file `.agents/sen.lock.json` nếu muốn). Toàn bộ code và tài liệu dự án của bạn vẫn còn nguyên vẹn 100%.

### 8.3 Bảng thuật ngữ siêu gọn

| Thuật ngữ | Nghĩa dễ hiểu |
|---|---|
| **Workspace** | Thư mục làm việc gốc trên máy tính chứa `.agents/`, `Code/`, `Templates/` và `docs/`. |
| **Tier (Cấp 1 / 2 / 3)** | Mức độ lớn/nhỏ và độ rủi ro của công việc để AI chọn quy trình phù hợp. |
| **Token** | Đơn vị đo độ dài văn bản mà AI đọc và viết; tiết kiệm token giúp AI chạy nhanh hơn và đỡ tốn hạn mức tài khoản. |
| **Subagent (Agent phụ)** | Các trợ lý AI chuyên biệt (Trinh sát, Dev, Tester, Kiểm định) được AI chính gọi ra hỗ trợ ở Cấp 3. |
| **Trinh sát (Scout)** | Agent phụ chỉ đọc và tìm kiếm thông tin bằng model nhẹ (`flash_lite` / `flash`) để tiết kiệm token cho AI chính. |
| **Quality Gate (Cổng kiểm duyệt)** | Bước kiểm tra bắt buộc (chạy test, build, rà soát bảo mật, pháp lý) trước khi bàn giao sản phẩm. |
| **Lockfile (`sen.lock.json`)** | File ghi nhớ chính xác phiên bản của Sen và các gói kỹ năng đang cài trong Workspace. |

---

## 9. Cần hỗ trợ? Liên hệ & Ủng hộ tác giả

Nếu bạn gặp khó khăn trong quá trình cài đặt, sử dụng hoặc muốn đóng góp ý kiến để Sen ngày càng hoàn thiện hơn, vui lòng liên hệ trực tiếp với tác giả:

```text
Mr Bòn Bon - tunbh.study@gmail.com
(+84) 793.166.866 - (+84) 96.158.1163
Donate: TPBank - 61.222.666.888
```
