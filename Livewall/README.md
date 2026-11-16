# Livewall

Hình nền video cho macOS, giao diện Liquid Glass. Yêu cầu macOS 26 trở lên.

- Mỗi màn hình một video; màn mới cắm vào tự nhận hình nền của màn chính.
- Lặp qua lại (đầu → cuối → đầu) để không có chỗ nối, kèm âm thanh nối mờ; hoặc lặp nối tiếp cho video chỉ chạy một chiều.
- Tạm dừng khi desktop bị che, khi màn hình ngủ hoặc khi pin xuống thấp.
- Tự cắt dải đen có sẵn trong video.
- Chạy ngầm: Thoát từ Dock hay ⌘Q chỉ đóng cửa sổ; thoát hẳn từ icon trên thanh menu.
- Khởi động cùng máy, dọn file thừa trong thư viện.

```bash
scripts/bundle.sh
```

Lệnh trên tạo `dist/Livewall.app`, chỉ cần Command Line Tools, không cần Xcode.

```bash
scripts/test.sh
```

- `Sources/LivewallCore`: logic thuần, có test.
- `Sources/Livewall`: AppKit, AVFoundation và SwiftUI.
- Dữ liệu nằm ở `~/Library/Application Support/Livewall`. Đặt biến `LIVEWALL_HOME` để dùng thư mục khác khi kiểm thử.
