BỔ SUNG — CÁCH XÂY DỰNG PRESET CHO PHOTO EDITOR

1. Nguyên tắc

Preset không phải chỉ là một LUT đơn lẻ.

Mỗi preset là một cấu hình hoàn chỉnh gồm:

* LUT hoặc công thức màu chính.
* Tone adjustments.
* Cường độ mặc định.
* Grain.
* Bloom hoặc glow.
* Vignette.
* Các giới hạn an toàn cho ảnh chân dung.
* Thông tin hiển thị trong UI.

Preset phải được định nghĩa bên ngoài giao diện để có thể:

* Thay đổi LUT mà không sửa UI.
* Thêm hoặc bỏ preset dễ dàng.
* Thử nghiệm nhiều phiên bản màu.
* Điều chỉnh thông số mà không phải viết lại render engine.

⸻

2. Cấu trúc preset

Tạo model:

struct PresetDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let shortName: String
    let lutResource: String?
    let lutDimension: Int?
    let defaultIntensity: Float
    let exposureOffset: Float
    let contrastOffset: Float
    let saturationOffset: Float
    let warmthOffset: Float
    let highlightsOffset: Float
    let shadowsOffset: Float
    let grainAmount: Float
    let grainSize: Float
    let bloomAmount: Float
    let bloomRadius: Float
    let vignetteAmount: Float
    let vignetteRadius: Float
    let protectSkinTones: Bool
    let isMonochrome: Bool
    let thumbnailAssetName: String?
    let sortOrder: Int
    let isActive: Bool
}

Không bắt buộc mọi preset phải dùng tất cả thông số.

Ví dụ preset nhẹ có thể chỉ dùng LUT và contrast.

Preset film có thể thêm grain và vignette.

⸻

3. Nguồn tạo preset

Có ba cách tạo preset.

3.1. LUT có sẵn

Có thể sử dụng LUT .cube đã mua hoặc được cấp phép hợp lệ.

Quy trình:

File .cube
→ Parse LUT
→ Chuyển thành CIColorCube data
→ Áp bằng CIColorCube hoặc CIColorCubeWithColorSpace

Cần kiểm tra:

* LUT dành cho ảnh thường, không phải LUT Log video.
* LUT phù hợp với sRGB hoặc Display P3.
* Có quyền sử dụng trong ứng dụng thương mại.
* Không dùng LUT không rõ giấy phép.

3.2. Tự tạo LUT bằng công cụ chỉnh ảnh

Có thể tạo preset bằng:

* Adobe Lightroom.
* Adobe Photoshop.
* DaVinci Resolve.
* Affinity Photo.
* Công cụ tạo LUT chuyên dụng.

Quy trình đề xuất:

Chọn ảnh mẫu
→ Chỉnh màu bằng công cụ chuyên nghiệp
→ Xuất LUT .cube
→ Đưa LUT vào app bundle
→ Tinh chỉnh thêm grain, bloom, vignette trong app

LUT chỉ nên chứa phần màu và tone chính.

Không cố đưa grain, bloom hoặc vignette vào LUT vì LUT không thể mô tả tốt các hiệu ứng texture và spatial effect.

3.3. Preset không dùng LUT

Một số preset có thể được xây hoàn toàn bằng Core Image:

* Exposure.
* Contrast.
* Saturation.
* Temperature.
* Tone curve.
* Monochrome.
* Sepia.
* Highlight/shadow.

Cách này phù hợp để:

* Tạo preset thử nghiệm ban đầu.
* Xây bản V1 trước khi có LUT chính thức.
* Kiểm tra toàn bộ pipeline.

Tuy nhiên, màu sắc cuối cùng của Nizi nên chuyển sang LUT hoặc một pipeline màu được tinh chỉnh kỹ.

⸻

4. File cấu hình preset

Tạo file:

Resources/Presets/presets.json

Ví dụ:

