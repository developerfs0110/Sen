# Sen: Thiết kế phần lõi

- **Ngày:** 2026-11-06
- **Trạng thái:** Bản nháp, chờ chủ dự án duyệt
- **Phạm vi:** Phần lõi của phương pháp luận Sen. Văn phòng giám sát 3D nằm ở tài liệu thứ hai, viết sau (xem mục 11).
- **Ký hiệu:** Những chỗ ghi *(AI đề xuất)* là quyết định do AI đưa ra trong lúc viết, chưa được chủ dự án xác nhận riêng. Chủ dự án có thể sửa bất kỳ chỗ nào.

---

## 1. Sen là gì và vì sao làm

**Sen** là một phương pháp luận làm việc với đội AI agent trong Antigravity, được đóng gói thành plugin để chia sẻ cho nhiều người.

Khẩu hiệu: *"Sen: làm việc với đội AI một cách gọn, rõ, nhẹ."* / *"Calm, clear AI work."*

**Vấn đề Sen giải quyết:**
- AI hoặc hỏi quá nhiều với việc nhỏ, hoặc tự làm quá đà với việc lớn.
- Người dùng không biết AI đang làm gì, làm đến đâu.
- Token bị tiêu vào những chỗ không cần (đọc cả file lớn, gọi cả đội cho việc nhỏ, chat dài lan man).
- Mỗi dự án làm một kiểu, không có quy trình chung từ lúc nhận việc đến lúc bàn giao.

**Năm nguyên lý** (hiển thị ở đầu README):
1. **Đúng mức kiểm soát:** Việc nhỏ tự chạy, việc vừa xin duyệt một lần, việc lớn có thiết kế và kế hoạch.
2. **Minh bạch:** Mọi việc đều thấy được qua nhãn cấp độ, sơ đồ, báo cáo, và (ở tài liệu 2) văn phòng giám sát.
3. **Có bằng chứng mới báo xong:** Không có kết quả test hay kiểm tra thật thì không được nói "xong".
4. **Gọn nhẹ mặc định:** Đúng model, đúng lượng token, chỉ gọi cả đội khi thật sự cần.
5. **Tích lũy:** Việc gì lặp lại thì đóng gói thành skill, để lần sau nhanh hơn.

## 2. Người dùng

- **Ban đầu:** Người Việt, bao gồm cả người **chưa từng dùng** skill hay phương pháp luận nào.
- **Đồng thời:** Người nói tiếng Anh phải dùng được ngay khi vừa tiếp cận, không cần chờ bản dịch.
- **Người đầu tiên dùng thật:** chủ dự án, trên workspace `d:\TUNBH\Workspace`.

## 3. Mục tiêu, không làm, phản mục tiêu

**Mục tiêu**
- Mọi yêu cầu trong workspace có cài Sen đều **tự động** được phân cấp và xử lý theo quy trình, không cần gõ lệnh kích hoạt.
- Người chưa có kinh nghiệm cài được Sen bằng cách dán một câu vào Antigravity, rồi làm xong việc đầu tiên theo hướng dẫn.
- Người dùng tiếng Việt và tiếng Anh đều có trải nghiệm trọn vẹn bằng ngôn ngữ của mình.
- Superpowers và security-audit được tự tải về, phiên bản được ghi lại, cập nhật theo cơ chế báo rồi bấm duyệt.

**Không làm (ở phiên bản này)**
- Không hỗ trợ công cụ khác ngoài Antigravity (Claude Code, Cursor, Codex...). Để mở rộng sau.
- Không chép skill của superpowers hay security-audit vào repo Sen.
- Không chứa skill theo công nghệ cụ thể (FastAPI, Vite...).
- Văn phòng giám sát 3D không nằm trong tài liệu này.

**Phản mục tiêu (xảy ra những điều này là thất bại, kể cả khi mọi thứ chạy được)**
- Việc Cấp 1 bị bắt qua nhiều bước xin phép.
- Rule luôn bật phình to đến mức AI làm theo kém đi hoặc tốn token đáng kể ở mọi lượt chat.
- Một bản cập nhật từ repo bên thứ ba tự vào máy người dùng mà họ không biết.
- Người mới cài xong mà không biết bước tiếp theo là gì.
- Thông tin cá nhân của chủ dự án (đường dẫn máy, profile) lọt vào plugin chia sẻ, ngoại trừ phần tác giả được chủ dự án chủ động đưa vào.

