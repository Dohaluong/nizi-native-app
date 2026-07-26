

# SPEC - Nhiệm vụ sửa Photo Draft Preview

## 1. Mục tiêu

Cập nhật màn hình `AlbumDraftPlanningPreview` để:

* các Spread có tổng số ảnh thay đổi từ **2 đến 6 ảnh**;
* cách phân phối giữa hai trang đa dạng;
* layout không lặp liên tục;
* ảnh mock có tỷ lệ ngang, dọc và vuông khác nhau;
* mỗi lần mở Preview có thể hiển thị một mẫu album đa dạng;
* vẫn có chế độ seed cố định để debug và test.

Ví dụ album preview:

```text
Spread 1: 2 ảnh
Page 1: 1 ảnh
Page 2: 1 ảnh

Spread 2: 5 ảnh
Page 3: 2 ảnh
Page 4: 3 ảnh

Spread 3: 4 ảnh
Page 5: 1 ảnh
Page 6: 3 ảnh

Spread 4: 6 ảnh
Page 7: 4 ảnh
Page 8: 2 ảnh

Spread 5: 3 ảnh
Page 9: 1 ảnh
Page 10: 2 ảnh
```

Không được mặc định thành:

```text
3 + 3
3 + 3
3 + 3
```

---

# 2. Không sửa Planner thành random

Planner production phải giữ nguyên nguyên tắc:

```text
cùng input
+ cùng layout library
= cùng kết quả
```

Không thêm:

```swift
.randomElement()
Int.random(...)
shuffled()
```

vào:

* `AlbumDraftPlanner`
* `AlbumSpreadBuilder`
* `AlbumLayoutPairSelector`
* `AlbumPhotoSlotAssigner`

Sự đa dạng của Album thật phải đến từ:

* số ảnh thực tế trong từng nhóm;
* orientation thực tế;
* số lượng layout trong library;
* variety penalty;
* cách chia Event thành Spread.

Random chỉ được dùng trong:

```text
Preview
Diagnostics
Mock data factory
```

---

# 3. Tạo Mock Album Factory riêng

Tạo file:

```text
Features/AlbumCreation/Preview/
└── AlbumDraftPreviewFactory.swift
```

Hoặc đặt cùng khu vực Presentation Preview hiện tại.

Định nghĩa:

```swift
struct AlbumDraftPreviewConfiguration {
    let spreadCount: Int
    let minimumPhotosPerSpread: Int
    let maximumPhotosPerSpread: Int
    let seed: UInt64?
}
```

Giá trị mặc định:

```swift
static let varied = AlbumDraftPreviewConfiguration(
    spreadCount: 8,
    minimumPhotosPerSpread: 2,
    maximumPhotosPerSpread: 6,
    seed: nil
)
```

Factory:

```swift
protocol AlbumDraftPreviewBuilding {
    func makeInput(
        configuration: AlbumDraftPreviewConfiguration
    ) -> AlbumPlanningInput
}
```

---

# 4. Sinh số ảnh đa dạng theo Spread

Preview phải sinh tổng ảnh cho từng Spread trong khoảng:

```text
2...6
```

Không random hoàn toàn độc lập vì có thể tạo chuỗi nhàm chán như:

```text
6, 6, 6, 6
```

Dùng một danh sách phân phối cân bằng:

```swift
let spreadPhotoCounts = [2, 5, 4, 6, 3, 5, 2, 6]
```

Sau đó shuffle bằng seeded generator khi cần.

Hoặc dùng một bag:

```swift
var countBag = [2, 3, 4, 5, 6]
```

Quy tắc:

1. Lấy lần lượt từ bag.
2. Khi bag hết thì tạo lại.
3. Có thể shuffle bag.
4. Không để hai Spread liên tiếp cùng số ảnh nếu có lựa chọn khác.

Pseudo-code:

```swift
func makeSpreadPhotoCounts(
    count: Int,
    using generator: inout some RandomNumberGenerator
) -> [Int] {
    var result: [Int] = []
    var bag = [2, 3, 4, 5, 6]

    while result.count < count {
        bag.shuffle(using: &generator)

        for value in bag {
            guard result.count < count else { break }

            if result.last == value {
                continue
            }

            result.append(value)
        }
    }

    return result
}
```

