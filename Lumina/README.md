<p align="center">
  <img src="Resources/Icons/AppIcon-256.png" width="128" height="128" alt="Icon Lumina">
</p>

<h1 align="center">Lumina</h1>

<p align="center">App menu bar cho macOS: nhận diện màn hình, chỉnh độ sáng và độ phân giải cho từng màn.</p>

## Tính năng

- **Nhận diện màn hình** đang cắm (tên, hãng, kích thước), tự cập nhật khi cắm/rút hay đổi chế độ.
- **Độ sáng**: màn tích hợp qua DisplayServices; màn ngoài qua **DDC/CI phần cứng** (vd Kuycon P27G); màn không có DDC thì làm tối bằng gamma.
- **Độ phân giải**: thanh trượt các mức HiDPI cùng tỉ lệ + danh sách mọi chế độ; mọi thay đổi **tự hoàn tác sau 15 giây** nếu không bấm "Giữ".
- Popover **Liquid Glass** (macOS 26+), neo đúng dưới icon kể cả khi đổi độ phân giải; danh sách chế độ dạng accordion.
- **Công cụ**:
  - **Ngăn ngủ** — giữ màn hình và máy không tự ngủ khi để yên (IOPM assertion, tự gỡ khi tắt hoặc thoát app).
  - **Sắp xếp màn hình** — bản đồ thu nhỏ, kéo-thả một màn; tự hít vào cạnh màn bên cạnh, không chồng, màn chính giữ ở gốc toạ độ.
- Không hiện ở Dock, chạy nền, **mở cùng máy** (bật/tắt ở chân popover).
- CLI: `Lumina list | get-brightness | set-brightness | set-resolution | arrange | login-item`.

## Icon

| Icon app | Icon menu bar |
|---|---|
| <img src="Resources/Icons/AppIcon-128.png" width="96" alt="Icon app"> <img src="Resources/Icons/AppIcon-64.png" width="48" alt=""> <img src="Resources/Icons/AppIcon-32.png" width="24" alt=""> <img src="Resources/Icons/AppIcon-16.png" width="16" alt=""> | <img src="Resources/Icons/MenuBarIcon@4x.png" width="36" alt="Icon menu bar"> <img src="Resources/Icons/MenuBarIcon@2x.png" width="18" alt=""> |

- `Resources/AppIcon.svg` — nguồn của icon app, sinh bởi `scripts/make-icon-svg.py` (sửa script, không sửa tay).
- `Resources/AppIcon.icns` — icon đóng vào app (đã commit sẵn, build không cần sinh lại).
- `Resources/Icons/` — PNG các cỡ để xem, và `MenuBarIcon.svg` (icon menu bar được vẽ bằng code trong `MenuBarIcon.draw()`, file này cùng hình).

Đổi icon: sửa `scripts/make-icon-svg.py`, rồi

```bash
python3 scripts/make-icon-svg.py && swift scripts/make-icon.swift
```

## Build

**Yêu cầu** (đã build và chạy với đúng cấu hình này):

| | |
|---|---|
| Máy | Apple Silicon (arm64) |
| macOS | 27.2 (chạy được từ macOS 14; Liquid Glass cần macOS 26+) |
| Công cụ | Command Line Tools với Swift 6.4.2, SDK macOS 27.2 — **không cần Xcode** |
| Phụ thuộc ngoài | không có |

Build và đóng gói `build/Lumina.app` (ký ad-hoc):

```bash
scripts/bundle.sh
```

Build, cài vào `/Applications` (thay bản cũ) rồi mở:

```bash
scripts/bundle.sh --install && open /Applications/Lumina.app
```

Chạy test logic (32 test):

```bash
swift test
```

### Lưu ý khi build bằng Command Line Tools

- Trên SDK macOS 27, `@State` của SwiftUI là macro mà plugin chỉ có trong Xcode, nên code dùng alias `@ViewState` (`Sources/Lumina/UI/ViewState.swift`). Đừng đổi lại thành `@State`.
- `swift test` đôi khi báo không tìm thấy plugin `TestingMacros` (hay gặp ngay sau `swift build -c release`); lỗi chập chờn của Command Line Tools, chạy lại `swift test` là qua.
- App ký ad-hoc (`codesign -s -`): chạy được trên máy build. Sang máy khác macOS sẽ chặn vì không có chữ ký Apple.
- Private API (DisplayServices, IOAVService) được nạp bằng `dlsym`; thiếu hàm nào thì tính năng đó tự ẩn, app không crash.

## Cấu trúc

```
Sources/LuminaCore/   logic thuần, có test: chế độ hiển thị, gói DDC, ghép DDC theo EDID, vị trí popover, tự hoàn tác, hít cạnh khi sắp xếp màn
Sources/Lumina/       app: System/ (CoreGraphics, DDC, độ sáng, login item), UI/ (popover, thẻ màn hình), CLI
Tests/                swift-testing
Resources/            Info.plist, icon
scripts/              bundle.sh, sinh icon
docs/                 tài liệu thiết kế và kế hoạch
```

Thiết kế UI trên Claude Design: https://claude.ai/artifact/KUfGxci9hwnDPHiwVaCRtm