## 4. Ràng buộc

- **Nền tảng:** Antigravity IDE. Sen là một plugin Antigravity: `plugin.json`, `rules/AGENTS.md` (luôn bật khi plugin bật), `skills/<tên>/SKILL.md`, `hooks.json` nếu cần.
- **Ngân sách rule:** Antigravity dành khoảng 20.000 token cho mọi rule luôn bật cộng lại, tối đa 24 KB mỗi file; vượt quá thì rule bị hạ xuống thành đường dẫn. Rule lõi của Sen phải nhỏ (mục tiêu: dưới khoảng 1.500 token, dưới 100 dòng).
- **Trường của `plugin.json`:** chỉ nhận `name`, `description`, `logo`, `suggestedPrompts`, `displayName`, `version`, `author` (tên + url `https://`), `homepage`, `repository`, `disabled`. Trường lạ bị bỏ qua âm thầm.
- **Trùng tên:** Tên plugin và tên skill dùng chung một không gian tên toàn cục; trùng thì một bên bị bỏ âm thầm. Mọi skill của Sen phải có tiền tố `sen-`.
- **Hệ điều hành:** Windows là chính (chủ dự án dùng Windows). macOS/Linux phải cài được nhưng có thể ít được thử hơn.
- **An toàn:** Cài đặt và cập nhật không bao giờ được chạy lệnh xóa hàng loạt hoặc ghi đè thư mục người dùng mà không hỏi.

## 5. Các phương án đã cân nhắc

| Quyết định | Các phương án | Đã chọn | Lý do |
|---|---|---|---|
| Đặt quy trình ở đâu | A. Rule mô-đun luôn bật + gọi skill khi cần · B. Gộp hết vào một `AGENTS.md` · C. Chỉ là một skill | **A** | Luôn tự áp dụng nhưng nhẹ token; phần nặng chỉ nạp khi cần. C không tự áp dụng nếu người dùng quên gọi. |
| Đóng gói | Một skill · Phương pháp luận dạng plugin | **Plugin** | Cần một rule luôn bật làm xương sống cộng nhiều skill; plugin cài và bật tắt được như một khối. |
| Ngôn ngữ | A. File cho AI bằng tiếng Anh, AI trả lời theo ngôn ngữ người dùng · B. Hai bản đầy đủ · C. Lõi tiếng Việt, dịch sau | **A** | Một bản quy trình, model làm theo tiếng Anh ổn định nhất, ít token hơn; người dùng vẫn nhận mọi thứ bằng ngôn ngữ của mình. B dễ lệch hai bản; C không đáp ứng người nước ngoài. |
| Skill bên thứ ba | Chép vào Sen và theo dõi nguồn gốc · Tự tải từ repo gốc khi cài | **Tự tải** | Không trùng tên, không cần ai duyệt định kỳ, skill luôn nguyên bản. Hai repo bắt buộc rất nhẹ (đo trên máy chủ dự án: superpowers ~1,5 MB, security-audit ~0,3 MB). |
| Cập nhật | Tự động hoàn toàn · Báo rồi bấm duyệt | **Báo rồi bấm duyệt** | Tránh việc bản cập nhật xấu từ repo bên thứ ba vào thẳng máy người dùng; skill có quyền chỉ đạo AI chạy lệnh. |

## 6. Cấu trúc repo `sen-method`

```text
sen-method/
├── plugin.json
├── README.md                  # tiếng Anh, bản mặc định trên GitHub
├── README.vi.md               # tiếng Việt
├── INSTALL.md                 # hướng dẫn cho AI agent thực hiện cài đặt (xem 8.1)
├── LICENSE
├── CHANGELOG.md
├── sen.lock.template.json     # mẫu file khóa phiên bản
├── rules/
│   └── AGENTS.md              # rule lõi, luôn bật (tiếng Anh)
├── skills/
│   ├── sen-onboarding/        # hướng dẫn tương tác cho người mới
│   ├── sen-setup/             # cài đặt và tạo cấu trúc workspace
│   ├── sen-update/            # kiểm tra và áp dụng cập nhật
│   ├── sen-delivery-report/   # báo cáo nghiệm thu khi bàn giao
│   ├── sen-release-readiness/ # kiểm tra trước khi phát hành
│   ├── sen-environment/       # kiểm tra và cài công cụ cho công nghệ đã chọn
│   └── sen-skill-capture/     # đề xuất và đóng gói việc lặp lại thành skill
├── templates/
│   ├── workspace/             # khung thư mục lõi tạo cho người dùng
│   ├── profile.template.md
│   ├── safety.template.md
│   ├── project-AGENTS.template.md   # cổng kiểm duyệt riêng của một dự án
│   └── CONTEXT.template.md
├── scripts/
│   ├── install.ps1 / install.sh
│   └── check-updates.ps1 / check-updates.sh
├── docs/
│   ├── guide.md               # hướng dẫn đầy đủ, tiếng Anh
│   ├── huong-dan.md           # hướng dẫn đầy đủ, tiếng Việt
│   └── specs/
└── tests/
    └── tier-scenarios.md      # bộ tình huống kiểm tra phân cấp
```