---

# 5. Dữ liệu mock phải tạo được đúng Spread mong muốn

Nếu Preview chỉ đưa tất cả ảnh vào một Event, Planner có thể tự chia lại theo cách cân bằng của nó.

Để chủ động tạo các Spread 2–6 ảnh, mỗi cụm mock nên là một Event riêng:

```text
Event 1: 2 ảnh
Event 2: 5 ảnh
Event 3: 4 ảnh
Event 4: 6 ảnh
Event 5: 3 ảnh
```

Do mỗi Event đã có từ 2 đến 6 ảnh, Planner sẽ ưu tiên giữ mỗi Event trong một Spread.

Ví dụ:

```swift
AlbumPlanningEvent(
    id: "preview-event-1",
    title: "Morning Walk",
    selectedPhotos: makePhotos(count: 2, ...)
)
```

Không tạo Event một ảnh trong màn hình preview đa dạng chính, trừ case riêng để test singleton merge.

---

# 6. Sinh orientation đa dạng

Mỗi Spread phải có tổ hợp orientation khác nhau.

Ví dụ:

```text
2 ảnh:
1 landscape
1 portrait
```

```text
3 ảnh:
2 portrait
1 square
```

```text
4 ảnh:
2 landscape
1 portrait
1 square
```

```text
5 ảnh:
3 landscape
2 portrait
```

```text
6 ảnh:
2 landscape
3 portrait
1 square
```

Tạo orientation bag:

```swift
let orientationPatterns: [Int: [[PhotoOrientation]]] = [
    2: [
        [.landscape, .portrait],
        [.square, .landscape],
        [.portrait, .portrait]
    ],

    3: [
        [.landscape, .portrait, .square],
        [.portrait, .portrait, .landscape],
        [.landscape, .landscape, .square]
    ],

    4: [
        [.landscape, .landscape, .portrait, .square],
        [.portrait, .portrait, .landscape, .square],
        [.landscape, .portrait, .portrait, .landscape]
    ],

    5: [
        [.landscape, .landscape, .portrait, .portrait, .square],
        [.portrait, .portrait, .portrait, .landscape, .square],
        [.landscape, .landscape, .landscape, .portrait, .portrait]
    ],

    6: [
        [.landscape, .landscape, .portrait, .portrait, .portrait, .square],
        [.landscape, .landscape, .landscape, .portrait, .portrait, .square],
        [.portrait, .portrait, .portrait, .landscape, .landscape, .square]
    ]
]
```

Preview chọn pattern khác nhau giữa các Spread.

---

# 7. Kích thước mock phải đúng orientation

Không chỉ set enum giả. `pixelWidth` và `pixelHeight` phải tạo đúng.

```swift
func dimensions(
    for orientation: PhotoOrientation,
    index: Int
) -> (width: Int, height: Int) {
    switch orientation {
    case .landscape:
        return index.isMultiple(of: 2)
            ? (4032, 3024)
            : (3840, 2160)

    case .portrait:
        return index.isMultiple(of: 2)
            ? (3024, 4032)
            : (2160, 3840)

    case .square:
        return (3024, 3024)
    }
}
```

Như vậy Planner thực sự phân tích orientation từ dimensions, không phải dựa trên dữ liệu giả không nhất quán.

---

# 8. Đa dạng partition giữa hai trang

Planner hiện ưu tiên cân bằng, vì vậy:

```text
4 ảnh → thường 2 + 2
6 ảnh → thường 3 + 3
```

Điều này đúng về thuật toán, nhưng dễ tạo preview đều đều.

Để đa dạng hơn, cần điều chỉnh **variety scoring**, không random.

Bổ sung hoặc tăng penalty cho pattern phân trang lặp lại:

```text
partition giống Spread trước: -8
layout count pattern giống Spread trước: -8
cặp layout giống Spread trước: -10
layout đơn lẻ giống Page trước: -5
```

Ví dụ:

```text
Spread trước: 3 + 3
Spread hiện tại:
3 + 3 có score 580
2 + 4 có score 576
```

Sau variety penalty:

```text
3 + 3 → 572
2 + 4 → 576
```

Planner chọn `2 + 4`.