[
  {
    "id": "original",
    "name": "Ảnh gốc",
    "shortName": "Gốc",
    "lutResource": null,
    "lutDimension": null,
    "defaultIntensity": 0,
    "exposureOffset": 0,
    "contrastOffset": 0,
    "saturationOffset": 0,
    "warmthOffset": 0,
    "highlightsOffset": 0,
    "shadowsOffset": 0,
    "grainAmount": 0,
    "grainSize": 0,
    "bloomAmount": 0,
    "bloomRadius": 0,
    "vignetteAmount": 0,
    "vignetteRadius": 0,
    "protectSkinTones": false,
    "isMonochrome": false,
    "thumbnailAssetName": null,
    "sortOrder": 0,
    "isActive": true
  },
  {
    "id": "warm-memory",
    "name": "Ký ức ấm",
    "shortName": "Ký ức",
    "lutResource": "warm-memory.cube",
    "lutDimension": 33,
    "defaultIntensity": 0.65,
    "exposureOffset": 0,
    "contrastOffset": -0.03,
    "saturationOffset": -0.04,
    "warmthOffset": 0.08,
    "highlightsOffset": -0.08,
    "shadowsOffset": 0.05,
    "grainAmount": 0.12,
    "grainSize": 0.7,
    "bloomAmount": 0.05,
    "bloomRadius": 6,
    "vignetteAmount": 0.08,
    "vignetteRadius": 1.2,
    "protectSkinTones": true,
    "isMonochrome": false,
    "thumbnailAssetName": null,
    "sortOrder": 1,
    "isActive": true
  }
]

Claude không được hard-code toàn bộ preset trực tiếp trong SwiftUI.

Preset phải được load qua PresetRepository.

⸻

5. Cấu trúc resource

Resources/
└── Presets/
    ├── presets.json
    ├── warm-memory.cube
    ├── summer.cube
    ├── soft.cube
    ├── film.cube
    ├── cinematic.cube
    ├── night.cube
    └── monochrome.cube

Nếu chưa có LUT chính thức, tạo các preset prototype bằng Core Image và đánh dấu:

prototypePreset = true

Không dùng LUT giả hoặc tải LUT không rõ nguồn chỉ để hoàn tất code.

⸻

6. Preset Repository

Tạo abstraction:

protocol PresetRepository {
    func loadPresets() throws -> [PresetDefinition]
    func preset(id: String) -> PresetDefinition?
}

Implementation:

final class BundlePresetRepository: PresetRepository {
    private var presets: [PresetDefinition] = []
    func loadPresets() throws -> [PresetDefinition] {
        // Load presets.json from app bundle
        // Decode
        // Validate
        // Sort by sortOrder
        // Cache
    }
    func preset(id: String) -> PresetDefinition? {
        presets.first { $0.id == id }
    }
}

Validation tối thiểu:

* ID không trùng.
* Intensity nằm trong 0...1.
* LUT resource tồn tại.
* LUT dimension hợp lệ.
* Giá trị effect nằm trong phạm vi cho phép.
* Original phải tồn tại.
* Original phải có intensity bằng 0.

Nếu một preset lỗi:

* Không làm crash app.
* Ghi log.
* Bỏ qua preset lỗi.
* Original vẫn phải sử dụng được.

⸻

7. LUT Loader

Tạo:

protocol LUTLoading {
    func loadCube(
        resourceName: String,
        dimension: Int
    ) throws -> LUTCube
}

LUTCube có thể chứa:

struct LUTCube {
    let dimension: Int
    let data: Data
    let colorSpace: CGColorSpace
}

LUT loader chịu trách nhiệm:

* Đọc file .cube.
* Bỏ qua comment.
* Đọc LUT_3D_SIZE.
* Đọc các giá trị RGB.
* Validate số lượng điểm.
* Chuyển Float thành Data phù hợp với Core Image.
* Cache LUT đã parse.

Không parse lại file LUT mỗi lần kéo slider.

⸻

8. Render một preset

Pipeline preset:

Input image
→ Preset base tone adjustments
→ LUT
→ Preset texture effects
→ Blend với input theo intensity

Tuy nhiên để có kết quả đẹp hơn, nên tách thành hai nhóm.

8.1. Color style

Gồm:

* LUT.
* Tone.
* Contrast.
* Warmth.
* Saturation.
* Highlight/shadow.

Phần này được blend trực tiếp với ảnh đầu vào theo intensity.

8.2. Texture style

Gồm:

* Grain.
* Bloom.
* Vignette.

Texture không nhất thiết giảm tuyến tính giống phần màu.

Ví dụ:

let colorIntensity = userIntensity
let grainIntensity = min(
    preset.grainAmount * (0.4 + userIntensity * 0.6),
    preset.grainAmount
)
let bloomIntensity = preset.bloomAmount * userIntensity
let vignetteIntensity = preset.vignetteAmount * userIntensity

Người dùng vẫn chỉ thấy một slider.

Các hệ số nội bộ thuộc định nghĩa preset.

⸻

9. Preset Renderer

Tạo:

protocol PresetRendering {
    func applyPreset(
        _ preset: PresetDefinition,
        intensity: Float,
        to input: CIImage
    ) throws -> CIImage
}

Pseudo flow:

func applyPreset(
    _ preset: PresetDefinition,
    intensity: Float,
    to input: CIImage
) throws -> CIImage {
    guard preset.id != "original", intensity > 0 else {
        return input
    }
    var styled = input
    styled = applyBaseTone(
        preset: preset,
        to: styled
    )
    if let lutResource = preset.lutResource {
        styled = applyLUT(
            resource: lutResource,
            dimension: preset.lutDimension,
            to: styled
        )
    }
    let colorBlended = blend(
        original: input,
        styled: styled,
        intensity: intensity
    )
    return applyTexture(
        preset: preset,
        intensity: intensity,
        to: colorBlended
    )
}

⸻

10. Intensity 0–100%

UI dùng:

0...100

Engine dùng:

0...1

Chuyển đổi:

let normalizedIntensity = Float(uiValue) / 100

Quy tắc:

* 0: hoàn toàn Original.
* 1: toàn bộ phần màu của preset.
* Texture được tính theo hệ số riêng.
* Không render lại LUT resource từ đầu khi intensity thay đổi.
* Chỉ thay đổi bước blend và texture strength.

⸻

11. Preset thumbnail

Thumbnail không phải asset cố định nếu có thể tránh.

Khi mở editor:

Ảnh hiện tại
→ Resize nhỏ
→ Render từng preset ở default intensity
→ Hiển thị thumbnail
→ Cache trong PhotoEditSession

Lợi ích:

* Người dùng thấy chính ảnh của họ dưới từng preset.
* Không cần chuẩn bị thumbnail riêng.
* Kết quả phản ánh đúng ảnh đang chỉnh.

Yêu cầu:

* Thumbnail khoảng 100–160 px tùy màn hình.
* Render dưới 10 preset.
* Chạy background task.
* Cache theo photoId + presetId.
* Hủy task khi editor đóng.

⸻

12. Bộ preset V1

V1 nên giới hạn 7 hoặc 8 lựa chọn:

1. Original.
2. Ký ức ấm.
3. Mùa hè.
4. Dịu nhẹ.
5. Film.
6. Điện ảnh.
7. Đêm phố.
8. Đen trắng.

Không tạo nhiều preset gần giống nhau.

Mỗi preset phải có mục đích rõ:

Original

Không chỉnh màu.

Ký ức ấm

* Ấm nhẹ.
* Saturation giảm nhẹ.
* Highlight mềm.
* Grain nhẹ.
* Phù hợp ảnh gia đình và kỷ niệm.

Mùa hè

* Sáng hơn.
* Màu xanh và vàng rõ hơn.
* Da người vẫn tự nhiên.
* Phù hợp ảnh ngoài trời và du lịch.

Dịu nhẹ

* Contrast thấp.
* Highlight mềm.
* Saturation nhẹ.
* Phù hợp ảnh trẻ em, trong nhà, chân dung.

Film

* Tone film rõ hơn.
* Black point hơi nâng.
* Grain rõ hơn.
* Màu không quá bão hòa.

Điện ảnh

* Contrast cao vừa phải.
* Highlight lạnh hơn.
* Shadow ấm hoặc hơi xanh tùy LUT.
* Cường độ mặc định thấp hơn các preset khác.

Đêm phố

* Bảo vệ highlight.
* Nâng shadow vừa phải.
* Giữ màu đèn.
* Không làm noise quá mạnh.

Đen trắng