Danh sách skill và tên của chúng là *(AI đề xuất)*.

## 7. Rule lõi (`rules/AGENTS.md`)

Viết bằng tiếng Anh, ngắn gọn. Nội dung bắt buộc:

### 7.1 Ngôn ngữ trả lời
- Trả lời bằng ngôn ngữ người dùng đang viết. Nếu `profile.md` có ghi ngôn ngữ cố định thì theo profile.
- Nhãn cấp độ dịch theo ngôn ngữ: `[Cấp 1 - Thực thi ngay]` / `[Tier 1 - Doing it now]`, tương tự cho Cấp 2, Cấp 3.

### 7.2 Phân cấp mọi yêu cầu
Câu trả lời đầu tiên cho một yêu cầu công việc luôn bắt đầu bằng nhãn cấp độ.

| Cấp | Tiêu chí | Hành vi |
|---|---|---|
| **1 - Thực thi ngay** | Sửa giao diện/CSS, đổi nội dung, sửa lỗi đã rõ nguyên nhân, refactor nhỏ trong 1–2 file, không đổi luồng dữ liệu | Làm luôn, tự kiểm tra (lint/test/build nếu có), báo kết quả. Không hỏi lại. |
| **2 - Xác nhận phương án** | Thêm tính năng mới; sửa logic chạm từ 3 file trở lên; cài thư viện mới; đổi API nội bộ | Tóm tắt phương án và danh sách file sẽ sửa, chờ người dùng duyệt **một lần**, sau đó làm đến hết. |
| **3 - Thiết kế & kế hoạch** | Dự án mới; đổi kiến trúc; đụng cơ sở dữ liệu, xác thực, thanh toán; có nguy cơ mất dữ liệu | Thảo luận làm rõ (`brainstorming`), viết thiết kế, viết kế hoạch (`writing-plans`), chờ duyệt, rồi mới thực thi. |

- **Ngoại lệ:** Câu hỏi tra cứu thông tin thuần túy thì trả lời thẳng, không gắn nhãn.
- **Người dùng ghi đè:** "làm luôn đi" / "just do it" thì chuyển về Cấp 1; "đây là Cấp 3" thì nâng cấp. Ghi đè có hiệu lực cho yêu cầu hiện tại.
- **Khi nghi ngờ giữa hai cấp:** chọn cấp cao hơn và nói một dòng lý do *(AI đề xuất)*.
- **Việc rủi ro không bao giờ bỏ qua thiết kế và kế hoạch** (xóa dữ liệu, cơ sở dữ liệu, xác thực, thanh toán), kể cả khi người dùng bảo "làm luôn". Trong trường hợp đó, AI hỏi xác nhận một lần. Nếu người dùng xác nhận, AI vẫn viết thiết kế và kế hoạch để có tài liệu xem lại khi có sự cố, chỉ bỏ bước chờ duyệt chúng *(chủ dự án chốt)*.

