# SPRINT-005B — PHOTO CURATION

Version: 1.1  
Status: Ready for implementation

---

# 1. Mục tiêu

Sprint-005B xây dựng chức năng tự động sắp xếp và đề xuất những ảnh phù hợp nhất trong một Event Candidate.

Ví dụ:

```text
Một sự kiện có 286 ảnh
        ↓
Nizi chia thành các nhóm ảnh liên quan
        ↓
Đánh giá chất lượng và độ trùng lặp
        ↓
Đề xuất khoảng 20–40 ảnh
        ↓
Người dùng xem lại và điều chỉnh
```

Mục tiêu chính:

> Giúp người dùng không phải tự chọn thủ công vài chục ảnh từ hàng trăm ảnh gần giống nhau.

Sprint này không tạo Album chính thức.

Sprint này chỉ tạo kết quả lựa chọn ảnh để chuyển sang Album Draft trong Sprint-006.

---

# 2. Nguyên tắc kế thừa

Sprint-005B phải kế thừa toàn bộ kết quả đã hoàn thành trong các Sprint trước.

Các phần đã hoạt động tốt phải được giữ nguyên:

- PhotoKit authorization;
- Photo Library scanning;
- Local Memory Index;
- trạng thái scan;
- pause và resume scan;
- Event Discovery;
- Event Candidate;
- session sơ bộ;
- Candidate List;
- Candidate Detail;
- các asset identifier đã được lưu;
- metadata đã được lập chỉ mục;
- các kết quả scan trên thư viện hiện tại.

## Yêu cầu quan trọng nhất

**Không được scan lại toàn bộ Photo Library khi triển khai Sprint-005B.**

Không được thay thế hoặc viết lại pipeline scan hiện có nếu không thật sự cần thiết.

Không được xoá Local Memory Index hiện tại.

Không được tạo một scanner mới chạy lại hàng chục hoặc hàng trăm nghìn ảnh.

Không được yêu cầu người dùng thực hiện lại quá trình scan đã hoàn thành.

Sprint-005B chỉ xử lý sâu những ảnh thuộc Event Candidate mà người dùng đang mở.

---

# 3. Phân biệt hai tầng xử lý

Nizi sử dụng hai tầng xử lý khác nhau.

---

## 3.1 Tầng 1 — Library Scan và Event Discovery

Tầng này đã được thực hiện trong các Sprint trước.

Luồng hiện có:

```text
Photo Library
        ↓
Đọc metadata
        ↓
Local Memory Index
        ↓
Sắp xếp theo thời gian và vị trí
        ↓
Phân chia session sơ bộ
        ↓
Phát hiện Event Candidate
```

Tầng này xử lý toàn bộ hoặc phạm vi thư viện mà người dùng đã lựa chọn.

Tầng này chỉ thực hiện các công việc nhẹ dựa chủ yếu trên metadata:

- asset local identifier;
- creation date;
- modification date nếu cần;
- media type;
- pixel width và height;
- favorite;
- location nếu có;
- burst identifier nếu có;
- duration đối với video;
- các metadata khác đã có trong Local Memory Index.

Tầng 1 không chịu trách nhiệm:

- phân tích mắt mở hay nhắm;
- đánh giá độ mờ chi tiết;
- so sánh nội dung từng cặp ảnh;
- nhận biết ảnh gần trùng lặp bằng pixel;
- chọn sẵn ảnh đẹp cho toàn bộ Event Candidate;
- tạo Album Preview.

Không thay đổi phạm vi của tầng này trong Sprint-005B.

---

## 3.2 Tầng 2 — Event Photo Curation

Tầng này được xây dựng trong Sprint-005B.

Tầng này chỉ chạy khi người dùng mở một Event Candidate cụ thể lần đầu tiên.

Luồng:

