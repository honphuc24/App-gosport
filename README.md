# GoSport

Ứng dụng Flutter xem tỷ số, lịch thi đấu và dữ liệu giải đấu từ football-data.org.

```

Ứng dụng gửi một yêu cầu cho endpoint `/matches` theo ngày Việt Nam đang chọn, không khóa vào danh sách giải cố định; API trả về các giải đấu mà tài khoản của bạn được phép truy cập. Endpoint công khai có thể trả dữ liệu không cần token, nhưng để sử dụng đúng quyền truy cập tài khoản hãy truyền token như bên dưới. Có thể thay `emulator-5554` bằng thiết bị đã kết nối, hoặc dùng `-d windows`.

Ứng dụng đọc tỷ số và lịch từ football-data.org, tự làm mới mỗi 5 phút và có thể cập nhật thủ công bằng nút làm mới. Kết quả truy vấn được lưu tạm 1 phút để giảm số lần gọi API; nếu API trả lỗi giới hạn yêu cầu, ứng dụng tôn trọng thời gian chờ do API cung cấp trước khi cho phép gọi lại. Nếu API không có trận trong ngày đã chọn, ứng dụng sẽ báo không có trận thay vì hiển thị tỷ số mẫu.




## Đăng ký và đăng nhập

GoSport dùng Firebase Authentication để đăng ký/đăng nhập bằng email và mật khẩu, đặt lại mật khẩu qua email, hoặc tiếp tục với Google. Tài khoản email cần mật khẩu ít nhất 6 ký tự; Firebase đăng nhập ngay sau khi đăng ký thành công.

1. Tạo project tại [Firebase Console](https://console.firebase.google.com/).
2. Thêm ứng dụng Android với package name `com.example.gosport` (xem `applicationId` trong `android/app/build.gradle.kts`).
3. Trong Firebase Console, mở **Authentication → Sign-in method** và bật **Email/Password**. Bật thêm **Google** nếu muốn dùng đăng nhập Google.
4. Nếu dùng Google, thêm SHA-1 của debug keystore Android vào **Project settings → Your apps → Android app**. Có thể lấy SHA-1 bằng PowerShell:

   ```powershell
   cd android
   .\gradlew signingReport
   ```

   ```powershell
   flutter clean
   flutter pub get
   flutter run --dart-define=FOOTBALL_DATA_KEY=YOUR_API_TOKEN
   ```

`google-services.json` chỉ chứa cấu hình ứng dụng Firebase, nhưng không nên đưa file này lên kho mã công khai nếu chính sách dự án của bạn yêu cầu giữ cấu hình nội bộ. Không gửi token football-data.org vào chat.

## Chức năng dữ liệu bóng đá

Khi chạy với API key, biểu tượng tìm kiếm trên màn hình tỷ số mở **Khám phá bóng đá**:

- Mục nổi bật UEFA Champions League (CL) và Premier League (PL) hiển thị trận đấu theo mùa, bảng xếp hạng, vua phá lưới và các đội.
- Tìm giải đấu, lọc danh sách đội trong giải và xem lịch/kết quả của đội trong mùa hiện tại.
- Nút mở ngoài trang giải đưa tới trang tương ứng trên native-stats (ví dụ: `https://native-stats.org/competition/CL/`).
- Chạm vào trận có mã trận để xem tỷ số và các sự kiện được API cung cấp.
- Tỷ số trực tiếp, lịch theo ngày và lọc giải vẫn nằm ở màn hình chính.

native-stats là website tham khảo, không phải API công khai riêng trong ứng dụng. GoSport lấy dữ liệu có cấu trúc từ API football-data.org; không scrape endpoint nội bộ của website. football-data.org không cung cấp endpoint đội hình và thống kê trận trong API được tích hợp; trang chi tiết chỉ hiển thị các sự kiện có trong phản hồi. Giải đấu, lịch sử và endpoint khả dụng phụ thuộc gói dịch vụ.

## Chạy với dữ liệu mẫu

Không cần API key. Chạy chế độ minh họa bằng lệnh:

```powershell
flutter run -d emulator-5554 --dart-define=USE_SAMPLE_DATA=true
```

Chế độ này dùng các trận và tỷ số cố định để thử giao diện, đồng thời hiển thị nhãn **DỮ LIỆU MẪU · KHÔNG PHẢI TỶ SỐ THẬT**. Bỏ `--dart-define=USE_SAMPLE_DATA=true` để quay lại dùng football-data.org.




## Chạy đồ án LTDD
LỆNH CHẠY
flutter run -d emulator-5554



flutter run -d emulator-5554 --dart-define=FOOTBALL_DATA_KEY=621d0372c13e4e4b80c2e744ff123f02

##
Trong Trình quản lý Tác vụ như ảnh, nhấn ô tìm kiếm phía trên và gõ emulator hoặc qemu. Nếu thấy emulator.exe hay qemu-system-x86_64.exe, chọn đúng tiến trình đó rồi bấm Kết thúc tác vụ. Thao tác này sẽ tắt máy ảo ngay.