### 7.2b Thứ tự ưu tiên so với superpowers *(AI đề xuất)*
- Một số skill của superpowers có mô tả kiểu "phải dùng trước mọi việc sáng tạo" (`brainstorming`) hoặc "dùng ở đầu mọi cuộc chat" (`using-superpowers`). Điều này mâu thuẫn với Cấp 1 "làm ngay".
- Kiểm tra trên bản superpowers đang cài: plugin **không có `rules/`** và **không có `hooks.json` ở thư mục gốc**. Hook `session-start` của nó nằm trong `hooks/` theo định dạng Claude Code, nên nhiều khả năng Antigravity không chạy. Nghĩa là superpowers không có phần luôn bật trong Antigravity; các skill của nó chỉ được nạp khi được gọi.
- Rule của Sen ghi rõ: **phân cấp của Sen quyết định skill nào được gọi.** `brainstorming` và `writing-plans` chỉ dùng ở Cấp 3. `using-superpowers` không dùng, vì rule của Sen thay vai trò của nó. Các skill khác (`systematic-debugging`, `test-driven-development`, `verification-before-completion`...) được dùng ở bất kỳ cấp nào khi phù hợp, miễn không thêm bước xin phép ở Cấp 1.
- Sen không sửa file nào của superpowers.

### 7.3 Vai trò
Cấp 1 và 2: AI chính tự làm hết. Cấp 3: AI chính đóng vai PM/Tech Lead điều phối các vai trò sau qua agent phụ:

| Vai trò | Việc | Model cho agent phụ |
|---|---|---|
| PM / Tech Lead | AI chính: phân cấp, điều phối, báo cáo cho người dùng | (model người dùng đang chọn) |
| BA / Kiến trúc sư | Viết thiết kế và kế hoạch | AI chính tự làm, hoặc `inherit` |
| Trinh sát | Chỉ đọc: tìm trong code, tài liệu, web; trả về bản tóm tắt ngắn | `flash_lite` hoặc `flash` |
| Dev | Viết code + test theo từng task của kế hoạch | `inherit` hoặc `pro` |
| Tester | Kiểm thử từ góc nhìn người dùng: chạy các kịch bản đầu đến cuối (đăng ký, mua hàng...), khác với test đơn vị do Dev viết | `inherit` |
| Kiểm định (Bảo mật, Pháp lý, các cổng khác) | Soát độc lập kết quả của Dev | `inherit` hoặc `pro` |

- **Đa luồng:** Chỉ chạy song song những task độc lập, không sửa chung file (theo `dispatching-parallel-agents`). Cấp 1–2 luôn một luồng.
- Trinh sát được ưu tiên cho mọi việc tìm kiếm trên nhiều file, kể cả ở Cấp 2.

### 7.3b Tự chọn cách thực thi kế hoạch Cấp 3 *(chủ dự án chốt)*
- Viết xong kế hoạch, AI **không hỏi** người dùng chọn Native hay Subagent-driven (khác hành vi mặc định của `writing-plans`). AI tự chọn và thông báo một dòng:
  - Ít task (dưới khoảng 5) hoặc các task phụ thuộc chặt vào nhau → **Native** (AI chính tự làm, một lượt soát cuối).
  - Nhiều task độc lập, hoặc việc rủi ro (dữ liệu, thanh toán, xác thực) → **Subagent-driven** (mỗi task một agent phụ, có người soát).
- Dòng thông báo kèm **ước lượng tương đối**, không đưa số tuyệt đối: Subagent-driven tốn khoảng 2–3 lần Native. Ví dụ: *"Kế hoạch có 8 task độc lập và đụng đến thanh toán, nên tôi giao cho các agent phụ (ước tính tốn khoảng 2–3 lần so với tự làm). Nếu tài khoản của bạn sắp hết hạn mức, nói 'tự làm' để tiết kiệm hơn."*
- Người dùng nói "tự làm" / "do it yourself" thì chuyển sang Native; "giao agent phụ" / "use subagents" thì chuyển sang Subagent-driven.
- Sen không đọc được hạn mức token còn lại của tài khoản (Antigravity không có cách chính thức nào cho việc này). Người dùng tự xem trong trang tài khoản.

### 7.4 Tiết kiệm token
- Tìm bằng từ khóa trước, chỉ đọc đúng đoạn cần, không đọc cả file lớn khi không cần.
- Việc đọc nhiều file thì giao cho Trinh sát dùng model nhẹ.
- Không in lại nguyên đoạn code đã sửa vào chat; tóm tắt thay đổi và gắn link tới dòng code.
- Chỉ gọi nhiều vai trò ở Cấp 3.

### 7.5 Sơ đồ và tài liệu trực quan
- **Cấp 3:** tự động có các sơ đồ phù hợp với việc (luồng nghiệp vụ, luồng hệ thống, trạng thái, dữ liệu, mockup giao diện, sơ đồ phụ thuộc giữa các task). Việc không đụng dữ liệu thì không vẽ sơ đồ dữ liệu, v.v.
- **Cấp 2:** chỉ vẽ khi người dùng yêu cầu.
- **Cấp 1:** không vẽ.
- Sơ đồ dùng Mermaid trong file markdown; mockup giao diện dùng visual companion của `brainstorming`.

