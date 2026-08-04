# GOOGLE DRIVE SHARE LINK IMPORT

## Yêu cầu phát triển tính năng nhập ảnh từ Google Drive Share Link cho Nizi Move

**Phiên bản:** MVP v1.0
**Ngày:** 2026-08-04

---

# 1. Mục tiêu

Bổ sung một nguồn nhập ảnh mới cho **Nizi Move**.

Hiện tại Nizi Move chỉ nhận ảnh từ máy tính:

```text
Folder trên máy tính
→ Browser chọn ảnh
→ Browser resize (nếu chọn)
→ Upload lên Nizi Move
→ Import Session
→ QR
→ Nizi Native
```

Mục tiêu mới:

```text
Google Drive Share Link
→ Nizi Move
→ Đọc danh sách ảnh
→ Hiển thị gallery
→ User chọn ảnh
→ Chỉ tải những ảnh đã chọn
→ Resize/Nén (tuỳ chọn)
→ Import Session hiện có
→ QR
→ Nizi Native
```

Đây **không phải** một hệ thống import mới.

Google Drive chỉ là **một nguồn dữ liệu đầu vào** của Nizi Move.

Toàn bộ:

* QR
* Pairing
* ImportSession
* Manifest
* Native download
* SHA256
* Cleanup

được tái sử dụng hoàn toàn.

---

# 2. Bài toán cần giải quyết

Một Google Drive Share Link có thể chứa:

```text
1.200 ảnh

Tổng dung lượng:

28 GB
```

Trong thực tế người dùng chỉ cần:

```text
35 ảnh
```

Không được:

```text
Download toàn bộ 28GB
↓

Hiển thị

↓

Cho chọn
```

Mà phải:

```text
Đọc metadata

↓

Hiển thị thumbnail

↓

User chọn

↓

Chỉ download 35 ảnh
```

Đây là yêu cầu quan trọng nhất của toàn bộ tính năng.

---

# 3. Kiến trúc tổng thể

```text
Google Drive Share Link

↓

Inspect Link

↓

List Metadata

↓

Thumbnail Gallery

↓

User Selection

↓

Download Selected Originals

↓

Resize/Nén (nếu chọn)

↓

Import Session

↓

Finalize

↓

QR

↓

Nizi Native
```

Native hoàn toàn không biết ảnh đến từ Google Drive.

Native chỉ biết:

```text
Import Session
```

---

# 4. Không sử dụng trong MVP

Không triển khai:

* Google Drive trong Files
* Document Picker
* Google SDK trên iPhone
* Google OAuth trong App Native
* Google API Key trong App
* Download toàn bộ folder
* Google Drive Browser trên Native

Google Drive chỉ được xử lý trên server của Nizi Move.

---

# 5. Luồng sử dụng

## Bước 1

Người dùng mở:

```text
move.nizi.vn
```

Có thêm section mới:

```text
==============================

Google Drive

Paste Google Drive Share Link

[________________________________]

        [ Đọc thư mục ]

==============================
```

---

## Bước 2

User paste:

```text
https://drive.google.com/drive/folders/xxxxxxxx
```

Server:

* kiểm tra link

* lấy Folder ID

* lấy Resource Key nếu có

---

## Bước 3

Server đọc:

* danh sách file

* metadata

* thumbnail

Không download file gốc.

---

## Bước 4

Web hiển thị:

```text
Đã tìm thấy

1047 ảnh

24.8GB
```

Gallery:

```text
□ □ □ □ □ □

□ □ □ □ □ □

□ □ □ □ □ □
```

Ảnh hiển thị bằng thumbnail.

Không dùng ảnh gốc.

---

## Bước 5

Người dùng chọn:

```text
42 ảnh
```

Hiển thị:

```text
42 ảnh

856MB
```

---

## Bước 6

Người dùng chọn:

```text
○ Giữ nguyên

● Tối ưu dung lượng
```

---

## Bước 7

User bấm

```text
Tạo phiên chuyển ảnh
```

Lúc này server mới bắt đầu download.

Không download trước.

---

# 6. Kiến trúc Download

Sai:

```text
Drive

↓

Download 1000 ảnh

↓

User chọn
```

Đúng:

```text
Drive

↓

Metadata

↓

Thumbnail

↓

User chọn

↓

Download originals đã chọn
```

Ví dụ:

```text
Folder:

1000 ảnh

20GB

↓

User chọn

35 ảnh

↓

Server download

35 ảnh
```

---

# 7. Metadata

Inspect chỉ lấy:

```text
File ID

Tên

Kích thước

MimeType

Ngày

Width

Height

Thumbnail

ResourceKey

CanDownload
```

Không lấy binary.

---

# 8. Gallery

