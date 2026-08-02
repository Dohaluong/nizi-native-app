# DESIGN BRIEF — NIZI HOME

## 1. Nhiệm vụ

Hãy đề xuất thiết kế lại hoàn toàn màn Home của Nizi.

Đây là DESIGN TASK.

Trước tiên:
- khảo sát code/UI Home hiện tại;
- hiểu các data source hiện có;
- sau đó đề xuất concept.

KHÔNG mặc định phải giữ layout Home hiện tại.

Tôi muốn tìm một ý tưởng có thể tạo ra bản sắc riêng cho Nizi, không đơn thuần là một màn photo gallery.

Có thể mạnh dạn thay đổi:
- hierarchy;
- navigation;
- card;
- typography;
- cách ảnh xuất hiện;
- interaction;
- animation;
- cách kể chuyện.

Nhưng không được đề xuất tính năng backend/AI không tồn tại chỉ để làm mockup đẹp.

---

# 2. Nizi là gì?

Nizi là một ứng dụng giúp người dùng quay lại với những bức ảnh đã bị quên trong Photo Library.

Một user có thể có:

100.000+ photos
↓
Nizi scan local Photo Library
↓
phân tích metadata
↓
chia ảnh thành Events
↓
chọn Highlights
↓
user hoặc Nizi xác định những Event đáng nhớ
↓
Memories
↓
có thể tạo Album / Photobook / Digital Artifact

Nizi không muốn trở thành:

> một ứng dụng quản lý ảnh khác.

Giá trị chính là:

> Biến một thư viện ảnh khổng lồ thành những khoảnh khắc con người muốn xem lại.

---

# 3. Product principle của Home

Home KHÔNG phải nơi quản lý dữ liệu.

Home phải trả lời:

> Hôm nay Nizi có gì khiến tôi muốn nhìn lại?

User mở app mà không cần biết mình đang tìm ảnh nào.

Home nên tạo cảm giác:

> "Ồ, mình đã quên mất chuyện này."

Đây là màn cảm xúc nhất của app.

---

# 4. Event và Memory

## Event

Event là những sự kiện Nizi tự phát hiện từ Photo Library.

Ví dụ:

12–14 Jul 2024
Đà Nẵng
187 photos

Event mang tính tổ chức/archive.

Có thể có hàng nghìn Event.

---

## Memory

Hiện tại chúng tôi đang đơn giản hóa:

> Memory về cơ bản vẫn là một Event đáng nhớ.

Một Event có thể trở thành Memory khi:

1. user bấm ♥;
2. sau này Nizi tự đánh giá Event đủ đáng nhớ.

Không cần coi Memory là một content entity hoàn toàn khác Event trong UI.

Memory là:

> một Event đã được trao thêm ý nghĩa.

---

# 5. Loved Events

Event List hiện đã có:

♡ / ♥

User tap:

♡ → ♥

Love được persist.

Loved Event sẽ xuất hiện trên Home trong phần:

"Kỷ niệm"

Nếu user bỏ ♥:

Event vẫn tồn tại,
nhưng không còn nằm trong Loved Memories.

Home hiện có thể lấy trực tiếp:

PhotoEvent
WHERE isLoved == true

sort theo event date DESC.

---

# 6. Event data hiện có

Một Event có thể cung cấp:

- cover photo;
- start date;
- end date;
- photo count;
- Favorite count;
- selected/highlight photos;
- Love state;
- GPS metadata;
- Event duration.

Location enrichment đang được xây.

Mục tiêu display location:

Việt Nam:

Phường/Xã - Thành phố

Ví dụ:

Mỹ An - Đà Nẵng

Nước ngoài:

Thành phố - Quốc gia

Ví dụ:

Tokyo - Nhật Bản

Không cần POI/address chi tiết.

---

# 7. Event Highlights

Nizi có Curation Engine để tự chọn Highlights từ Event.

Ví dụ:

500 source photos
↓
Nizi chọn khoảng vài chục Highlights
↓
user có thể chỉnh lại

Curation đang được cải tiến để:

- bỏ screenshot/document;
- loại ảnh quá xấu;
- giảm near duplicates;
- giảm ảnh cùng khoảnh khắc;
- ưu tiên Favorite;
- giữ temporal diversity.

Do đó Home KHÔNG nhất thiết chỉ có một cover image.

Có thể sử dụng:

- 1 hero photo;
- collage;
- sequence;
- mosaic;
- slideshow;
- cinematic transition;
- hoặc ý tưởng khác.

Hãy tự đề xuất.

---

# 8. First Experience

Lần đầu user dùng Nizi:

Photo Library
↓
scan/index
↓
Event Discovery
↓
Nizi tìm một Memory đủ tốt
↓
First Memory

Mục tiêu:

User phải thấy giá trị của Nizi càng sớm càng tốt.

Sau onboarding, Home trở thành nơi tiếp tục trải nghiệm này.

Thiết kế Home nên có continuity với cảm giác:

> Nizi đang tìm lại ký ức cho tôi.

---

# 9. Initial Scan Journey

Initial scan có thể lâu với thư viện:

100.000+ photos.

Trong quá trình scan, UI có thể biết:

- đang scan đến năm nào;
- số ảnh đã index;
- số Event đã tìm thấy;
- Favorite photos đã gặp;
- một số ảnh cũ đang xuất hiện dần.

Chúng tôi muốn biến scan thành:

> một chuyến quay ngược thời gian,

thay vì progress screen kỹ thuật.

Sau khi initial scan hoàn tất, Home trở thành trải nghiệm chính.

Không cần redesign Initial Scan trong task này,
nhưng Home nên có cùng visual language.

---

# 10. Existing Event Library

Nizi có màn Events riêng.

Events có:

- year filter;
- Event cards;
- date;
- location khi available;
- photo count;
- ♡ / ♥;
- Event Detail.

Home KHÔNG được trở thành một bản copy của Events.

Nếu Home chỉ là:

"Recent Events"

thì thiết kế thất bại.

Events = archive/browser.

Home = discovery/emotion.

---

# 11. Home cần hỗ trợ những loại nội dung nào?

Không bắt buộc tất cả phải xuất hiện cùng lúc.

Có thể sử dụng những content type sau.

### A. Loved Memories

Những Event user đã ♥.

Ví dụ:

Mùa hè ở Đà Nẵng
July 2024

---

### B. Rediscovery

Một Event cũ Nizi đưa trở lại.

Ví dụ:

"8 năm trước"

"Bạn có nhớ mùa hè này?"

"Ngày này năm 2019"

Không cần implement scoring trong design task.

Chỉ cần thiết kế presentation có thể support concept này.

---

### C. Recent Event

Event mới được phát hiện.

Ví dụ:

"Cuối tuần vừa rồi"

Có thể cho user:

♥
Xem lại

Nhưng Recent không được chiếm toàn bộ Home.

---

### D. Trips

Nizi đã có Trip Discovery.

Một Trip có thể gồm nhiều Event.

Ví dụ:

Nhật Bản
Tokyo · Kyoto · Osaka
7 ngày

Trip chưa cần trở thành phần bắt buộc của Home V1.

Nhưng design nên nghĩ xem nó có thể xuất hiện thế nào trong tương lai.

---

### E. Create Artifact

Từ một Memory/Event user có thể tiến tới:

Album
Photobook
Digital Artifact

Nhưng Home không nên biến thành màn bán Photobook.

Creation là secondary action.

Emotion trước.
Creation sau.

---

# 12. Một số narrative Nizi có thể sử dụng

Không bắt buộc dùng đúng wording.

Ví dụ:

"8 năm trước"

"Một ngày bạn có thể đã quên"

"Mùa hè năm ấy"

"Chuyến đi đầu tiên"

"Tháng 7, 2018"