Nhưng chỉ cho phép variety thắng khi chênh lệch chất lượng nhỏ.

## Quy tắc giới hạn

Không chọn phương án orientation kém rõ rệt chỉ để khác layout.

Đề xuất:

```swift
let varietyTolerance = 12.0
```

Nếu candidate tốt nhất về orientation cao hơn phương án đa dạng trên 12 điểm, giữ candidate tốt nhất.

Có thể thực hiện theo hai bước:

```text
1. Tìm base best score.
2. Giữ các candidate có score nằm trong baseBest - tolerance.
3. Trong nhóm gần tương đương, chọn candidate ít lặp hơn.
```

Cách này tốt hơn cộng penalty quá mạnh vào tổng score.

---

# 9. Theo dõi lịch sử partition

Mở rộng planning context:

```swift
struct AlbumLayoutPlanningContext {
    let previousLeftLayoutId: String?
    let previousRightLayoutId: String?
    let previousPartition: AlbumPagePartition?
    let recentlyUsedLayoutIds: [String]
}
```

Không cần lưu vào domain Album nếu chỉ dùng trong quá trình plan.

Khi chọn Spread tiếp theo, truyền context của Spread trước.

Variety score xét:

* partition trước;
* layout bên trái trước;
* layout bên phải trước;
* layout xuất hiện trong 2–3 Page gần nhất.

---

# 10. Layout Library phải đủ layout cho 1–4 ảnh mỗi trang

Theo báo cáo hiện tại library có 12 layout:

```text
1 ảnh: 2 layout
2 ảnh: 4 layout
3 ảnh: 3 layout
4 ảnh: 3 layout
```

Đủ để chạy version đầu, nhưng cần kiểm tra `preferredOrientation` có thực sự khác nhau.

Nếu nhiều layout chỉ khác tọa độ nhưng cùng orientation signature, Planner vẫn coi chúng gần như giống nhau.

Mỗi layout nên có signature rõ:

```text
1 ảnh:
- full landscape/any
- inset portrait/any

2 ảnh:
- vertical: 2 landscape
- horizontal: 2 portrait
- heroTop: landscape + square
- heroLeft: portrait + square

3 ảnh:
- heroTop: landscape + square + square
- heroLeft: portrait + square + square
- columns: portrait + portrait + portrait

4 ảnh:
- grid: square × 4
- heroTop: landscape + square × 3
- heroLeft: portrait + square × 3
```

Cần rà lại JSON để Planner có lý do chọn khác nhau.

---

# 11. Thay placeholder trống bằng mock ảnh dễ phân biệt

Ngay cả khi chưa có `AlbumPhotoProviding`, placeholder hiện tại không nên chỉ là các ô xám giống nhau.

Mỗi mock photo tile nên hiển thị:

```text
P01
Landscape
Score 78
```

Và có pattern nền khác nhau theo ID.

Có thể dùng SwiftUI thuần:

```swift
ZStack {
    LinearGradient(...)
    Text(photo.shortLabel)
}
```

Nhưng không hardcode màu ngẫu nhiên mỗi lần render.

Tạo style deterministic từ hash của `photoId`.

Ví dụ:

```swift
let styleIndex = abs(photoId.hashValue) % mockStyles.count
```

Lưu ý `hashValue` không ổn định giữa process. Tốt hơn tự tạo stable hash đơn giản từ Unicode scalars.

Hoặc dùng ảnh asset mock có sẵn nếu project đã có.

Mục tiêu là nhìn rõ:

* ảnh nào được lặp;
* ảnh nào vào hero;
* ảnh ngang hay dọc;
* cách crop trong slot;
* layout giữa các Page khác nhau.

---

# 12. Preview controls

Ở đầu màn hình `AlbumDraftPlanningPreview`, thêm một thanh control nhỏ:

```text
[Regenerate] [Seed: 1042] [Show metadata]
```

Yêu cầu:

### Regenerate

* tạo seed mới;
* dựng lại mock input;
* chạy lại Planner;
* chỉ tồn tại trong Preview/Diagnostics.

### Fixed seed

Cho phép dùng các preset:

```text
Seed 1
Seed 2
Seed 3
```

để tái hiện lỗi.