```text
Người dùng mở Event Candidate
        ↓
Lấy danh sách asset identifier đã có của Event Candidate
        ↓
Không scan lại thư viện
        ↓
Phân tích sâu các ảnh thuộc Event Candidate
        ↓
Chia thành nhóm ảnh gần nhau
        ↓
Đánh giá chất lượng
        ↓
Phát hiện ảnh gần trùng lặp
        ↓
Đề xuất ảnh tốt nhất
        ↓
Lưu kết quả local
        ↓
Hiển thị Photo Curation UI
```

Ví dụ:

```text
Thư viện có 105.379 ảnh

Event Candidate đang mở có 286 ảnh

Sprint-005B chỉ được xử lý 286 ảnh này.
```

Không được quay lại xử lý toàn bộ 105.379 ảnh.

---

# 4. Điều kiện bắt đầu Photo Curation

Photo Curation bắt đầu khi:

1. Người dùng mở Candidate Detail.
2. Event Candidate có danh sách asset identifier hợp lệ.
3. Event Candidate chưa có kết quả curation hợp lệ trong local cache.

Nếu đã có kết quả curation hợp lệ:

```text
Mở Event Candidate
        ↓
Đọc kết quả từ local database
        ↓
Hiển thị ngay
```

Không chạy lại phân tích.

---

# 5. Trạng thái Curation

Mỗi Event Candidate cần có trạng thái curation riêng.

Các trạng thái tối thiểu:

```text
notStarted
processing
completed
failed
outdated
```

Ý nghĩa:

## notStarted

Event Candidate chưa từng được phân tích sâu.

## processing

Photo Curation đang chạy.

## completed

Đã có kết quả hợp lệ và có thể hiển thị.

## failed

Quá trình phân tích bị lỗi hoặc bị gián đoạn.

## outdated

Kết quả cũ không còn phù hợp vì dữ liệu Event Candidate hoặc phiên bản thuật toán đã thay đổi.

---

# 6. Khi người dùng mở một Event Candidate

Candidate Detail phải mở ngay.

Không giữ người dùng ở Candidate List trong lúc xử lý.

Candidate Detail có thể hiển thị ngay các dữ liệu đã có:

- cover;
- ngày bắt đầu và kết thúc;
- số lượng ảnh;
- loại sự kiện;
- số session;
- lý do phát hiện;
- metadata cơ bản.

Sau đó mới hiện trạng thái phân tích.

Ví dụ:

```text
Nizi đang chọn những ảnh phù hợp nhất…

Đã xử lý 6 / 24 nhóm
```

Hoặc:

```text
Đang sắp xếp 286 ảnh…
```

Không dùng màn hình trắng.

Không chặn toàn bộ giao diện.

---

# 7. Không yêu cầu scan lại

Trong quá trình Photo Curation:

- không gọi lại chức năng scan toàn thư viện;
- không xoá trạng thái scan trước;
- không tạo lại toàn bộ Local Memory Index;
- không chạy lại Event Discovery cho tất cả ảnh;
- không yêu cầu cấp lại quyền Photo Library nếu quyền hiện tại vẫn hợp lệ;
- không thay đổi phạm vi scan mà người dùng đã chọn;
- không làm mất Event Candidate hiện có.

Photo Curation chỉ được yêu cầu tải hình ảnh hoặc thumbnail của các asset identifier thuộc Event Candidate đang xử lý.

---

# 8. Ba cấp độ phân nhóm

Claude phải phân biệt rõ ba khái niệm sau.

---

## 8.1 Event Candidate

Một sự kiện lớn đã được Event Discovery phát hiện.

Ví dụ:

```text
Chuyến đi 11/02/2021 – 12/02/2021

286 ảnh
```

Event Candidate đã tồn tại trước Sprint-005B.

---

## 8.2 Session

Một khoảng hoạt động trong Event Candidate.

Session sơ bộ đã có thể được tạo từ metadata trong Sprint trước.

Ví dụ:

```text
11/02 — 09:10–10:20 — 42 ảnh

11/02 — 13:40–15:10 — 73 ảnh

12/02 — 08:00–09:30 — 51 ảnh
```

