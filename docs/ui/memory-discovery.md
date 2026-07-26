# UI-MEMORY-DISCOVERY

## 1. Mục tiêu UI

UI phải giúp người dùng cảm thấy:

- Nizi đang hỗ trợ, không kiểm soát thư viện;
- dữ liệu được xử lý riêng tư;
- quá trình scan không đáng sợ;
- đề xuất dễ hiểu;
- người dùng luôn là người quyết định.

Ngôn ngữ sản phẩm không dùng các từ:

- cào dữ liệu;
- thu thập toàn bộ;
- upload thư viện;
- AI quét mọi thứ.

Nên dùng:

- Khám phá thư viện;
- Tìm lại kỷ niệm;
- Khám phá ký ức;
- Đề xuất Album;
- Phân tích trên thiết bị.

---

## 2. Information Architecture

```text
Nizi iOS
├── Home
├── Albums
├── Memory Discovery
│   ├── Onboarding
│   ├── Permission
│   ├── Scan Progress
│   ├── Discovery Home
│   ├── Years
│   ├── Candidate Detail
│   ├── Similar Photos
│   ├── Album Draft
│   └── Settings
└── Account
```

---

## 3. Screens

## MD-00 — Entry Point

Vị trí:

- Home;
- tab riêng;
- card “Khám phá ký ức”.

Card:

```text
Khám phá ký ức
Tìm lại những chuyến đi và khoảnh khắc đáng nhớ trong thư viện ảnh.

[Bắt đầu]
```

Nếu scan đã có:

```text
Khám phá ký ức
12 đề xuất mới · Đã khảo sát đến năm 2021

[Tiếp tục]
```

---

## MD-01 — Onboarding

### Mục tiêu

Giải thích giá trị trước khi xin quyền.

### Nội dung

Title:

```text
Những Album đáng nhớ có thể đã nằm sẵn trong iPhone của bạn
```

Ba ý:

```text
Tìm các nhóm ảnh theo thời gian và địa điểm
Phân tích ngay trên thiết bị
Không upload ảnh khi bạn chưa xác nhận
```

CTA chính:

```text
Khám phá thư viện ảnh
```

CTA phụ:

```text
Để sau
```

---

## MD-02 — Permission Result

### Full Access

```text
Đã cho phép toàn bộ thư viện

Nizi có thể tìm các sự kiện xuyên suốt nhiều năm.
[Bắt đầu khám phá]
```

### Limited Access

```text
Nizi chỉ được xem một số ảnh

Các đề xuất sẽ chỉ dựa trên những ảnh bạn đã chọn.
[Tiếp tục với ảnh đã chọn]
[Chọn thêm ảnh]
```

### Denied

```text
Nizi chưa thể truy cập Photos

Bạn có thể cấp quyền trong Settings để sử dụng Khám phá ký ức.
[Mở Settings]
[Để sau]
```

---

## MD-03 — Scan Progress

### Header

```text
Đang khám phá thư viện
```

### Progress card

```text
12.450 / 28.300 ảnh
44%

Đang xử lý ảnh từ năm 2021
```

### Findings card

```text
Đã tìm thấy
18 sự kiện tiềm năng
```

### Actions

```text
[Tạm dừng]
[Tiếp tục dùng Nizi]
```

### Quy tắc

- Không khóa người dùng ở màn hình này.
- Khi có candidate tốt đầu tiên, hiển thị:

```text
Đã có đề xuất đầu tiên
[Xem ngay]
```

---

## MD-04 — Discovery Home

### Sections

1. Đề xuất mới.
2. Tiếp tục khảo sát.
3. Theo năm.
4. Album Draft.
5. Đã bỏ qua.

### Candidate card

```text
[Cover]

Đà Nẵng & Hội An
08–11/06/2024

186 ảnh · 4 ngày
Nizi đã chọn trước 42 ảnh

[Xem lại]
```

Badge tùy chọn:

```text
Đề xuất mới
Cần tải từ iCloud
Limited Access
```

---

## MD-05 — Years Explorer

Hiển thị:

```text
2026    1.240 ảnh    8 đề xuất
2025    4.860 ảnh   16 đề xuất
2024    7.230 ảnh   21 đề xuất
...
```

Mỗi năm có 1–4 thumbnail đại diện.

Khi mở năm:

- danh sách tháng;
- số ảnh;
- các candidate liên quan.

Không cần tái tạo Apple Photos grid trong MVP.

---

## MD-06 — Candidate Detail

### Header

```text
Đà Nẵng & Hội An
08–11/06/2024
```

Metadata:

```text
186 ảnh
4 ngày
3 khu vực
5 phiên chụp
```

### Why card

```text
Vì sao Nizi đề xuất Album này?

• Nhiều ảnh được chụp liên tục trong 4 ngày
• Phần lớn ảnh nằm trong cùng hành trình
• Có 12 ảnh Favorite
```

### Gallery modes

```text
Nổi bật
Tất cả
Theo ngày
Ảnh tương tự
```

### Bottom action bar

```text
42 ảnh đã chọn
[Chỉnh lựa chọn]
[Tạo Album]
```

---

## MD-07 — Photo Selection

Grid dùng lazy loading.