Gallery phải hoạt động tốt với:

```text
1000+

2000+

5000 ảnh
```

Không render toàn bộ.

Yêu cầu:

* Virtual Grid

* Lazy Loading

* Infinite Scroll

* Chỉ load thumbnail trong viewport

* Không giữ toàn bộ thumbnail trong RAM

---

# 9. Thumbnail

Thumbnail dùng để:

* xem trước

* chọn ảnh

Không dùng để import.

Không lưu thumbnail thành asset.

Không resize thumbnail.

---

# 10. Selection

Cho phép:

✓ Chọn từng ảnh

✓ Bỏ chọn

✓ Chọn tất cả

✓ Bỏ chọn tất cả

✓ Chọn theo trang

✓ Hiển thị tổng số ảnh

✓ Tổng dung lượng

---

# 11. Download

Sau khi user xác nhận.

Server tạo:

```text
Import Session
```

Asset:

```text
pending
```

Sau đó download từng ảnh.

Không download song song quá nhiều.

Đề xuất:

```text
Download:

3 concurrent
```

Không download 100 ảnh cùng lúc.

---

# 12. Pipeline download

```text
Google Drive

↓

HTTP Stream

↓

temporary/

↓

Validate

↓

Resize nếu cần

↓

SHA256

↓

assets/

↓

ready
```

Không dùng:

```text
download

↓

Data()

↓

RAM
```

Phải stream trực tiếp xuống file.

---

# 13. Resize

Hai chế độ.

## Keep Original

Không thay đổi.

## Optimize

JPEG

* max 3000px

* quality khoảng 85%

PNG

* giữ nguyên

GIF

* giữ nguyên

HEIC

* giữ nguyên MVP

Nếu resize lỗi:

fallback original.

---

# 14. Progress

Trong lúc download.

Hiển thị:

```text
Đang chuẩn bị ảnh

12 / 42
```

Không cần progress theo byte.

Theo số file.

---

# 15. Import Session

Tái sử dụng hoàn toàn.

Không tạo model mới.

Chỉ thêm:

```text
SourceType

google_drive
```

Nếu cần.

---

# 16. QR

Không thay đổi.

Sau khi:

```text
ready
```

↓

Finalize

↓

QR

↓

Native

---

# 17. Native

Không sửa protocol.

Native tiếp tục:

Claim

↓

Manifest

↓

Download

↓

Photos

↓

Completed

↓

Cleanup

Native không biết:

Google Drive

Folder

Share Link

---

# 18. Storage

Không lưu lâu dài.

```text
temporary

↓

assets

↓

completed

↓

delete
```

Giống upload hiện tại.

---

# 19. Bảo mật

Không lưu:

Google Credential

Google Token

Google Refresh Token

Google API Key

trong:

* App Native

* Browser

* QR

* Manifest

Google credential chỉ tồn tại trên server.

---

# 20. Trường hợp lỗi

Ví dụ:

Folder không public.

↓

Thông báo:

```text
Không thể truy cập thư mục.

Hãy kiểm tra quyền chia sẻ Google Drive.
```

Không báo lỗi chung.

Các lỗi:

* Link sai

* Folder không tồn tại

* Không có ảnh

* Không có quyền

* Download lỗi

* Quá dung lượng

* Hết hạn

đều phải phân biệt.

---

# 21. Không thay đổi

Không sửa:

QR

Manifest

Native API

Import Session

Native Download

Cleanup

SHA256

Pairing

Upload từ máy tính

Tính năng Google Drive phải hoạt động như một nguồn nhập mới, không làm ảnh hưởng luồng upload hiện tại.

---

# 22. Sprint triển khai

## Sprint 1

* Parse Google Drive Link

* Inspect Folder

* Metadata

* Thumbnail

* Gallery

* Selection

---

## Sprint 2

* Download Selected

* Temporary Storage

* Validation

* Progress

---

## Sprint 3

* Resize

* Import Session

* QR

* Native Test

---

## Sprint 4

* Cleanup

* Retry

* Error Handling

* Performance

* Regression Test

---

# 23. Tiêu chí nghiệm thu

Được coi là hoàn thành khi:

✓ Paste được Google Drive Share Link

✓ Đọc được folder

✓ Hiển thị được gallery

✓ Không download ảnh gốc trước khi chọn

✓ Chỉ download ảnh đã chọn

✓ Resize đúng

✓ Import Session hoạt động

✓ QR hoạt động

✓ Native nhận ảnh bình thường

✓ Không regression upload từ máy tính

✓ Folder 1000+ ảnh vẫn hoạt động mượt

✓ Không đưa Google Credential vào App Native

✓ Không tải toàn bộ folder trước khi user chọn