Session được dùng để chia Event Candidate thành các phần nhỏ hơn.

Không nhất thiết mỗi Session chỉ chứa một nội dung duy nhất.

---

## 8.3 Similarity Group

Một nhóm ảnh có nội dung gần giống nhau.

Ví dụ:

```text
7 ảnh chụp liên tiếp cùng người, cùng góc

Nizi đề xuất 1 ảnh
```

Hoặc:

```text
10 ảnh cùng cảnh nhưng khác biểu cảm

Nizi đề xuất 2 ảnh
```

Similarity Group được tạo trong Sprint-005B bằng cách kết hợp:

- khoảng cách thời gian;
- burst metadata nếu có;
- hình ảnh gần giống nhau;
- chủ thể hoặc khuôn hình gần nhau;
- các tín hiệu phù hợp khác.

UI của Sprint-005B chủ yếu trình bày ảnh theo Similarity Group hoặc các nhóm hiển thị nhỏ tương đương.

---

# 9. Luồng xử lý Photo Curation

```text
Event Candidate
        ↓
Đọc asset identifier hiện có
        ↓
Lấy session sơ bộ
        ↓
Tải thumbnail hoặc ảnh kích thước phù hợp
        ↓
Tinh chỉnh thành Similarity Group
        ↓
Đánh giá chất lượng từng ảnh
        ↓
Phát hiện ảnh gần trùng lặp
        ↓
Chọn ảnh tốt nhất trong từng nhóm
        ↓
Cân bằng toàn bộ Event Candidate
        ↓
Lưu kết quả local
        ↓
Hiển thị lựa chọn đề xuất
```

---

# 10. Yêu cầu về ảnh đầu vào

Không cần tải ảnh gốc toàn độ phân giải để phân tích nếu thumbnail hoặc ảnh downsampled đáp ứng được tiêu chí.

Ưu tiên:

- request thumbnail hoặc target size phù hợp;
- hạn chế giữ nhiều ảnh trong RAM;
- xử lý theo batch;
- giải phóng ảnh sau khi tính xong feature;
- không lưu bản sao ảnh gốc;
- không thay đổi dữ liệu trong Apple Photos.

Ảnh gốc vẫn nằm trong Apple Photos và tiếp tục là source of truth.

---

# 11. Đánh giá chất lượng ảnh

Mỗi ảnh có thể được chấm một điểm chất lượng nội bộ.

Ví dụ:

```text
qualityScore: 0...100
```

Điểm này không bắt buộc hiển thị cho người dùng.

Các tiêu chí có thể gồm:

---

## 11.1 Độ nét

Ưu tiên:

- ảnh rõ nét;
- ít rung;
- chủ thể không bị motion blur nghiêm trọng.

---

## 11.2 Phơi sáng

Ưu tiên:

- ảnh không quá tối;
- ảnh không cháy sáng nghiêm trọng;
- độ tương phản còn đủ để nhìn rõ chủ thể.

---

## 11.3 Khuôn mặt

Khi ảnh có người, ưu tiên:

- khuôn mặt đủ rõ;
- khuôn mặt không bị che quá nhiều;
- khuôn mặt không bị cắt bất hợp lý;
- chủ thể chính nằm trong khung hình.

---

## 11.4 Mắt và biểu cảm

Khi có thể đánh giá đáng tin cậy, ưu tiên:

- mắt mở;
- biểu cảm tự nhiên;
- không chọn ảnh có nhắm mắt nếu cùng nhóm có ảnh tương đương tốt hơn.

Không loại bỏ tuyệt đối ảnh nhắm mắt trong mọi trường hợp.

Một số ảnh vẫn có thể có giá trị cảm xúc dù không đạt tiêu chuẩn chân dung thông thường.

---

## 11.5 Bố cục

Có thể ưu tiên:

- chủ thể dễ nhận biết;
- khung hình cân đối;
- không cắt mất phần quan trọng của người hoặc vật;
- không bị nghiêng hoặc lỗi bố cục quá rõ.

Không cần xây dựng một hệ thống chấm điểm nghệ thuật phức tạp trong Sprint này.

---

## 11.6 Favorite

Ảnh được người dùng đánh dấu Favorite trong Apple Photos nên được tăng ưu tiên.

Favorite không đồng nghĩa với việc bắt buộc phải chọn trong mọi tình huống, nhưng là một tín hiệu mạnh.

---

# 12. Near-Duplicate Detection

Đây là một phần cốt lõi của Sprint-005B.

Ví dụ:

```text
IMG_0001
IMG_0002
IMG_0003
IMG_0004
IMG_0005
```

Năm ảnh được chụp liên tiếp và gần giống nhau.

Nizi không nên đề xuất cả năm.

Nizi cần:

1. Nhận biết chúng thuộc cùng một Similarity Group.
2. So sánh chất lượng.
3. Chọn ảnh tốt nhất.
4. Có thể chọn thêm một ảnh nếu nội dung hoặc biểu cảm thực sự khác biệt.
5. Giữ lại toàn bộ ảnh để người dùng có thể xem và thay đổi lựa chọn.

Không xoá ảnh gần trùng lặp.

Chỉ thay đổi trạng thái lựa chọn.

---

# 13. Logic lựa chọn theo nhóm

Không đặt cứng mỗi nhóm chỉ chọn một ảnh.

Logic tham khảo:

```text
Nhóm 2–5 ảnh gần giống nhau
→ thường chọn 1 ảnh

Nhóm 6–12 ảnh gần giống nhau
→ thường chọn 1–2 ảnh

Nhóm có nhiều biểu cảm hoặc khoảnh khắc khác nhau
→ có thể chọn nhiều hơn

Ảnh đơn lẻ, khác biệt rõ ràng
→ có thể tự động chọn

Nhóm chất lượng thấp
→ có thể không chọn ảnh nào
```

Đây là quy tắc mềm.

Thuật toán phải ưu tiên sự đa dạng của nội dung, không chỉ điểm chất lượng tuyệt đối.

---

# 14. Cân bằng toàn sự kiện

Sau khi chọn trong từng Similarity Group, Nizi cần cân bằng toàn bộ Event Candidate.

Mục tiêu:

- không chọn quá nhiều ảnh của một cảnh;
- không bỏ trống các phần quan trọng trong timeline;
- giữ sự đa dạng về thời gian, địa điểm và nội dung;
- tránh 20 ảnh rất giống nhau chỉ vì đều có điểm chất lượng cao.

Khoảng số lượng tham khảo:

```text
Event dưới 50 ảnh
→ khoảng 8–20 ảnh

Event từ 50–150 ảnh
→ khoảng 15–30 ảnh

Event từ 150–300 ảnh
→ khoảng 20–40 ảnh

Event trên 300 ảnh
→ khoảng 30–60 ảnh
```

Đây không phải giới hạn cứng.

Ví dụ:

```text
300 ảnh nhưng chỉ có 15 khoảnh khắc khác nhau
```

Nizi không cần cố chọn đủ 20 hoặc 40 ảnh.

Ngược lại, một sự kiện dài và đa dạng có thể cần nhiều ảnh hơn.

---

# 15. Kết quả Photo Curation

Sau khi hoàn thành:

```text
286 ảnh gốc

Nizi đề xuất 32 ảnh

254 ảnh chưa được chọn
```

Kết quả này chưa phải Album.

Đây là:

```text
Event Curation Result
```

hoặc:

```text
Album Selection Preview
```

Sprint-006 sẽ sử dụng kết quả này để tạo Album Draft.

---

# 16. Dữ liệu cần lưu local

Tên model có thể điều chỉnh theo kiến trúc hiện tại, nhưng cần thể hiện được các thông tin tương đương.

---

## 16.1 EventCurationResult