* Monochrome.
* Contrast và grain riêng.
* Có thể không cần LUT màu.

⸻

13. Quy trình tạo preset chính thức

Claude chỉ xây engine và preset prototype.

Bộ màu chính thức cần một quy trình riêng:

Bước 1 — Chọn bộ ảnh test

Tối thiểu gồm:

* Chân dung ngoài trời.
* Chân dung trong nhà.
* Ảnh trẻ em.
* Ảnh phong cảnh.
* Ảnh biển.
* Ảnh cây xanh.
* Ảnh hoàng hôn.
* Ảnh đêm.
* Ảnh thiếu sáng.
* Ảnh HDR.
* Ảnh có nhiều màu da.
* Ảnh từ nhiều đời iPhone.

Khoảng 50–100 ảnh test là đủ cho vòng đầu.

Bước 2 — Tạo màu tham chiếu

Chỉnh ảnh trong Lightroom hoặc công cụ tương đương.

Mỗi preset cần:

* Một mục tiêu cảm xúc.
* Một nhóm ảnh phù hợp.
* Một nhóm ảnh không phù hợp.
* Cường độ mặc định.
* Giới hạn saturation và skin tone.

Bước 3 — Xuất LUT

Xuất .cube, ưu tiên LUT 3D size 33.

Nếu chất lượng hoặc hiệu năng không phù hợp, có thể thử size 17 hoặc 64.

Bước 4 — Đưa vào app

* Thay LUT prototype.
* Không thay ID preset.
* So sánh trước và sau.
* Kiểm tra thumbnail.
* Kiểm tra ảnh full resolution.

Bước 5 — Tinh chỉnh effect phụ

Sau LUT mới tinh chỉnh:

* Grain.
* Bloom.
* Vignette.
* Default intensity.

Bước 6 — Test trên thiết bị thật

Kiểm tra:

* Màn hình iPhone.
* Ảnh sRGB.
* Ảnh Display P3.
* Ảnh HDR nếu app hỗ trợ.
* Preview và export phải gần giống nhau.

⸻

14. Yêu cầu cho Claude

Khi triển khai Preset Sprint, Claude phải:

1. Tạo toàn bộ kiến trúc preset có thể thay LUT.
2. Tạo presets.json.
3. Tạo PresetRepository.
4. Tạo .cube parser hoặc sử dụng parser nội bộ đơn giản, không phụ thuộc package lớn nếu không cần.
5. Cache LUT sau khi parse.
6. Tạo Preset Renderer dùng Core Image.
7. Tạo intensity blend 0–100%.
8. Tạo thumbnail động từ ảnh đang chỉnh.
9. Tạo các preset prototype bằng Core Image nếu chưa có LUT chính thức.
10. Gắn nhãn rõ trong code và tài liệu:

Prototype presets — cần thay bằng LUT chính thức.

11. Không tự tải LUT trên Internet.
12. Không nhúng LUT không rõ giấy phép.
13. Không dành quá nhiều thời gian cố mô phỏng Kodak, Fuji hoặc thương hiệu film cụ thể.
14. Không dùng tên preset có thể gây hiểu nhầm về thương hiệu.
15. Viết tài liệu:

docs/modules/PHOTO-EDITOR-PRESET-GUIDE.md

Tài liệu phải mô tả:

* Cách thêm preset mới.
* Cách thay file LUT.
* Cách chỉnh default intensity.
* Cách chỉnh grain, bloom và vignette.
* Cách kiểm thử LUT.
* Cách vô hiệu hóa preset.
* Các giới hạn color space.

⸻

15. Tiêu chí hoàn thành Preset Sprint

Preset Sprint hoàn thành khi:

* Preset được load từ JSON.
* Có preset Original.
* Có ít nhất ba preset prototype hoạt động.
* Có thể thay LUT mà không sửa UI.
* Intensity chạy từ 0–100%.
* Thumbnail dùng chính ảnh hiện tại.
* LUT chỉ parse một lần.
* Render preview không block UI.
* Preset lỗi không làm crash app.
* Có tài liệu hướng dẫn thêm và thay preset.
* Có ghi chú rõ preset hiện tại là prototype hay chính thức.