### 7.6 Cổng kiểm duyệt
- **Cổng mặc định**, áp dụng khi nghiệm thu Cấp 2 và 3: test và build đạt, không lộ mật khẩu hay API key, không có lỗi bảo mật cơ bản. Dùng `verification-before-completion`.
- **Cổng theo dự án:** Dự án nào cần thêm (Pháp lý, Bảo mật sâu, tiêu chuẩn riêng) thì đặt `AGENTS.md` trong thư mục dự án, theo mẫu `templates/project-AGENTS.template.md`. Kiểm tra thực tế (xem `notes/2026-11-06-plugin-rule-probe.md`) cho thấy Antigravity **không chắc** tự nạp file này, nên rule lõi ghi rõ: trước khi làm việc trong một thư mục dự án, AI tự đọc `AGENTS.md` ở gốc dự án (và các thư mục cha lên tới workspace) nếu có, rồi áp dụng.
- Cổng Bảo mật gọi skill `security-audit`. Cổng Pháp lý gọi `vn-law-check` nếu đã cài; nếu chưa cài thì nói rõ là chưa kiểm được và gợi ý cài.

### 7.7 Chốt trạng thái
- Khi xong một mốc ở Cấp 2/3, hoặc khi cuộc chat đã dài, cập nhật `docs/CONTEXT.md` của dự án: đang ở đâu, đã chốt gì, việc tiếp theo.
- Khi cuộc chat dài, gợi ý người dùng dùng `/compact` hoặc mở chat mới; chat mới chỉ cần đọc `CONTEXT.md`.

### 7.8 Đóng gói việc lặp lại
- Khi một quy trình lặp lại lần thứ 2–3, hoặc ngay sau khi người dùng sửa một lỗi quy trình quan trọng, đề xuất một dòng ở cuối câu trả lời: có muốn đóng gói thành skill không. Chỉ tạo khi người dùng đồng ý (dùng `sen-skill-capture`, bên trong gọi `writing-skills`).

### 7.9b Chuẩn bị môi trường (`sen-environment`) *(chủ dự án chốt)*
Chạy ngay sau khi chốt công nghệ, trước khi viết code, áp dụng cho mọi công nghệ (Node, Python, Flutter, Android SDK...).

1. **Liệt kê công cụ cần có.** Ở Cấp 3, danh sách nằm trong tài liệu thiết kế, mục "Công cụ cần có". Mỗi công cụ được đánh dấu **Bắt buộc** hoặc **Tùy chọn**.
2. **Kiểm tra kỹ máy hiện tại trước khi kết luận thiếu.** Không chỉ chạy `<tool> --version`, mà còn kiểm tra các vị trí cài phổ biến và các trình quản lý phiên bản (ví dụ nvm, fnm, pyenv). Chia kết quả thành ba nhóm: *đã có và đủ phiên bản* / *đã có nhưng cần nâng cấp* / *chưa có*. Chỉ đưa vào danh sách cài những thứ thật sự thiếu hoặc cần nâng cấp.
3. **Hỏi một lần cho cả danh sách**, dạng ô tick:
   - Mỗi dòng ghi: tên công cụ, phiên bản sẽ cài, dung lượng ước tính, nhãn Bắt buộc/Tùy chọn.
   - Mặc định tất cả đều được tick sẵn. Người dùng bỏ tick hoặc tick lại tùy ý.
   - Ngay trên danh sách có lời nhắc: *"Các mục có nhãn Bắt buộc đều cần cài thì dự án mới chạy được."*
   - Nếu người dùng bỏ tick một mục Bắt buộc, AI nói một dòng hậu quả (ví dụ: "Không có Node.js thì không chạy được dự án này"), rồi làm theo lựa chọn của người dùng, không hỏi lại.
   - Hộp chọn có sẵn của Antigravity (`ask_question`) hỗ trợ chọn nhiều mục, nhưng có thể không hỗ trợ tick sẵn. Nếu vậy, người thực thi tìm cách thay thế giữ được ý "mặc định là tất cả", ví dụ đặt lựa chọn đầu tiên là "(Khuyên dùng) Cài tất cả", hoặc hiện danh sách tick trong visual companion.
