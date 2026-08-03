# Architecture

Cloud Bridge gồm browser React/Vite, API Express headless và `StorageProvider`. `LocalStorageProvider` ghi vào `UPLOAD_STORAGE_PATH`; business logic chỉ gọi interface này nên có thể thêm S3-compatible provider sau này.

`ImportSession` lưu trạng thái, hạn 24 giờ, token QR đã hash và token access native đã hash. Mỗi `ImportAsset` có trạng thái/checksum/storage key riêng. `apps/desktop` và `packages/bridge-core` là LAN Bridge độc lập, không được build/start trong deploy `move.nizi.vn`.

Browser chỉ tạo dữ liệu sơ bộ (group thời gian/folder, duplicate checksum, ảnh nhỏ cần xem lại). Server không tạo Event, Memory hay Trip chính thức.