Mỗi cell:

- thumbnail;
- checkmark;
- badge Favorite;
- badge iCloud nếu cần;
- similarity count nếu thuộc nhóm.

Toolbar:

```text
Chọn đề xuất
Chọn tất cả
Bỏ chọn
Lọc
```

Filter MVP:

```text
Đã chọn
Favorite
Ảnh
Video
Screenshot
```

---

## MD-08 — Similar Photos

Ví dụ:

```text
8 ảnh tương tự
Nizi đề xuất giữ 2 ảnh
```

Hiển thị nhóm ngang hoặc grid.

Ảnh recommended có nhãn:

```text
Đề xuất
```

Actions:

```text
[Giữ ảnh được đề xuất]
[Tự chọn]
```

MVP có thể trì hoãn màn hình này sang Sprint 006.

---

## MD-09 — Album Draft

Fields:

```text
Tên Album
Khoảng thời gian
Địa điểm
Ảnh bìa
Số ảnh
```

Preview:

```text
42 ảnh
5 ảnh cần tải từ iCloud
Ước tính upload: 312 MB
```

Actions:

```text
[Lưu bản nháp]
[Chuẩn bị Album]
```

Không upload ngay khi vừa mở màn hình.

---

## MD-10 — Upload Preparation

Checklist:

```text
Đang kiểm tra ảnh: 42/42
Đang tải từ iCloud: 3 ảnh
Sẵn sàng upload: 39 ảnh
```

Cho phép:

```text
[Tạm dừng]
[Tiếp tục]
```

Hiển thị lỗi theo ảnh, không chỉ một lỗi chung.

---

## MD-11 — Discovery Settings

Sections:

### Quyền truy cập

```text
Photos Access: Full
[Thay đổi trong Settings]
```

### Khảo sát

```text
Cho phép thumbnail từ iCloud
Chỉ xử lý khi có Wi‑Fi
Tạm dừng khi pin yếu
```

### Dữ liệu

```text
Dữ liệu khám phá: 84 MB
[Xóa dữ liệu khám phá]
```

### Giới thiệu riêng tư

```text
Ảnh chỉ được upload sau khi bạn xác nhận tạo Album.
```

---

## 4. Navigation Flow

```text
Entry
→ Onboarding
→ Permission
→ Scan
→ Discovery Home
→ Candidate Detail
→ Photo Selection
→ Album Draft
→ Upload Preparation
→ Album Created
```

Alternative:

```text
Discovery Home
→ Years Explorer
→ Candidate Detail
```

---

## 5. UI States

Mỗi màn hình phải có:

- loading;
- loaded;
- empty;
- error;
- limited permission;
- offline;
- partial data.

Không dùng spinner toàn màn hình lâu. Ưu tiên skeleton và progress cụ thể.

---

## 6. Copywriting Guidelines

### Nên dùng

```text
Nizi đang khám phá ảnh từ năm 2022
Nizi đã tìm thấy một chuyến đi có thể tạo Album
Ảnh được xử lý trên iPhone của bạn
Bạn luôn có thể thay đổi lựa chọn
```

### Không nên dùng

```text
AI đã quyết định
Nizi sẽ upload toàn bộ ảnh
Đang thu thập dữ liệu
Đã xác định chính xác đây là chuyến đi
```

---

## 7. Accessibility

- Hỗ trợ Dynamic Type.
- VoiceOver đọc được số ảnh và trạng thái chọn.
- Không dùng màu làm tín hiệu duy nhất.
- Cell có vùng chạm tối thiểu phù hợp.
- Progress có text, không chỉ vòng tròn.
- Contrast đạt chuẩn.

---

## 8. Performance UI

- Dùng `LazyVGrid`.
- Không tạo thumbnail full-resolution.
- Cell hủy request khi biến mất.
- ViewModel không giữ `UIImage` cho toàn bộ danh sách.
- Candidate list dùng cover nhỏ.
- Full-screen preview mới yêu cầu ảnh lớn.

---

## 9. Design tokens đề xuất

Nizi có thể dùng phong cách:

- nền sáng ấm;
- ảnh là trọng tâm;
- text tối giản;
- accent mềm;
- card bo góc vừa;
- không quá nhiều gradient;
- không dùng UI kỹ thuật kiểu diagnostics trong app thật.

Màn hình diagnostics có thể thô và tách riêng debug build.

---

## 10. Debug-only screen

Tên:

```text
Photo Library Diagnostics
```

Chỉ xuất hiện trong Debug build.

Hiển thị:

```text
Authorization
Total assets
Assets with date
Assets with GPS
Oldest date
Newest date
Scan duration
Current batch
Memory usage
Candidate count
```

Actions:

```text
Scan metadata
Clear index
Rebuild sessions
Rebuild candidates
Load 200 thumbnails
Test iCloud
Export debug summary
```

---

## 11. Definition of Done UI

- Permission flow rõ ràng.
- Full/Limited/Denied đều có màn hình.
- Scan không khóa app.
- Candidate có reason.
- Người dùng sửa selection được.
- AlbumDraft tách biệt upload.
- iCloud requirement hiển thị rõ.
- Data reset dễ tìm.
- UI chạy ổn trên iPhone thật.