4. **Cài bằng nguồn chính thức** (`winget`, `brew`, trang chủ của công cụ). Không tải file cài đặt từ nguồn lạ.
5. **Kiểm tra lại sau khi cài** (ví dụ `node -v`). Nếu cần mở lại terminal hoặc IDE để máy nhận công cụ mới thì nói rõ.

- Cài phần mềm là thao tác ngoài workspace, nên đây là **ngoại lệ được phép của quy tắc an toàn, nhưng luôn phải hỏi trước**, kể cả khi việc đang làm là Cấp 1. Mẫu `safety.template.md` phải ghi ngoại lệ này.

### 7.10 Bàn giao
- Không báo "xong" khi chưa chạy lệnh kiểm tra thật.
- Cấp 2/3 kết thúc bằng báo cáo nghiệm thu (`sen-delivery-report`).
- Chỉ commit khi người dùng yêu cầu; commit theo quy ước của workspace nếu có.

## 8. Cài đặt

### 8.1 Cách người dùng bắt đầu
1. Người dùng tự cài **Antigravity IDE** (Sen không cài thay được bước này). Hướng dẫn có link tải và ảnh minh họa.
2. Mở Antigravity, dán một câu: *"Cài Sen cho tôi từ https://github.com/<owner>/sen-method"* (bản tiếng Anh: *"Install Sen from …"*).
3. Lúc này Sen chưa có trên máy, nên AI sẽ đọc `INSTALL.md` trong repo. File này là chỉ dẫn viết cho AI: tải repo, rồi làm theo skill `sen-setup`.

### 8.2 Các bước `sen-setup`

| Bước | Việc | Người dùng làm gì |
|---|---|---|
| 1 | Kiểm tra Git. Thiếu thì đề xuất cài bằng `winget` (Windows) hoặc `brew` (macOS). Node.js chỉ cần cho văn phòng giám sát (tài liệu 2), nên ở đây chỉ báo, không bắt buộc *(AI đề xuất)* | Bấm đồng ý |
| 2 | Liệt kê các ổ đĩa kèm dung lượng trống, đề xuất ổ trống nhiều nhất làm nơi đặt workspace | Chọn ổ hoặc chấp nhận |
| 3 | Tạo workspace từ `templates/workspace/`: `.agents/rules/`, `.agents/plugins/`, `.agents/skills/`, `Code/`, `Templates/`, `docs/`. Nếu thư mục đã có thì không ghi đè, chỉ bổ sung phần thiếu | Không cần làm gì |
| 4 | Đặt Sen vào `.agents/plugins/sen-method/`. Tải bản mới nhất (không kèm lịch sử) của `superpowers` vào `.agents/plugins/superpowers/` và `security-audit` vào `.agents/skills/security-audit/` | Không cần làm gì |
| 5 | Hỏi có muốn cài `vn-law-check` không | Chọn có/không |
| 6 | Hỏi vài câu để tạo `.agents/rules/profile.md`: tên gọi, ngôn ngữ, công nghệ hay dùng, phong cách làm việc. Tạo `.agents/rules/safety.md` từ mẫu, với đường dẫn workspace thật | Trả lời |
| 7 | Ghi `sen.lock.json`: phiên bản (commit) của Sen, superpowers, security-audit, vn-law-check (nếu có) | Không cần làm gì |
| 8 | Phát hiện trùng: nếu máy đã có một bản superpowers hoặc security-audit ở chỗ khác mà Antigravity cũng đọc được, hỏi người dùng giữ bản nào | Chọn |
| 9 | Chạy thử một việc Cấp 1 nhỏ để xác nhận rule đã có hiệu lực | Xem kết quả |

