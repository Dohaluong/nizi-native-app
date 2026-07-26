

## FIX PHOTO VIEWER — HIỂN THỊ ẢNH NGAY VÀ PREFETCH ẢNH KẾ TIẾP

1. Hiện trạng lỗi

Trong màn hình danh sách ảnh, thumbnail đã hiển thị bình thường.

Tuy nhiên, khi người dùng nhấn vào một thumbnail để mở Photo Viewer:

* Màn hình viewer xuất hiện nhưng chưa có ảnh.
* Phải chờ khoảng 3 giây ảnh lớn mới xuất hiện.
* Khi vuốt sang ảnh tiếp theo, lại tiếp tục chờ khoảng 3 giây.
* Trải nghiệm không giống ứng dụng Apple Photos.
* Người dùng có cảm giác ứng dụng bị đứng hoặc tải lại từng ảnh.

Nguyên nhân có thể là viewer đang:

* bỏ qua thumbnail đã có;
* chỉ request ảnh chất lượng cao;
* chờ request hoàn tất mới cập nhật giao diện;
* không nhận hoặc không hiển thị kết quả degraded image;
* không prefetch ảnh trước và ảnh sau;
* tạo request mới chỉ sau khi người dùng đã vuốt sang ảnh khác.

2. Mục tiêu

Photo Viewer phải hoạt động theo mô hình progressive image loading:

Thumbnail hiện có
    ↓
Degraded image từ PhotoKit
    ↓
Final high-quality image

Người dùng không được nhìn thấy màn hình trống trong lúc chờ ảnh chất lượng cao.

Khi nhấn vào thumbnail:

1. Hiển thị ngay thumbnail hiện có, phóng lớn theo chế độ aspect fit.
2. Đồng thời request ảnh từ PhotoKit bằng .opportunistic.
3. Khi PhotoKit trả degraded image, thay thumbnail bằng degraded image.
4. Khi PhotoKit trả final high-quality image, thay degraded image bằng ảnh final.
5. Không chờ ảnh final rồi mới hiển thị viewer.

3. Quy tắc hiển thị khi mở ảnh

Ngay khi người dùng nhấn vào thumbnail:

* truyền thumbnail hiện tại sang Photo Viewer;
* hiển thị thumbnail ngay lập tức;
* giữ đúng tỷ lệ ảnh;
* cho phép thumbnail bị hơi mờ trong thời gian rất ngắn;
* không dùng nền trắng hoặc spinner thay thế ảnh;
* không xóa ảnh đang có khi bắt đầu request mới.

Thumbnail trong viewer chỉ là placeholder có nội dung thật, không phải placeholder màu xám.

Ví dụ dữ liệu truyền vào viewer:

struct PhotoViewerItem: Identifiable {
    let id: String
    let asset: PHAsset
    let initialThumbnail: UIImage?
}

Photo Viewer phải sử dụng initialThumbnail ngay khi màn hình được mở.

4. Request ảnh bằng PhotoKit

Dùng PHCachingImageManager.

Cấu hình request:

let options = PHImageRequestOptions()
options.isSynchronous = false
options.deliveryMode = .opportunistic
options.resizeMode = .fast
options.isNetworkAccessAllowed = true

Request ảnh theo kích thước viewer thực tế:

let targetSize = CGSize(
    width: viewerSize.width * screenScale,
    height: viewerSize.height * screenScale
)

Không dùng PHImageManagerMaximumSize cho thao tác xem ảnh thông thường.

Không request original image data khi chỉ mở viewer.

5. Xử lý callback nhiều lần

Với .opportunistic, PhotoKit có thể gọi callback nhiều lần.

Phải kiểm tra:

let isDegraded =
    info?[PHImageResultIsDegradedKey] as? Bool ?? false

Khi isDegraded == true

Đây là ảnh degraded do PhotoKit trả về.

Yêu cầu:

* hiển thị ngay;
* thay thế thumbnail nếu degraded image có chất lượng tốt hơn;
* không đánh dấu request đã hoàn tất;
* không hủy request;
* tiếp tục chờ ảnh final;
* không tắt trạng thái tải hoàn toàn.

Khi isDegraded == false

Đây là ảnh final chất lượng cao cho targetSize đã yêu cầu.

Yêu cầu:

* thay thế ảnh đang hiển thị;
* đánh dấu request hoàn tất;
* giữ ảnh trong memory cache;
* không tạo request trùng cho cùng asset và cùng target size.

6. Không làm mất ảnh đang hiển thị

Trong toàn bộ quá trình tải, viewer phải luôn giữ ảnh tốt nhất hiện có:

initialThumbnail
→ degradedImage
→ finalImage

Tuyệt đối không được thực hiện kiểu:

ảnh hiện tại
→ nil
→ loading
→ ảnh mới

Khi bắt đầu request chất lượng cao:

* không đặt displayedImage = nil;
* không quay về placeholder;
* không hiện màn hình trắng;
* không thay ảnh bằng spinner.

Chỉ thay ảnh khi callback trả về một ảnh mới hợp lệ.

7. Prefetch ảnh trước và ảnh sau

Đây là nguyên nhân chính khiến mỗi lần vuốt đều phải chờ khoảng 3 giây.

Khi viewer đang hiển thị ảnh tại index hiện tại, phải prefetch ít nhất:

currentIndex - 2
currentIndex - 1
currentIndex
currentIndex + 1
currentIndex + 2

Ưu tiên:

1. ảnh hiện tại;
2. ảnh kế tiếp;
3. ảnh trước đó;
4. ảnh cách hai vị trí.

Khi người dùng đang xem ảnh số 10, ảnh số 11 và 12 phải được request trước khi người dùng vuốt tới.

Có thể dùng:

PHCachingImageManager.startCachingImages(
    for: assets,
    targetSize: targetSize,
    contentMode: .aspectFit,
    options: options
)

Khi current index thay đổi:

* cập nhật vùng prefetch;
* bắt đầu cache vùng mới;
* dừng cache các ảnh quá xa vùng đang xem.

Không dừng cache toàn bộ mỗi lần người dùng vuốt một ảnh.

8. Memory cache cho Viewer

Tạo memory cache cho ảnh đã request:

NSCache<NSString, UIImage>

Cache key phải bao gồm:

asset.localIdentifier
targetWidth
targetHeight

Ví dụ:

\(asset.localIdentifier)-\(Int(width))x\(Int(height))

Trước khi request PhotoKit:

1. kiểm tra final image trong memory cache;
2. nếu có thì hiển thị ngay;
3. nếu chưa có thì dùng initial thumbnail;
4. sau đó mới request PhotoKit.

Không lưu hàng loạt ảnh original hoặc full resolution trong RAM.

Memory cache chỉ giữ ảnh đã resize phù hợp với viewer.

9. Viewer dạng vuốt ngang

Mỗi trang trong viewer phải có trạng thái tải độc lập.

Không dùng duy nhất một biến ảnh chung cho tất cả các trang nếu điều đó khiến ảnh bị reset khi current index thay đổi.

Mỗi item nên có:

struct ViewerPhotoState {
    var thumbnail: UIImage?
    var degradedImage: UIImage?
    var finalImage: UIImage?
    var requestID: PHImageRequestID?
    var isLoadingFromICloud: Bool
    var progress: Double
}

Hoặc xây dựng một image loader riêng theo asset.localIdentifier.

Khi trang xuất hiện:

* hiển thị ảnh tốt nhất đã có;
* request nếu cần;
* không request lại nếu request đang chạy.

Khi trang biến mất:

* không nhất thiết hủy ngay request của ảnh liền trước hoặc liền sau;
* chỉ hủy request của ảnh đã ra xa vùng prefetch;
* tránh hủy rồi tạo lại liên tục khi người dùng vuốt qua lại.

10. Tránh cập nhật nhầm ảnh

Mỗi request phải được gắn với đúng asset.

Trước khi cập nhật UI, kiểm tra:

requestedAssetID == currentAsset.localIdentifier

Không để callback của request cũ gán ảnh vào trang mới.

Phải kiểm tra thêm:

PHImageCancelledKey
PHImageErrorKey

Nếu request bị hủy hoặc asset không còn khớp, bỏ qua callback.

11. Ảnh nằm trên iCloud

Đặt:

options.isNetworkAccessAllowed = true

Và sử dụng:

options.progressHandler

Tuy nhiên:

* progress bar không được thay thế ảnh;
* vẫn giữ thumbnail hoặc degraded image trên màn hình;
* chỉ hiển thị progress bar đè nhẹ lên ảnh;
* delay khoảng 300–500 ms trước khi hiện progress để tránh nhấp nháy;
* progress bar chỉ thể hiện quá trình tải dữ liệu cần thiết từ iCloud.