```text
id
eventCandidateID
status
algorithmVersion
createdAt
updatedAt
completedAt
sourceAssetCount
selectedAssetCount
groupCount
```

---

## 16.2 PhotoCurationGroup

```text
id
eventCurationResultID
sessionID
startTime
endTime
sortOrder
assetCount
suggestedCount
```

---

## 16.3 PhotoCurationItem

```text
id
groupID
assetLocalIdentifier
sortOrder

qualityScore
sharpnessScore
exposureScore
faceScore
similarityClusterIdentifier

isSuggested
isSelected
selectionSource
```

Không bắt buộc phải lưu tất cả điểm thành các cột riêng nếu kiến trúc hiện tại phù hợp hơn với một object hoặc payload khác.

---

# 17. Nguồn lựa chọn

Cần phân biệt:

```text
systemSuggested
userAdded
userRemoved
```

Ý nghĩa:

## systemSuggested

Ảnh được Nizi tự động chọn.

## userAdded

Ảnh ban đầu không được chọn nhưng người dùng đã chọn thêm.

## userRemoved

Ảnh ban đầu được đề xuất nhưng người dùng đã bỏ chọn.

Quyết định của người dùng phải được ưu tiên hơn kết quả thuật toán.

---

# 18. Không ghi đè quyết định người dùng

Sau khi người dùng đã chỉnh sửa lựa chọn:

- không tự động chọn lại khi họ mở màn hình lần sau;
- không ghi đè `userAdded`;
- không khôi phục ảnh `userRemoved`;
- không chạy lại thuật toán âm thầm.

Nếu cần chạy lại, phải là hành động rõ ràng của người dùng hoặc do kết quả cũ không còn hợp lệ.

Khi chạy lại, cần có chiến lược bảo toàn thay đổi thủ công hoặc yêu cầu xác nhận phù hợp.

Sprint này chưa cần xây dựng UX phức tạp cho việc hợp nhất hai kết quả, nhưng tuyệt đối không được âm thầm xoá quyết định của người dùng.

---

# 19. Điều kiện sử dụng cache

Kết quả Photo Curation được tái sử dụng khi:

- Event Candidate vẫn còn tồn tại;
- số lượng asset không thay đổi;
- các asset identifier chính vẫn còn hợp lệ;
- algorithm version tương thích;
- kết quả không ở trạng thái failed hoặc outdated.

---

# 20. Khi nào cần phân tích lại

Chỉ phân tích lại khi:

- người dùng chủ động yêu cầu chọn lại;
- Event Candidate có thêm hoặc mất ảnh;
- asset trong sự kiện không còn truy cập được;
- algorithm version thay đổi và hệ thống quyết định kết quả cũ không còn phù hợp;
- dữ liệu curation bị lỗi;
- người dùng xoá cache tương ứng.

Không phân tích lại chỉ vì người dùng đóng rồi mở màn hình.

---

# 21. UI tổng thể

Candidate Detail hiển thị:

```text
Cover

Thông tin Event

Tóm tắt lựa chọn

Các nhóm ảnh

Bottom Selection Bar
```

Ví dụ:

```text
286 ảnh

Nizi đã chọn giúp bạn 32 ảnh
```

---

# 22. Grid ảnh

Sử dụng grid vuông.

Không dùng masonry trong màn hình lựa chọn.

Ví dụ:

```text
□ □ □ □
□ □ □ □
□ □ □ □
```

Mục tiêu:

- xem được nhiều ảnh;
- dễ so sánh ảnh gần giống nhau;
- bố cục gọn;
- dễ nhận biết ảnh được chọn và chưa được chọn.

Số cột có thể thích ứng theo kích thước màn hình nhưng phải giữ cảm giác compact.

---

# 23. Hiển thị ảnh được đề xuất

Ảnh được Nizi đề xuất:

- hiển thị sáng bình thường;
- có dấu tích màu xanh;
- được tính vào tổng số ảnh đã chọn.

