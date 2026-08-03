# Deploy xCloud

Thiết lập Environment:

```env
NODE_ENV=production
PORT=4318
PUBLIC_BASE_URL=https://move.nizi.vn
SESSION_TTL_HOURS=24
QR_TOKEN_TTL_MINUTES=30
# Xoá file multipart upload bị ngắt sau 60 phút
UPLOAD_TEMP_TTL_MINUTES=60
UPLOAD_STORAGE_PATH=/persistent-path/nizi-move
MAX_FILE_SIZE_BYTES=262144000
MAX_SESSION_SIZE_BYTES=0
```

xCloud chạy lần lượt `npm install`, `npm run build`, rồi `npm run start:server`. Không chạy `npm run dev:desktop`; không chỉnh Nginx/SSL từ repository. Kiểm tra sau deploy bằng `GET /api/health`.

Server dọn session hết hạn mỗi 15 phút và cũng dọn file multipart còn sót trong `UPLOAD_STORAGE_PATH/temporary`. `UPLOAD_TEMP_TTL_MINUTES` mặc định là 60; giữ giá trị này lớn hơn thời gian upload tối đa dự kiến của một ảnh để không chạm vào upload đang chạy.