"Bạn đã ♥ kỷ niệm này"

"156 bức ảnh. Nizi chọn lại 24 khoảnh khắc."

"5 năm trong 12 bức ảnh"

"Những ngày ở Tokyo"

Claude có thể đề xuất copywriting khác.

Tránh cheesy/overly sentimental.

Nizi nên có cảm xúc nhưng vẫn hiện đại và tinh tế.

---

# 13. Home không nên quá nhiều dashboard information

Không ưu tiên:

105,423 photos
1,739 Events
83 Trips
43 Memories

như dashboard analytics.

Các con số này có thể xuất hiện nếu có narrative value,
nhưng không phải mục tiêu chính.

Nizi không phải admin dashboard.

---

# 14. Không cần các module kiểu app quản lý

Tránh Home kiểu:

[ Memories ]
[ Events ]
[ Albums ]
[ Trips ]

hoặc:

Recent
Favorites
Albums
Statistics

Nếu chỉ là collection of shortcuts thì chưa đủ.

Navigation có thể nằm ở Tab Bar hoặc secondary navigation.

Home phải có nội dung thật.

---

# 15. Photography-first

Ảnh phải là vật liệu thiết kế chính.

UI chrome nên hạn chế.

Ưu tiên:

- edge-to-edge photography;
- typography tốt;
- whitespace;
- subtle gradients;
- depth;
- motion;
- transition.

Không phủ quá nhiều button/badge lên ảnh.

---

# 16. Emotional pacing

Không cần nhét nhiều card vào một viewport.

Có thể chấp nhận:

1 Memory chiếm phần lớn màn hình.

Home có thể có rhythm:

large
↓
small
↓
large
↓
sequence

thay vì một grid đều nhau.

Hãy suy nghĩ giống editorial/photo journal hơn là social feed.

---

# 17. Interaction

Hãy đề xuất interaction có giá trị.

Ví dụ có thể cân nhắc:

- swipe qua Highlights;
- tap để vào Memory;
- long press;
- subtle parallax;
- photo reveal;
- transition từ cover → Event Detail;
- animated sequence;
- scroll-driven storytelling.

Không cần animation chỉ để trang trí.

Motion phải phục vụ cảm giác khám phá ký ức.

---

# 18. Love interaction

♥ là hành động quan trọng.

Nhưng không cần đặt một heart button khổng lồ.

Có thể là secondary action tinh tế.

Khi user ♥ một Event:

Event đó trở thành một phần của "Kỷ niệm".

Home phải thể hiện được ý nghĩa này.

---

# 19. Editing

Memory/Event đã được Nizi chọn Highlights.

User có thể vào và:

- xem Highlights;
- xem All Photos;
- thêm ảnh;
- bỏ ảnh.

Không cần đưa editing controls lên Home.

Home chỉ đưa user vào trải nghiệm.

---

# 20. Empty / Early Home

Phải thiết kế cho trường hợp:

User mới dùng app
↓
chưa ♥ Event nào.

Home không được trống chỉ vì:

Loved Memories = 0.

Có thể sử dụng:

- First Memory;
- Nizi rediscovery;
- recent strong Event;
- onboarding prompt;
- suggested Event.

Home phải có nội dung từ những lần đầu tiên.

---

# 21. Mature Home

Sau vài tháng sử dụng:

User có:

- nhiều Events;
- Loved Memories;
- Trips;
- Albums;
- nhiều năm lịch sử.

Home không được trở thành một endless archive.

Nó vẫn phải curate.

Nguyên tắc:

> Home cho tôi một vài thứ đáng xem hôm nay,
> không phải tất cả mọi thứ tôi có.

---

# 22. Local-first constraint

Nizi ưu tiên local-first.

Không thiết kế concept phụ thuộc vào:

- backend feed;
- social graph;
- cloud AI;
- server recommendation;
- online account;
- community content.

Home phải hoạt động tốt từ dữ liệu trên iPhone.

