# Lumina — Tài liệu thiết kế

Ngày: 2026-11-02 · Trạng thái: chờ duyệt

## 1. Ý định

Lumina là app menu bar cho macOS, có **đủ tính năng tương đương BetterDisplay** (31 tính năng đã liệt kê và người dùng chọn "làm hết"). Giao diện là một popover đẹp, trực quan, thiết kế bằng **Claude Design** trước khi code.

Lumina là sản phẩm **tự viết**: tên, icon, giao diện và code đều riêng, không decompile hay chép code/tài nguyên của BetterDisplay. Chỉ học *cơ chế* từ kiến thức công khai và các dự án mã nguồn mở (MonitorControl, BetterDummy, displayplacer…) theo đúng license của chúng.

## 2. Mục tiêu / Không phải mục tiêu / Phản mục tiêu

**Mục tiêu**
- Đủ 31 tính năng, chia 5 đợt; hết mỗi đợt app đều chạy được.
- Popover menu bar: mở ra là thấy ngay các màn hình đang có, thao tác chính (độ sáng, độ phân giải) trong 1–2 cú bấm.
- Chạy tốt trên máy của người dùng: Apple M5 Pro, macOS 27.0.1, màn tích hợp Liquid Retina XDR + màn ngoài Kuycon P27G 5K.

**Không phải mục tiêu**
- Phát hành lên Mac App Store (dùng private API nên không thể).
- Hỗ trợ Mac Intel (chỉ Apple Silicon; đường DDC qua IOI2C của Intel bỏ qua).
- Bản quyền / license / thanh toán.
- Hệ thống cập nhật tự động (tính năng 31 chỉ gồm "khởi động cùng máy"; tự cập nhật để dành khi có nơi phát hành — *quyết định của Claude*).

**Phản mục tiêu** (làm vậy là hỏng dù "chạy được")
- Giao diện trông như bản sao BetterDisplay (cùng tên, icon, bố cục y hệt).
- Thao tác làm màn hình đen/không khôi phục được mà không có đường thoát. Mọi thao tác nguy hiểm (đổi độ phân giải, ngắt màn, HiDPI mirror) phải có **hộp xác nhận tự hoàn tác sau 15 giây** như System Settings.
- App gây lag hoặc ăn CPU khi chạy nền (mục tiêu: <1% CPU khi rảnh).

## 3. Ràng buộc

- Máy chỉ có Command Line Tools (Swift 6.4), **không có Xcode**. Build bằng Swift Package Manager, đóng gói `.app` bằng script (`Info.plist` với `LSUIElement`, ký ad-hoc hoặc bằng chứng chỉ tự ký ổn định để quyền Screen Recording/Accessibility không mất sau mỗi lần build).
- Không sandbox. Cần quyền: Accessibility (bắt phím độ sáng/âm lượng), Screen Recording (PIP / phát màn hình).
- Deployment target: macOS 14+. Kiểm thử thực tế trên macOS 27.
- Private API khai báo trong một target ObjC/C riêng (`LuminaPrivate`) với header tự viết; hàm C nạp bằng `dlsym` để app không crash nếu API biến mất — tính năng tương ứng tự ẩn.
- App Intents (Shortcuts) cần bước xử lý metadata của Xcode; nếu không build được bằng SwiftPM thì tính năng 30 dùng URL scheme `lumina://` + CLI thay thế.

## 4. Kiến trúc (quyết định của Claude)

```
Lumina (SwiftPM)
├── LuminaApp        — SwiftUI app, MenuBarExtra(.window) popover, cửa sổ Settings, OSD HUD, PIP windows
├── LuminaCore       — model + service thuần Swift, test được
│   ├── DisplayRegistry   (liệt kê, theo dõi cắm/rút qua CGDisplayRegisterReconfigurationCallback)
│   ├── ModeService       (độ phân giải, Hz, xoay, mirror, màn chính)
│   ├── BrightnessService (gộp DDC + phần mềm + XDR thành một thang 0–100%+)
│   ├── DDCService        (IOAVService I2C, hàng đợi, retry, cache)
│   ├── VirtualDisplayService, ColorService, StreamService, ProtectionService, PresetService
│   └── Settings store (JSON trong Application Support)
├── LuminaPrivate    — header private API (CGVirtualDisplay, IOAVService, DisplayServices, SkyLight, MonitorPanel…)
└── lumina (CLI)     — gửi lệnh tới app qua URL scheme / XPC
```