Ảnh không được đề xuất:

- tối nhẹ;
- vẫn nhìn rõ;
- có dấu tích xám hoặc trạng thái chưa chọn;
- vẫn có thể bấm để xem;
- vẫn có thể được người dùng chọn lại.

Không làm ảnh chưa chọn tối đến mức khó xem.

---

# 24. Nhóm ảnh

Các Similarity Group cần được phân tách bằng:

- khoảng cách dọc nhỏ;
- header ngắn;
- hoặc divider nhẹ.

Không tạo card nặng cho từng nhóm.

Ví dụ:

```text
09:12

8 ảnh · Nizi chọn 2

[grid]
```

Hoặc:

```text
Nhóm 1

8 ảnh · Đã chọn 2

[grid]
```

Ưu tiên thời gian nếu metadata đủ rõ và có ý nghĩa.

Không cần diễn giải bằng văn bản dài cho từng nhóm.

---

# 25. Tương tác lựa chọn

Người dùng có thể:

- bấm vào ảnh chưa chọn để chọn thêm;
- bấm vào ảnh đã chọn để bỏ chọn;
- xem ảnh ở kích thước lớn;
- chuyển qua lại giữa các ảnh trong cùng nhóm;
- giữ toàn bộ thay đổi khi quay lại màn hình.

Khi người dùng thay đổi lựa chọn:

- cập nhật tổng số ảnh đã chọn ngay;
- lưu thay đổi local;
- không chạy lại thuật toán.

---

# 26. Xem ảnh toàn màn hình

Khi bấm hoặc long press vào ảnh, có thể mở preview toàn màn hình.

Preview cho phép:

- xem ảnh rõ hơn;
- chuyển ảnh trước và sau;
- biết ảnh đang được chọn hay chưa;
- đổi trạng thái chọn trực tiếp.

Không cần chỉnh sửa ảnh trong Sprint này.

---

# 27. Bottom Selection Bar

Hiển thị cố định ở cuối màn hình.

Ví dụ:

```text
32 / 286 ảnh đã chọn

Tiếp tục
```

Hoặc:

```text
Đã chọn 32 ảnh

Tạo Album
```

Tên hành động cuối cùng cần thống nhất với Sprint-006.

Trong Sprint-005B, nút này chỉ chuyển dữ liệu sang luồng Album Draft.

Sprint-005B không tự tạo Album hoàn chỉnh và không upload ảnh.

---

# 28. Trạng thái đang xử lý

Khi curation đang chạy:

- Candidate Detail vẫn mở;
- hiển thị metadata đã có;
- hiển thị progress;
- có thể hiển thị nhóm đã hoàn thành trước;
- không yêu cầu chờ toàn bộ nếu kiến trúc hỗ trợ streaming kết quả.

Ví dụ:

```text
Nizi đang chọn ảnh…

Đã xử lý 14 / 27 nhóm
```

Nếu chưa thể hiển thị từng phần, có thể hiển thị progress tổng thể trước.

---

# 29. Pause và huỷ

Sprint này không bắt buộc phải có giao diện Pause riêng cho Photo Curation.

Tuy nhiên:

- tác vụ không được làm treo UI;
- phải phản ứng với cancellation khi view bị đóng hoặc task bị thay thế;
- kết quả đã xử lý có thể được lưu tạm nếu kiến trúc phù hợp;
- mở lại không được gây crash hoặc tạo nhiều task trùng nhau.

Không sử dụng logic pause/resume của toàn bộ Library Scan để chạy lại Photo Curation.

Đây là hai tác vụ khác nhau.

---

# 30. Error State

Nếu Photo Curation thất bại:

```text
Nizi chưa thể sắp xếp sự kiện này.

Thử lại
```

Có thể hiển thị thêm lý do kỹ thuật trong debug mode.

Trong giao diện người dùng:

- không hiển thị stack trace;
- không xoá Event Candidate;
- không xoá Local Memory Index;
- không yêu cầu scan lại thư viện;
- cho phép thử lại riêng Event Candidate này.

---

# 31. Asset không còn tồn tại

Nếu một số asset đã bị xoá khỏi Apple Photos:

- bỏ qua asset không còn hợp lệ;
- cập nhật số lượng ảnh thực tế;
- không làm toàn bộ Event Candidate thất bại nếu vẫn còn đủ dữ liệu;
- đánh dấu kết quả curation là outdated nếu cần;
- phân tích lại riêng Event Candidate.

Không scan lại toàn bộ thư viện.

---

# 32. Hiệu năng

Photo Curation phải:

- chạy ngoài main thread;
- không block scrolling;
- xử lý theo batch;
- giới hạn số tác vụ ảnh đồng thời;
- dùng autorelease pool hoặc cơ chế giải phóng phù hợp;
- không giữ toàn bộ bitmap của 200–300 ảnh cùng lúc;
- ưu tiên thumbnail hoặc downsample;
- hỗ trợ cancellation;
- tránh tạo lại feature đã có nếu có cache.

Mục tiêu là giữ app phản hồi tốt trên iPhone thực tế.

---

# 33. Memory Management

Không giữ toàn bộ thumbnail của Event Candidate trong RAM.

UI sử dụng lazy loading.

Thumbnail ngoài vùng hiển thị có thể được giải phóng theo cơ chế cache phù hợp.

Feature phục vụ similarity hoặc quality scoring nên được lưu dưới dạng dữ liệu nhỏ nếu cần, không giữ bitmap gốc lâu dài.

---

# 34. Không mở rộng phạm vi Sprint

Sprint-005B không bao gồm:

- scan lại thư viện;
- thiết kế lại Local Memory Index;
- thay đổi Event Discovery đã hoạt động;
- upload ảnh;
- đồng bộ cloud;
- login;
- API backend;
- tạo Album hoàn chỉnh;
- layout Album;
- chỉnh màu;
- crop;
- retouch;
- nhận diện người dùng cụ thể;
- học sở thích cá nhân;
- huấn luyện model;
- đồng bộ lựa chọn giữa nhiều thiết bị.

---

# 35. Liên kết với Sprint-006

Sprint-005B tạo đầu vào cho Sprint-006.

Đầu ra cần cung cấp tối thiểu:

```text
eventCandidateID

orderedGroupIDs

orderedSelectedAssetIdentifiers

selectedAssetCount

sourceAssetCount

userSelectionOverrides
```

Sprint-006 sẽ dùng dữ liệu này để tạo Album Draft.

Sprint-006 không cần chạy lại Photo Curation nếu kết quả hợp lệ đã tồn tại.

---

# 36. Migration và dữ liệu hiện tại

Vì hệ thống đã scan thư viện và có Event Candidate thực tế, việc thêm Sprint-005B phải là thay đổi tăng dần.

Yêu cầu:

- không xoá database hiện tại;
- không reset toàn bộ app data;
- không xoá kết quả Event Discovery;
- không yêu cầu scan lại để migration;
- thêm model hoặc field mới theo cách tương thích;
- các Event Candidate cũ mặc định có curation status là `notStarted`;
- chỉ tạo curation result khi người dùng mở từng Event Candidate.

Ví dụ sau migration:

```text
Event Candidate cũ
        ↓
Vẫn hiển thị trong Candidate List
        ↓
curationStatus = notStarted
        ↓
Người dùng mở
        ↓
Photo Curation chạy riêng cho Event đó
```

---

# 37. Trình tự triển khai

Claude cần triển khai theo thứ tự sau:

## Bước 1

Đọc lại kiến trúc hiện tại:

- Photo Library Scanner;
- Local Memory Index;
- Event Candidate;
- Event Session;
- Candidate Detail;
- persistence layer.

Không code lại scanner.

## Bước 2

Báo cáo rõ:

- asset identifier của Event Candidate hiện được lưu ở đâu;
- session hiện được lưu thế nào;
- Candidate Detail đang lấy ảnh bằng cách nào;
- database hoặc persistence hiện tại hỗ trợ mở rộng ra sao.

## Bước 3

Thêm model và trạng thái cho Photo Curation.

## Bước 4

Tạo service phân tích riêng một Event Candidate.

Ví dụ tên tham khảo:

```text
EventPhotoCurationService
```

Tên cụ thể có thể theo convention của project.

## Bước 5

Tạo grouping, quality scoring và suggestion pipeline.

## Bước 6

Lưu kết quả local.

## Bước 7

Tích hợp UI vào Candidate Detail.

## Bước 8

Kiểm thử với Event Candidate thực tế có vài trăm ảnh.

---

# 38. Acceptance Criteria

Sprint-005B được coi là hoàn thành khi đáp ứng các điều kiện sau.

---

## 38.1 Không scan lại thư viện

Khi mở một Event Candidate:

- Library Scan không chạy lại;
- tổng số ảnh thư viện không được duyệt lại;
- Event Discovery toàn cục không chạy lại;
- chỉ các asset thuộc Event Candidate được phân tích sâu.

---

## 38.2 Kế thừa dữ liệu hiện có

Các Event Candidate đã phát hiện trước đó vẫn tồn tại và mở được.

Không mất:

- Local Memory Index;
- Candidate List;
- session;
- scan status;
- metadata đã lưu.

---

## 38.3 Phân nhóm

Một Event Candidate có nhiều ảnh gần nhau được chia thành các nhóm nhỏ hợp lý.

Các loạt ảnh chụp liên tiếp không bị trình bày như những ảnh hoàn toàn độc lập.

---

## 38.4 Lựa chọn ảnh

Với Event Candidate khoảng 200–300 ảnh:

- Nizi tạo được lựa chọn đề xuất;
- số ảnh thường nằm trong khoảng 20–40 khi nội dung phù hợp;
- không chọn quá nhiều ảnh gần trùng;
- ảnh rõ nét hơn được ưu tiên;
- ảnh có khuôn mặt tốt hơn được ưu tiên khi phù hợp.

---

## 38.5 UI

Người dùng nhìn thấy:

- ảnh được chọn có tích xanh;
- ảnh chưa chọn có trạng thái xám và tối nhẹ;
- ảnh được trình bày trong grid vuông;
- các nhóm được ngăn cách rõ;
- tổng số ảnh đã chọn được cập nhật ngay.

---

## 38.6 Quyền người dùng

Người dùng có thể:

- chọn thêm;
- bỏ chọn;
- xem ảnh lớn;
- thay đổi đề xuất;
- đóng và mở lại mà không mất quyết định.

---

## 38.7 Cache

Sau khi một Event Candidate đã hoàn thành curation:

- mở lần sau hiển thị từ local cache;
- không chạy lại toàn bộ pipeline;
- không scan lại thư viện.

---

## 38.8 Chuyển sang Sprint-006

Danh sách ảnh đã chọn được sắp xếp đúng thứ tự và có thể chuyển sang Album Draft.

Sprint-005B không upload ảnh và không tạo Album hoàn chỉnh.

---

# 39. Definition of Done

Sprint-005B chỉ được đánh dấu hoàn thành khi Claude chứng minh được:

1. Không có full-library rescan.
2. Event Candidate hiện có được giữ nguyên.
3. Photo Curation chỉ xử lý asset của một Event.
4. Kết quả được cache local.
5. Các ảnh gần giống nhau được nhóm.
6. Nizi tự đề xuất ảnh.
7. Người dùng có thể thay đổi lựa chọn.
8. Các thay đổi của người dùng không bị ghi đè khi mở lại.
9. UI vẫn phản hồi tốt với Event khoảng 200–300 ảnh.
10. Dữ liệu đầu ra sẵn sàng cho Sprint-006 Album Draft.