- Cài **theo workspace** (trong `.agents/` của workspace đã chọn), không cài toàn máy *(AI đề xuất: khớp với cấu trúc workspace lõi; người dùng muốn dùng ở thư mục khác thì cài lại ở đó hoặc mở rộng sau)*.
- **Chuyển sang workspace mới** *(AI đề xuất)*: Nếu người dùng chọn một ổ hoặc thư mục khác với thư mục đang mở trong Antigravity, cửa sổ hiện tại sẽ không nạp Sen. Vì vậy sau bước 8, `sen-setup` dừng lại và hướng dẫn cụ thể: *"Mở thư mục `E:\Sen-Workspace` bằng File → Open Folder, rồi gõ 'hướng dẫn tôi'"*. Bước 9 (chạy thử Cấp 1) do `sen-onboarding` làm trong cửa sổ mới. Nếu người dùng giữ thư mục hiện tại thì làm bước 9 ngay.
- **Nguồn tải:**
  - superpowers: repo gốc của Jesse Vincent (lấy URL chính xác từ `.git` của bản đang cài hoặc từ README của superpowers).
  - security-audit: `github.com/cloudflare/security-audit-skill`, thư mục `skills/security-audit/` (theo `skills-lock.json` trên máy chủ dự án). Skill nằm trong thư mục con, nên phải tải repo rồi chỉ lấy thư mục đó.
  - vn-law-check: `github.com/mhfed/vn-law-check`. Người thực thi xác định thư mục chứa skill.
- **Kiểm tra đầu tiên khi thực thi:** xác nhận Antigravity nạp `rules/AGENTS.md` của một plugin đặt tại `<workspace>/.agents/plugins/<tên>/`, và rule đó cộng dồn với `AGENTS.md` trong thư mục dự án. Phần `skills/` thì đã chạy được: các skill của superpowers tại `.agents/plugins/superpowers/` đang được nạp trên máy chủ dự án. Nếu phần rule không chạy, cách dự phòng là `sen-setup` chép rule lõi thành `.agents/rules/sen.md`, còn `sen-update` cập nhật cả bản chép này.
- Script `install.ps1` / `install.sh` làm các bước không cần hỏi (tạo thư mục, tải, ghi lock); AI lo phần hỏi đáp và xử lý lỗi.

### 8.3 Workspace của chủ dự án hiện tại
Workspace `d:\TUNBH\Workspace` đã có superpowers, security-audit, `safety.md`, `commit-convention.md`. Khi cài Sen vào đây, `sen-setup` phải giữ nguyên các file hiện có, chỉ thêm phần thiếu, và tạo `sen.lock.json` từ các bản đang có.

## 9. Cập nhật (`sen-update`)

- **Tần suất:** kiểm tra tối đa một lần mỗi tuần.
- **Cách báo:** liệt kê các gói có bản mới kèm tóm tắt thay đổi, ví dụ: *"superpowers có bản mới. Thay đổi: … Cập nhật không?"*. Người dùng đồng ý thì mới cập nhật.
- **Quay lại:** `sen.lock.json` giữ phiên bản trước; cập nhật lỗi thì quay về được.
- Người dùng cũng có thể nói "kiểm tra cập nhật Sen" bất cứ lúc nào.
- **Cơ chế kích hoạt hằng tuần: để người thực thi chọn** (xem mục 12). Yêu cầu: không tốn token ở những lượt chat không đến hạn kiểm tra.

## 10. Tài liệu cho người dùng

### 10.1 README (`README.md` tiếng Anh, `README.vi.md` tiếng Việt, dòng đầu liên kết qua lại)
Thứ tự:
1. Tên + khẩu hiệu.
2. Sen là gì (3 câu).
3. Vấn đề Sen giải quyết.
4. Năm nguyên lý (mục 1).
5. Sen hoạt động thế nào: sơ đồ Yêu cầu → phân cấp → đội AI → cổng kiểm duyệt → bàn giao, kèm bảng ba cấp. Chừa chỗ cho ảnh hoặc GIF văn phòng giám sát (thêm sau tài liệu 2).
6. Bắt đầu nhanh: 3 bước (cài Antigravity, dán câu cài đặt, làm theo hướng dẫn), link sang hướng dẫn đầy đủ.
7. Sen dùng những gì: superpowers, security-audit, vn-law-check (tùy chọn); ghi rõ tác giả và giấy phép của từng gói.
8. **Tác giả & Ủng hộ / Author & Support** (cuối trang):
   - Mr Bòn Bon - tunbh.study@gmail.com
   - (+84) 793.166.866 - (+84) 96.158.1163
   - Donate: TPBank - 61.222.666.888