Mỗi service công bố "khả năng" (capability) theo từng màn hình; UI chỉ hiện điều khiển mà màn đó hỗ trợ.

## 5. Tính năng và cách làm

Mức độ: 🟢 API chính thức · 🟡 private API · 🔴 rủi ro cao, có thể không làm được trên macOS 27.

### Đợt 1 — Khung app và chế độ hiển thị
| # | Tính năng | Cách làm |
|---|---|---|
| 3 | Thanh trượt độ phân giải | Danh sách mode sắp theo kích thước, slider nhảy giữa các mode khả dụng (gồm mode ẩn) |
| 4 | Danh sách độ phân giải + yêu thích | `CGDisplayCopyAllDisplayModes` + `kCGDisplayShowDuplicateLowResolutionModes`; mode ẩn qua SkyLight `CGSGetDisplayModeDescriptionOfLength`/`CGSConfigureDisplayMode` |
| 5 | Tần số quét | Lọc mode cùng kích thước khác Hz |
| 7 | Xoay | `MPDisplay` (MonitorPanel.framework) `setOrientation` |
| 21 | Mirror, màn chính | `CGConfigureDisplayMirrorOfDisplay`, `CGConfigureDisplayOrigin` |
| 24 | Thông tin màn hình | `CGDisplay*`, IORegistry (EDID, vendor, serial, cổng) |
| 28 | Phím tắt toàn cục | Carbon `RegisterEventHotKey` (không cần quyền Accessibility) |
| 31 | Khởi động cùng máy | `SMAppService.mainApp` |

### Đợt 2 — Độ sáng và DDC
| # | Tính năng | Cách làm |
|---|---|---|
| 8–11 | DDC: sáng, tương phản, âm lượng, tắt tiếng, cổng vào, RGB gain, nguồn | `IOAVServiceCreateWithService` + `IOAVServiceWriteI2C/ReadI2C` (địa chỉ 0x37, offset 0x51), ghép `DCPAVServiceProxy` với display qua IORegistry. Hàng đợi tuần tự, chờ ≥50 ms giữa lệnh, đọc có retry |
| 12 | Làm tối bằng phần mềm | `CGSetDisplayTransferByTable` (gamma); với màn không DDC dùng làm thang chính, với màn có DDC nối tiếp xuống dưới 0% DDC |
| 13 | Tăng sáng XDR/HDR | Overlay cửa sổ trong suốt dùng `CAMetalLayer` EDR + compositing multiply để kéo headroom; chỉ bật trên màn có EDR headroom > 1 |
| 14 | Phím sáng/âm lượng + OSD | `CGEventTap` bắt `NX_SYSDEFINED` (cần Accessibility); OSD tự vẽ theo thiết kế Lumina; áp lên màn đang chứa con trỏ |
| 15 | Đồng bộ độ sáng | Đọc độ sáng màn tích hợp qua `DisplayServices` và áp tỉ lệ cho màn ngoài; tùy chọn theo cảm biến ánh sáng |

