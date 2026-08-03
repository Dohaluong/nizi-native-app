# Security

QR token và native access token dùng random cryptographic bytes; chỉ bản hash được lưu. QR token hết hạn theo `QR_TOKEN_TTL_MINUTES` và bị vô hiệu ngay khi claim thành công. Session chỉ cho một claim; asset download bắt buộc bearer token session và không chấp nhận asset ID đơn lẻ.

Production bắt buộc HTTPS do xCloud/Nginx quản lý. Không log request body/token. Giới hạn MIME/extension ảnh, dung lượng file/session và dùng checksum trước khi commit object. Chủ browser giữ `X-Session-Owner` chỉ trong phiên UI để upload/finalize/xoá.