Không cần TextField phức tạp.

Có thể dùng:

```swift
@State private var seed: UInt64 = 1
```

và:

```swift
Button("Regenerate") {
    seed &+= 1
}
```

Seed phải đi vào mock factory.

Planner production vẫn không random.

---

# 13. Tách ba chế độ Preview

Nên có ba section hoặc ba tab:

## A. Varied Album

Dành để xem trải nghiệm thực:

```text
8–12 Spread
mỗi Spread 2–6 ảnh
orientation đa dạng
```

## B. Edge Cases

Giữ ba case cũ:

* 6 ảnh;
* 13 ảnh;
* singleton Event merge.

## C. Layout Library

Hiển thị từng layout riêng để kiểm tra geometry.

Như vậy case kỹ thuật không làm màn hình Album chính bị nhàm chán.

---

# 14. Acceptance criteria

Claude hoàn thành khi:

1. `AlbumDraftPlanningPreview` không còn chỉ hiển thị các trang 3 ảnh.
2. Preview có Spread từ 2 đến 6 ảnh.
3. Có ít nhất một Spread cho mỗi tổng số ảnh `2, 3, 4, 5, 6`.
4. Hai Spread liền nhau không luôn có cùng partition.
5. Có trang 1 ảnh, 2 ảnh, 3 ảnh và 4 ảnh trong cùng album preview.
6. Orientation mock gồm landscape, portrait và square.
7. Pixel dimensions phù hợp orientation.
8. Planner production không dùng random.
9. Random/seed chỉ nằm trong mock factory hoặc Diagnostics.
10. Preview có nút Regenerate.
11. Có seed để tái hiện một kết quả.
12. Layout pair selector có variety context.
13. Partition lặp được xem như một tiêu chí variety.
14. Variety không được làm mất phương án orientation tốt rõ rệt.
15. Không có Page rỗng.
16. Không có Spread dưới 2 hoặc trên 6 ảnh.
17. Không duplicate photo.
18. Placeholder mock dễ phân biệt từng ảnh.
19. Edge-case Preview cũ vẫn còn.
20. Build pass.

---

# 15. Yêu cầu ngắn để giao Claude Code

Có thể gửi trực tiếp đoạn này:

```markdown
## TASK — Diversify Album Draft Preview

The current Album Draft preview is visually repetitive because most spreads resolve to 3+3 photos and every photo is rendered as an identical placeholder.

Update the Preview/Diagnostics experience so that a generated mock album contains varied spreads of 2–6 photos across exactly two pages.

Requirements:

1. Do not add randomness to the production Album Planner. Production planning must remain deterministic.
2. Add an `AlbumDraftPreviewFactory` with a seedable random generator.
3. Generate 8–12 mock Events, where each Event contains 2–6 selected photos so that each Event naturally becomes one Spread.
4. Ensure one preview album contains examples of total spread counts 2, 3, 4, 5 and 6.
5. Generate varied landscape, portrait and square photo dimensions.
6. Add a Regenerate button that changes only the Preview seed.
7. Keep fixed seed support for reproducible debugging.
8. Add variety context to layout-pair selection:
   - previous partition;
   - previous left/right layout IDs;
   - recently used layout IDs.
9. Prefer a different partition/layout when candidates are near-equivalent, but never sacrifice a clearly better orientation match.
10. Use a score tolerance approach rather than uncontrolled random selection.
11. Avoid repeated 3+3 partitions across consecutive spreads when a 2+4 or 4+2 candidate is nearly equivalent.
12. Improve mock photo tiles so each photo is visually distinguishable and shows its ID/orientation.
13. Keep the existing technical edge-case previews separately.
14. Verify that the varied album contains pages with 1, 2, 3 and 4 photos.
15. Run build only; do not run Simulator or tests unless explicitly requested.

Report:
- files created;
- files modified;
- mock generation rules;
- seed behavior;
- variety selection behavior;
- example spread sequence;
- build result.
```

Điểm cốt lõi: **không ép Album thật phải ngẫu nhiên**, mà cho Planner chọn phương án khác nhau trong nhóm các phương án có chất lượng gần tương đương. Như vậy Album vừa tự nhiên, vừa ổn định và có thể tái tạo.
