<p align="center">
  <img src="Resources/Icons/AppIcon-256.png" width="128" height="128" alt="Icon Livewall">
</p>

<h1 align="center">Livewall</h1>

<p align="center">Hình nền video cho macOS, giao diện Liquid Glass.</p>

## Tính năng

- **Mỗi màn hình một video**; màn mới cắm vào tự nhận hình nền của màn chính.
- **Lặp qua lại** (đầu → cuối → đầu) nên không có chỗ nối, âm thanh được nối mờ; hoặc **lặp nối tiếp** cho video chỉ chạy một chiều.
- **Tiết kiệm**: tạm dừng khi desktop bị che, khi màn hình ngủ hoặc khi pin xuống thấp; không giữ màn hình sáng.
- **Tự cắt dải đen** có sẵn trong video.
- **Chạy ngầm**: Thoát từ Dock hay ⌘Q chỉ đóng cửa sổ; thoát hẳn từ icon trên thanh menu. Mở cùng máy (bật trong Cài đặt).
- Kệ video cuộn ngang bằng con lăn chuột hoặc nút mũi tên; lọc, tìm, chỉnh ảnh bìa; dọn file thừa trong thư viện.

## Icon

<img src="Resources/Icons/AppIcon-128.png" width="96" alt="Icon app"> <img src="Resources/Icons/AppIcon-64.png" width="48" alt=""> <img src="Resources/Icons/AppIcon-32.png" width="24" alt=""> <img src="Resources/Icons/AppIcon-16.png" width="16" alt="">

- `Resources/AppIcon.icns`: icon đóng vào app (đã commit sẵn, build không cần sinh lại).
- `Resources/Icons/`: PNG các cỡ để xem.
- Hình vẽ nằm trong `scripts/make-icon.swift`. Đổi icon: sửa file đó rồi chạy `scripts/make-icon.sh`.
- Icon trên thanh menu là SF Symbol `play.rectangle.on.rectangle`.

## Build

**Yêu cầu** (đã build và chạy với đúng cấu hình này):

| | |
|---|---|
| Máy | Apple Silicon (arm64) |
| macOS | 27.2 (chạy được từ macOS 26) |
| Công cụ | Command Line Tools với Swift 6.4.2, SDK macOS 27.2, **không cần Xcode** |
| Phụ thuộc ngoài | không có |

Build và đóng gói `dist/Livewall.app` (ký ad-hoc):

```bash
scripts/bundle.sh
```

Build, cài vào `/Applications` (thay bản cũ) rồi mở:

```bash
scripts/bundle.sh --install && open /Applications/Livewall.app
```

Chạy test logic (127 test). Script này thêm đường dẫn tới Testing.framework của Command Line Tools, vì `swift test` không tự tìm thấy khi không có Xcode:

```bash
scripts/test.sh
```

## Cấu trúc

- `Sources/LivewallCore`: logic thuần, có test.
- `Sources/Livewall`: AppKit, AVFoundation và SwiftUI.
- `Resources/Info.plist`: bundle id `dev.livewall.app`, không hiện ở Dock khi cửa sổ đóng.
- Dữ liệu nằm ở `~/Library/Application Support/Livewall`. Đặt biến `LIVEWALL_HOME` để dùng thư mục khác khi kiểm thử.