---

# 23. Performance

Ảnh có thể nằm trong iCloud.

Không assume full-resolution image luôn available ngay.

Design phải chịu được:

thumbnail
↓
preview
↓
higher-quality image

progressively.

Không thiết kế interaction yêu cầu hàng chục full-resolution image load cùng lúc.

---

# 24. iPhone first

Design cho native SwiftUI iPhone trước.

Không phải web page được chuyển sang SwiftUI.

Phải tôn trọng:

- safe areas;
- gestures;
- Dynamic Type hợp lý;
- native navigation;
- performance;
- scrolling behavior.

Nhưng không có nghĩa phải giống Apple Photos.

Nizi cần visual identity riêng.

---

# 25. Điều tôi muốn Claude làm

Trước khi code:

## STEP 1 — Audit

Đọc Home hiện tại và các component/data source liên quan.

Báo cáo ngắn:

- Home hiện có gì;
- cái gì reuse được;
- constraint kỹ thuật nào quan trọng.

---

## STEP 2 — Đề xuất 3 concept Home khác nhau

Không chỉ đổi màu/layout.

Ba concept phải khác nhau về PRODUCT EXPERIENCE.

Ví dụ:

### Concept A
Memory Feed

### Concept B
Daily Rediscovery

### Concept C
Editorial Memory Journal

Đây chỉ là ví dụ.

Claude hãy tự đặt concept tốt hơn nếu có.

---

# 26. Với mỗi concept

Mô tả:

### Product idea

Home đang cố làm điều gì?

### First viewport

User mở app thấy gì đầu tiên?

### Scroll behavior

Scroll xuống trải nghiệm thế nào?

### Memory presentation

Một Memory được trình bày thế nào?

### Event relationship

Event mới xuất hiện ở đâu?

### Loved Memory

♥ Memory xuất hiện thế nào?

### Empty state

User chưa có Memory thì sao?

### Mature state

User đã dùng Nizi nhiều năm thì sao?

### Motion

Có animation/transition gì thực sự có ích?

### Technical feasibility

Có phù hợp SwiftUI/local-first hiện tại không?

### Risks

Điểm yếu của concept.

---

# 27. Wireframe

Cho mỗi concept một text wireframe.

Ví dụ format:

┌────────────────────────────┐
│ Nizi                       │
│                            │
│ 8 năm trước                │
│                            │
│                            │
│       HERO PHOTO           │
│                            │
│                            │
│ Đà Nẵng · July 2018        │
│ 24 khoảnh khắc             │
│                        ♥   │
└────────────────────────────┘

Không bị giới hạn bởi wireframe ví dụ này.

---

# 28. Chọn một phương án mạnh nhất

Sau 3 concept:

Claude phải tự chọn:

> Concept nào phù hợp Nizi nhất và tại sao?

Không chọn dựa trên:

"easiest to implement".

Ưu tiên:

1. emotional impact;
2. differentiation;
3. clarity;
4. repeat usage;
5. technical feasibility.

---

# 29. Có thể đề xuất một ý tưởng đột phá

Nếu thấy có cách hoàn toàn khác để làm Home:

hãy đề xuất.

Ví dụ Home không nhất thiết phải là:

vertical feed.

Có thể là:

- một Memory mỗi lần mở;
- timeline sống;
- cinematic memory surface;
- photo journal;
- spatial stack;
- hoặc interaction khác.

Nhưng ý tưởng phải:

- giải quyết đúng product goal;
- khả thi trên iPhone;
- không gimmick;
- không phụ thuộc backend.

---

# 30. Không code trong task này

KHÔNG sửa SwiftUI.

KHÔNG tạo file View mới.

KHÔNG implement animation.

KHÔNG thay navigation.

Chỉ:

AUDIT
↓
PRODUCT/UI CONCEPT
↓
WIREFRAME
↓
RECOMMENDATION

Sau khi chọn concept mới chuyển thành UI sprint.