Trong viewer thông thường, không chủ động tải original asset nếu một ảnh screen-sized đã đủ để hiển thị.

12. Chuyển đổi giữa các cấp chất lượng

Khi thay thumbnail bằng degraded image hoặc final image:

* không dùng animation dài;
* có thể crossfade rất nhẹ khoảng 0.1–0.2 giây;
* không scale lại toàn bộ viewer;
* không làm thay đổi vị trí ảnh;
* không gây nhấp nháy nền.

Nếu ảnh mới cùng asset nhưng chất lượng cao hơn, chỉ cập nhật bitmap đang hiển thị.

13. Luồng mong muốn

Khi nhấn vào thumbnail

0 ms:
Mở viewer và hiển thị ngay thumbnail đã truyền vào.
0–100 ms:
Kiểm tra memory cache.
100–500 ms:
PhotoKit có thể trả degraded image, thay thumbnail.
Sau đó:
PhotoKit trả final image, thay degraded image.

Người dùng phải thấy ảnh ngay từ thời điểm viewer xuất hiện, dù ảnh đầu tiên có thể chưa hoàn toàn sắc nét.

Khi vuốt sang ảnh kế tiếp

Trước khi vuốt:
Ảnh kế tiếp đã được prefetch.
Khi trang kế tiếp xuất hiện:
Hiển thị ngay cached image, degraded image hoặc thumbnail.
Sau đó:
Nâng cấp lên final image nếu cần.

Không được chờ khoảng 3 giây rồi ảnh mới xuất hiện.

14. Yêu cầu nghiệm thu

1. Nhấn thumbnail thì viewer hiển thị ảnh gần như ngay lập tức.
2. Trong lúc chờ ảnh nét hơn, thumbnail vẫn được giữ trên màn hình.
3. Không có màn hình trắng khi mở ảnh.
4. Không có spinner toàn màn hình thay cho ảnh.
5. Callback degraded image được xử lý và hiển thị.
6. Final image tự động thay thế degraded image.
7. Vuốt sang ảnh kế tiếp không phải đợi khoảng 3 giây.
8. Ít nhất hai ảnh trước và hai ảnh sau được prefetch.
9. Vuốt qua lại giữa các ảnh vừa xem phải gần như tức thì.
10. Không request original asset cho viewer thông thường.
11. Không tạo request trùng lặp cho cùng một asset.
12. Không hủy request quá sớm đối với ảnh liền trước và liền sau.
13. Không gán nhầm ảnh khi người dùng vuốt nhanh.
14. Không giữ nhiều ảnh full resolution trong RAM.
15. Ảnh nằm trên iCloud vẫn phải có thumbnail hoặc degraded image hiển thị trong lúc tải.

15. Điều cần kiểm tra trong code hiện tại

Hãy đọc implementation hiện có và xác định cụ thể:

* Viewer có được truyền thumbnail từ grid hay không.
* Có đặt ảnh về nil khi mở viewer hay khi đổi trang không.
* deliveryMode hiện đang là .highQualityFormat hay .opportunistic.
* Code có bỏ qua callback khi PHImageResultIsDegradedKey == true không.
* Viewer có đang request PHImageManagerMaximumSize không.
* Có đang dùng API lấy original image data chỉ để xem ảnh không.
* Có memory cache không.
* Có prefetch ảnh trước và ảnh sau không.
* Request có bị hủy ngay khi trang vừa rời màn hình không.
* Khi vuốt, có tạo lại loader hoặc view model khiến cache bị mất không.
* Có request trùng lặp do SwiftUI body, onAppear hoặc .task chạy nhiều lần không.

Sau khi sửa, hãy báo rõ:

1. Nguyên nhân chính khiến mỗi ảnh phải đợi khoảng 3 giây.
2. Những file đã sửa.
3. Cơ chế hiển thị thumbnail, degraded image và final image.
4. Phạm vi prefetch đang áp dụng.
5. Cách ngăn request trùng lặp.
6. Kết quả test trên iPhone thật.


Show the existing thumbnail immediately, accept the PhotoKit degraded image, then replace it with the final high-quality image. Prefetch adjacent assets before the user swipes to them.