### 10.2 Hướng dẫn đầy đủ (`docs/huong-dan.md`, `docs/guide.md`)
Viết cho người chưa biết gì:
1. Khái niệm: AI agent, Antigravity, skill, rule, plugin. Mỗi khái niệm một câu đời thường và một ví dụ.
2. Cài đặt từng bước, có cách tải file zip cho người không dùng git.
3. Kiểm tra cài đặt: một câu thử, kết quả mong đợi.
4. Việc đầu tiên theo từng cấp: ba ví dụ, ở mỗi bước người dùng sẽ thấy gì và cần làm gì.
5. Cách điều khiển AI: duyệt, "làm luôn đi", chỉnh cấp, kiểm tra cập nhật.
6. Đọc tài liệu AI sinh ra: thiết kế, kế hoạch, sơ đồ, báo cáo nghiệm thu, `CONTEXT.md`.
7. Điền và sửa `profile.md`; thêm cổng kiểm duyệt cho một dự án.
8. Lỗi thường gặp, gỡ cài đặt, bảng thuật ngữ.
9. Cuối trang: "Cần hỗ trợ? Liên hệ…" với thông tin tác giả.

### 10.3 Hướng dẫn tương tác (`sen-onboarding`)
Người dùng gõ "hướng dẫn tôi" / "onboard me". AI dẫn từng bước trong chat: kiểm tra cài đặt đã đủ chưa, giúp điền `profile.md`, cho làm thử một việc Cấp 1, giới thiệu ba cấp bằng ví dụ thật trong workspace của họ.

### 10.4 Thông tin tác giả ở các chỗ khác
- `plugin.json`: `author.name` = "Mr Bòn Bon" (file này không nhận email hay số điện thoại).
- `LICENSE`: tên tác giả trong dòng bản quyền.
- Cuối hai file hướng dẫn: dòng liên hệ.

## 11. Liên hệ với văn phòng giám sát (tài liệu 2)

Văn phòng giám sát là plugin phụ riêng (`sen-office`), thiết kế sau. Những gì đã chốt, để tài liệu 2 kế thừa:
- Tab trình duyệt riêng, phòng 3D, hình người màu theo vai trò ở mục 7.3, dây nối cong mở ra khi trao đổi, nhấp nháy đến khi xong.
- Hai lớp dữ liệu chồng nhau: hook ghi thao tác (luôn chạy, gần như 0 token) và AI tự ghi lời giải thích (thêm).
- Công tắc `Tắt / Tiết kiệm / Chi tiết` trên màn hình, bấm không tốn token; chọn Chi tiết thì hiện cảnh báo tốn thêm token; mặc định mỗi việc mới là Tiết kiệm.

Phần lõi không phụ thuộc vào văn phòng. Rule lõi không được nhắc đến văn phòng ngoài một dòng: "nếu `sen-office` được cài, làm theo rule của nó".

## 12. Để lại cho người thực thi

- Câu chữ chính xác của rule và các skill, miễn giữ đúng hành vi đã mô tả và nằm trong ngân sách token.
- Cơ chế kích hoạt kiểm tra cập nhật hằng tuần. Ưu tiên cách không tốn token (hook, hoặc script chạy theo lịch của hệ điều hành ghi ra một file cờ mà rule chỉ đọc khi tồn tại). Nếu phải dùng rule thì chi phí ở mỗi lượt chat phải gần bằng 0.
- Định dạng chi tiết của `sen.lock.json`.
- Cách hiện thực bộ kiểm tra phân cấp `tests/tier-scenarios.md`. Tối thiểu: mỗi cấp 5–10 yêu cầu mẫu kèm cấp đúng, cộng các trường hợp ngoại lệ (câu hỏi tra cứu, ghi đè, việc có nguy cơ mất dữ liệu).
- Nội dung danh sách kiểm tra cơ bản trong `sen-release-readiness` cho những nhóm chưa có skill (chính sách kho ứng dụng, giấy phép thư viện, khả năng tiếp cận, hiệu năng, SEO, vận hành). Skill phải chạy các nhóm song song và gộp thành một báo cáo: đạt, cảnh báo, chặn phát hành.
- Thiết kế logo (có thể dùng công cụ tạo ảnh).

## 13. Còn phải xác nhận

- **Giấy phép của Sen:** chưa chọn (ví dụ MIT, giống superpowers).
- **Giấy phép của `security-audit` và `vn-law-check`:** chưa kiểm tra. Vì Sen chỉ tải về từ repo gốc chứ không chép vào, điều này chủ yếu ảnh hưởng đến cách ghi công trong README.
- **Chủ sở hữu repo GitHub** (tài khoản hoặc tổ chức nào) để điền vào câu cài đặt và `plugin.json`.

