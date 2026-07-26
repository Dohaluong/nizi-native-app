# SPRINT-005 — DISCOVERY UI

Version: 1.0

---

# 1. Mục tiêu

Sprint 001~004 đã hoàn thành:

- PhotoKit
- Local Memory Index
- Event Discovery

Từ Sprint 005, bắt đầu xây dựng giao diện người dùng.

Lưu ý:

Memory Discovery KHÔNG phải màn hình chính của ứng dụng.

Memory Discovery chỉ là một công cụ giúp người dùng tìm các sự kiện/chuyến đi để tạo Album.

Màn hình Home chính luôn là Timeline Album.

---

# 2. Product Flow

```
Launch

↓

Hello Nizi

↓

Permission

↓

Scope Selection

↓

Scan

↓

Home

↓

Timeline Album

↓

Các sự kiện / chuyến đi

↓

Candidate List

↓

Candidate Detail

↓

( Sprint 006 )
Album Draft
```

---

# 3. First Launch

Nếu ứng dụng chưa từng scan.

Hiển thị:

```
Hello Nizi
```

Không hiển thị danh sách Candidate.

Không hiển thị Album.

---

## 3.1 Nội dung

Tiêu đề

```
Hello Nizi
```

Đoạn mô tả

```
Nizi sẽ khảo sát thư viện ảnh của bạn
để tìm các chuyến đi,
các sự kiện
và những nhóm ảnh
có thể trở thành một Album.

Toàn bộ dữ liệu được xử lý trên thiết bị của bạn.

Bạn luôn có quyền lựa chọn phạm vi khảo sát.
```

---

## 3.2 CTA

Button

```
Bắt đầu
```

---

# 4. Scope Selection

Sau khi bấm Bắt đầu.

Hiển thị lựa chọn.

```
Khảo sát

(•) Toàn bộ thư viện

( ) Chỉ một số năm

( ) Chỉ một số tháng
```

Nếu chọn

Toàn bộ

↓

scan toàn bộ.

Nếu chọn

Theo năm

↓

Hiển thị list năm.

Ví dụ

```
2026

2025

2024

...

2010
```

Cho phép chọn nhiều năm.

Nếu chọn

Theo tháng

↓

Hiển thị

```
2025

01

02

03

...

12
```

Có thể mở rộng.

Không cần Calendar.

Không cần Date Picker.

---

# 5. Permission

Sau khi xác nhận phạm vi.

Mới xin quyền Photo Library.

Không xin quyền ngay khi mở App.

---

Permission Denied

Hiển thị

```
Nizi chưa thể đọc thư viện ảnh.

Mở Cài đặt
```

---

Limited Access

Hiển thị

```
Bạn chỉ chia sẻ một phần thư viện.

Tiếp tục

hoặc

Chọn thêm ảnh
```

---

# 6. Scan Progress

Trong quá trình Scan.

Hiển thị

```
Đang khảo sát thư viện ảnh...

20345 / 105379

███████-----
```

Có

Pause

Resume

Background.

Không chặn navigation.

---

# 7. Sau khi Scan

Không mở Candidate List.

Đi tới

Home.

---

# 8. Home

Home là Timeline Album.

Không phải Memory Discovery.

Toàn bộ Album đã tạo.

Theo Timeline.

Phần này sẽ rewrite từ WebApp.

Không tự thiết kế mới.

---

## 8.1 Home Header

```
Hello Luong

105 Album

23450 Photos
```

(Chỉ ví dụ.

Số liệu lấy từ Album.)

---

## 8.2 Quick Action

Một Card.

```
Các sự kiện / chuyến đi

18 Candidate mới
```

Bấm

↓

Candidate List.

---

# 9. Candidate List

Hiển thị EventCandidate.

Không hiển thị toàn bộ ảnh.

Mỗi Card.

```
Ảnh Cover

↓

01 Jul - 02 Jul 2020

278 ảnh

Trip

★★★★☆

```

Có

Date

Photo Count

Candidate Type

Score

Reason ngắn.

Không hiển thị quá nhiều text.

---

# 10. Candidate Detail

Khi bấm.

Hiển thị.

```
Cover

↓

278 ảnh

↓

Timeline

↓

Reason

↓

Grid Thumbnail
```

Reason.

Ví dụ.

```
278 ảnh trong 2 ngày

3 phiên liên tiếp

17 Favorite

Cùng khu vực
```

---

Grid.

Không load toàn bộ.

Virtual Scroll.

Thumbnail.

Không tải ảnh gốc.

---

# 11. Candidate Actions

Chỉ có.

```
Tạo Album
```

Không Upload.

Không Sync.

Không AI.

Bấm.

↓

Sprint 006.

---

# 12. Years Explorer

Trong Candidate List.

Có Filter.

```
2026

2025

2024

...
```

Không cần Tree.

Không Calendar.

---

# 13. Search

Sprint này chưa làm.

---

# 14. Filter

Sprint này chỉ có.

```
Year

Candidate Type
```

Không thêm.

---

# 15. Loading

Skeleton.

Không Spinner toàn màn hình.

---

# 16. Empty State

```
Chưa tìm thấy sự kiện nào.

Thử mở rộng phạm vi khảo sát.
```

---

# 17. Error

Có nút

```
Scan lại
```

Không crash.

---

# 18. Memory

Không giữ toàn bộ Thumbnail.

Dùng LazyVGrid.

Giải phóng Thumbnail ngoài màn hình.

---

# 19. Accessibility

Toàn bộ Button.

Có Label.

Dynamic Type.

VoiceOver.

---

# 20. Out of Scope

Không làm

- Upload
- Login
- API
- Album Draft
- AI
- Vision
- Similarity
- Map
- Chia sẻ
- Cloud Sync

---

# 21. Acceptance

User có thể

Hello

↓

Permission

↓

Scan

↓

Home

↓

Candidate List

↓

Candidate Detail

↓

Tạo Album

mà không gặp màn hình trắng.

Không tăng RAM vô hạn khi scroll.

Không tải ảnh gốc.

Không block UI khi Scan.