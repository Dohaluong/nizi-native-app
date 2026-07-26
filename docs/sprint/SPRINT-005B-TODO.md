Những vấn đề sau cần giải quyết:

# 1. Điểm checkbox ở ngoài màn Candidate List vẫn quá nhỏ, tôi hay bị chọn nhầm., 
    Đề nghị vùng chọn nhận check box phải to hơn, ít nhất là 44x44pt, và có thể chọn cả vùng xung quanh chứ không chỉ riêng check box.

# 2. Khi vuốt ảnh, viewer đang hiển thị ảnh lớn rồi mới hiển thị, không tận dụng thumbnail hiện có làm ảnh tạm và cũng chưa prefetch ảnh kế tiếp. 
    - Hiện tại, khi người dùng vuốt sang ảnh khác, viewer sẽ hiển thị một màn hình trắng trong vài giây trước khi hiển thị ảnh lớn. 
    - Đề nghị: Hiện thumbnail ngay lập tức, chấp nhận degraded image từ PhotoKit, sau đó thay bằng ảnh chất lượng hơn. 
    - Prefetch các asset liền kề trước khi người dùng vuốt tới chúng.

# 3. Chưa có chức năng doupble tap hoặc dùng 2 ngón tay để zoom ảnh. 
    - Đề nghị: Double tap hoặc dùng 2 ngón để zoom in/out, giữ nguyên vị trí ảnh đang hiển thị.

# 4. Sửa lại màn chọn hay không chọn đều sáng ( không bị làm tối đi nếu không chọn)

# 5. Cần gom nhóm với các ảnh chụp cùng thời điểm. 
    - Ví dụ ảnh trước và ảnh sau cách nhau trong 1 phút là 1 nhóm. 1 nhóm có các ảnh cách nhau dưới 1 phút là đủ điều kiện làm 1 nhóm, không phân nhóm như bây giờ khoảng 1 ngày mới là 1 nhóm

# 6. Trên mỗi nhóm ghi ngày giờ và nút check-all. 
    - Ví dụ:  10:30 - 11/9 . Nút check-all để check/un-check toàn bộ ảnh trong nhóm

# 7. Trong quá trình chọn ảnh , tự động loại các ảnh sau:
    - Ảnh trong thư mục Hidden 
    - Ảnh chụp màn hình
    - Ảnh tài liệu
    - 