### Đợt 3 — Màn hình ảo, HiDPI, màu
| # | Tính năng | Cách làm |
|---|---|---|
| 1 | Màn hình ảo | `CGVirtualDisplay` / `CGVirtualDisplayDescriptor` / `CGVirtualDisplaySettings` / `CGVirtualDisplayMode`; preset tỉ lệ 16:9, 16:10, 21:9, 32:9, 4:3, tùy chỉnh; bật/tắt, lưu lại |
| 2 | HiDPI cho màn thường | Tạo màn ảo `hiDPI = 1` rồi mirror màn thật vào nó (cách đã được BetterDummy chứng minh) |
| 16 | Chỉnh màu phần mềm | Bảng gamma: gamma, nhiệt độ màu, tương phản, bão hòa (ghép chung với dimming #12) |
| 17 | Hồ sơ màu | ColorSync `ColorSyncDeviceSetCustomProfiles` |
| 18 | Bật/tắt HDR | `MPDisplay` HDR API (MonitorPanel) |

### Đợt 4 — PIP, phát hình, tự động hóa
| # | Tính năng | Cách làm |
|---|---|---|
| 25 | Picture-in-Picture | ScreenCaptureKit `SCStream` → cửa sổ nổi có thể kéo, đổi kích thước, luôn trên cùng, xuyên click tùy chọn |
| 26 | Phát màn hình | Cửa sổ full-screen không viền trên màn đích, co giãn fit/fill/stretch |
| 27 | Lật/xoay khi phát | Transform layer |
| 22 | Bảo vệ cấu hình | Lưu cấu hình mong muốn; khi callback reconfigure báo thay đổi không do Lumina gây ra thì áp lại |
| 29 | Presets | Nhận diện "bộ màn hình" theo vendor+model+serial; tự áp khi khớp |
| 30 | CLI / URL scheme / Shortcuts | `lumina://set?display=…&brightness=…`, CLI `lumina` in kết quả JSON; App Intents nếu build được |

### Đợt 5 — Nhóm rủi ro
| # | Tính năng | Cách làm (cần khảo sát trên macOS 27 trước) |
|---|---|---|
| 6 | Độ phân giải tùy chỉnh (EDID) | Ưu tiên: thêm mode qua màn ảo; ghi đè EDID chỉ khi khả thi |
| 19 | Độ sâu màu, RGB/YCbCr | Khảo sát API kết nối của DCP/IOMobileFramebuffer |
| 20 | Ngắt/kết nối màn bằng phần mềm | SkyLight `SLSConfigureDisplayEnabled` |
| 23 | Sidecar/AirPlay | `SidecarCore` (`SidecarDisplayManager`); AirPlay khảo sát sau |

Tính năng nào trong Đợt 5 không làm được thì báo rõ lý do, không giả lập.

## 6. Giao diện (Đợt 0 — Claude Design)

Thiết kế trong Claude Design (https://claude.ai/artifact/KUfGxci9hwnDPHiwVaCRtm), người dùng duyệt trước khi code. Ngôn ngữ giao diện: tiếng Việt (quyết định của Claude). Bảng màu: nền graphite #1C1C1F, accent hổ phách #F5A524, vùng XDR #FFD873. Phạm vi:

1. **Popover menu bar** (~360 pt rộng): mỗi màn hình một thẻ — tên + biểu tượng loại màn, slider độ sáng gộp (vạch đánh dấu vùng XDR >100%), hàng nút nhanh (độ phân giải, Hz, HiDPI, PIP, nhiều hơn). Bấm vào thẻ mở rộng chi tiết: danh sách độ phân giải có yêu thích, DDC (tương phản, âm lượng, cổng vào), màu. Cuối popover: màn hình ảo (thêm/bật/tắt), presets, nút Settings.
2. **Cửa sổ Settings**: sidebar (Chung, Màn hình, Độ sáng, Màn hình ảo, PIP & Phát hình, Phím tắt, Presets, Nâng cao/Thử nghiệm).
3. **OSD HUD** độ sáng/âm lượng.
4. **Hộp xác nhận tự hoàn tác** 15 giây.

Phong cách: hợp với macOS 26/27 (Liquid Glass), sáng/tối đều đẹp, nhận diện riêng của Lumina.

## 7. Kiểm thử

- `LuminaCore` có unit test cho logic thuần: lọc/sắp mode, gói tin DDC + checksum, ghép thang độ sáng DDC/phần mềm/XDR, khớp preset.
- Mỗi đợt kiểm tra thủ công trên 2 màn thật của người dùng; ghi lại kết quả theo từng tính năng.

## 8. Để người xây dựng quyết định

- Cấu trúc file chi tiết, tên type.
- Cách lưu settings (JSON hay `UserDefaults`), miễn có thể export/import.
- Ký app: ad-hoc hay chứng chỉ tự ký, miễn quyền hệ thống không mất sau mỗi lần build.
- Chi tiết thuật toán đồng bộ độ sáng.
