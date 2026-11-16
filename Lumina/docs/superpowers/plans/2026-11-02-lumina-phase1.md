# Lumina Đợt 1 — Khung app và chế độ hiển thị — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App menu bar Lumina chạy được, có popover liệt kê màn hình, đổi độ phân giải/Hz/xoay/mirror/màn chính có tự hoàn tác, xem thông tin màn hình, phím tắt toàn cục, khởi động cùng máy (tính năng 3, 4, 5, 7, 21, 24, 28, 31).

**Architecture:** SwiftPM gồm `LuminaCore` (model + logic thuần, có test), `LuminaPrivate` (header ObjC cho MonitorPanel), `Lumina` (executable SwiftUI `MenuBarExtra(.window)`). Logic quyết định (gom mode, tính toạ độ, đếm ngược) nằm trong Core dưới dạng hàm thuần; phần gọi CoreGraphics nằm trong service mỏng, kiểm tra thủ công trên màn thật.

**Tech Stack:** Swift 6.4, SwiftUI, AppKit, CoreGraphics, Carbon (hotkey), ServiceManagement, MonitorPanel.framework (private), swift-testing. Không dùng dependency ngoài.

**Spec:** `docs/superpowers/specs/2026-11-02-lumina-design.md` · Thiết kế UI: https://claude.ai/artifact/KUfGxci9hwnDPHiwVaCRtm (artboard `Main`, `Detail` tab Hiển thị, `Settings`, `Overlays`).

## Global Constraints

- macOS deployment target 14; chỉ arm64. Không sandbox, không Mac App Store.
- Build bằng `swift build` (không có Xcode). `.app` đóng gói bằng `scripts/bundle.sh`, ký ad-hoc (`codesign -s -`).
- Bundle id `com.hoanganh.lumina`, `LSUIElement = YES`, tên hiển thị `Lumina`.
- Giao diện tiếng Việt, theo đúng chữ trong thiết kế. Popover và cửa sổ luôn dùng giao diện tối (`.preferredColorScheme(.dark)`) — *quyết định của Claude*, vì thiết kế chỉ có bản tối.
- Bảng màu (`Theme`): nền `#1C1C1F`, thẻ `#26262A`, chip `#34343A`, rãnh slider `#3A3A40`, công tắc tắt `#3F3F46`, chữ `#F2F2F4`, chữ phụ `#A1A1AA`, accent `#F5A524`, accent nền mềm `#F5A524` 16% với chữ `#FFC86B`, chữ trên accent `#1A1300`, XDR `#FFD873`. Popover rộng 380 pt, bo góc 18; thẻ bo 14; chip cao 28 bo 8; công tắc 38×22.
- Mọi thay đổi chế độ hiển thị (độ phân giải, Hz, xoay, mirror, màn chính) phải qua hộp xác nhận **tự hoàn tác sau 15 giây**.
- Private API chỉ gọi sau khi kiểm tra `NSClassFromString`/`responds(to:)`; thiếu thì ẩn điều khiển tương ứng, không crash.
- CPU khi rảnh < 1%: không polling; chỉ cập nhật qua `CGDisplayRegisterReconfigurationCallback`.

## Review Focus

1. **Rút cáp màn hình khi popover đang mở hoặc khi đang đếm ngược hoàn tác** → không crash; hộp xác nhận tự đóng, không cố hoàn tác trên màn đã mất. (Task 4: `PendingChange` bỏ qua khi display không còn.)
2. **Đổi sang mode làm màn đen / mất tín hiệu** → sau 15 giây vẫn tự hoàn tác dù popover đã đóng và người dùng không thấy hộp thoại. (Task 4: test hết hạn của `AutoRevert`.)
3. **Màn chỉ có 1 mode hoặc không có mode HiDPI** → thanh trượt độ phân giải ẩn, danh sách vẫn hiện. (Task 2: test `sliderModes` với 1 mode.)
4. **Hai màn hình giống hệt nhau, serial = 0** → yêu thích của màn này không lẫn sang màn kia. (Task 3: test `DisplayIdentity.key` có unit number khi serial = 0.)
5. **Phím tắt không có phím bổ trợ hoặc đã bị app khác chiếm** → không đăng ký được thì báo "Phím tắt này đang được dùng" ngay ở ô ghi phím, không im lặng. (Task 8: test `KeyCombo.isValidGlobal`, và `HotKeyCenter.register` trả lỗi.)

---

## File Structure

```
Package.swift
scripts/bundle.sh                      — build release + đóng gói build/Lumina.app (+ --install vào ~/Applications)
Resources/Info.plist
Sources/LuminaPrivate/include/MonitorPanel.h, module.modulemap, LuminaPrivate.m (rỗng)
Sources/LuminaCore/
  DisplayModeInfo.swift   — struct mode + HiDPI
  ModeCatalog.swift       — gom/sắp/lọc mode, chọn mode tốt nhất
  DisplayIdentity.swift   — khoá nhận diện màn, kích thước đường chéo
  FavoritesStore.swift    — lưu yêu thích (JSON)
  AutoRevert.swift        — đếm ngược 15 giây
  ArrangementPlanner.swift— toạ độ khi đổi màn chính, kiểm tra mirror hợp lệ
  KeyCombo.swift          — tổ hợp phím, mô tả "⌥⌘1", Codable
Sources/Lumina/
  LuminaApp.swift, AppState.swift
  System/DisplayRegistry.swift, ModeService.swift, RotationService.swift, ArrangementService.swift,
         DisplayInfoReader.swift, HotKeyCenter.swift, LoginItem.swift
  UI/Theme.swift, Components.swift, PopoverView.swift, DisplayCardView.swift, DetailView.swift,
     InfoView.swift, ConfirmRevertPanel.swift, SettingsWindow.swift, MenuBarIcon.swift
Tests/LuminaCoreTests/*.swift
```

---

### Task 1: Khung package, đóng gói .app, popover rỗng

**Files:**
- Create: `Package.swift`, `Resources/Info.plist`, `scripts/bundle.sh`, `Sources/LuminaPrivate/…`, `Sources/LuminaCore/Placeholder.swift`, `Sources/Lumina/LuminaApp.swift`, `Sources/Lumina/UI/MenuBarIcon.swift`, `Tests/LuminaCoreTests/SmokeTests.swift`, `.gitignore` (`.build/`, `build/`)

**Interfaces:**
- Produces: target names `LuminaCore` (library), `LuminaPrivate` (ObjC), `Lumina` (executable, phụ thuộc cả hai); `scripts/bundle.sh [--install]` → `build/Lumina.app`.

- [ ] **Step 1:** `Package.swift` tools 6.0, `platforms: [.macOS(.v14)]`, 3 target trên + `LuminaCoreTests`. `Lumina` link `-framework MonitorPanel -F /System/Library/PrivateFrameworks` qua `linkerSettings: [.unsafeFlags([...])]`.
- [ ] **Step 2:** `MonitorPanel.h` khai báo `MPDisplayMgr` (`-init`, `-(NSArray*)displays`, `-(MPDisplay*)displayWithID:(int)`) và `MPDisplay` (`displayID`, `isBuiltIn`, `canChangeOrientation`, `orientation`, `-setOrientation:(int)`). Trước khi viết, xác minh selector bằng `class_copyMethodList` (đã thấy `setOrientation:`, `canChangeOrientation`, `displayID`; kiểm tra thêm `displayWithID:`/`displays` — nếu khác tên thì dùng tên thật).
- [ ] **Step 3:** `LuminaApp`: `MenuBarExtra { Text("Lumina") } label: { MenuBarIcon() }.menuBarExtraStyle(.window)`. `MenuBarIcon` vẽ template image 18 pt: vòng tròn r9 nét 2 (opacity 0.45) + chấm đặc r5, giống logo thiết kế.
- [ ] **Step 4:** `bundle.sh`: `swift build -c release --arch arm64`, tạo `build/Lumina.app/Contents/{MacOS,Resources}`, chép binary + `Info.plist` (bundle id, `LSUIElement`, `CFBundleShortVersionString 0.1.0`, `LSMinimumSystemVersion 14.0`), `codesign --force -s - build/Lumina.app`. `--install` chép sang `~/Applications/Lumina.app`.
- [ ] **Step 5:** `SmokeTests`: `@Test func coreLinks() { #expect(LuminaCore.version == "0.1.0") }`.
- [ ] **Step 6:** Chạy `swift test` → PASS; `scripts/bundle.sh && open build/Lumina.app && sleep 2 && pgrep -x Lumina` → in ra PID.
- [ ] **Step 7:** Commit `feat: scaffold Lumina menu bar app`.

---

### Task 2: Model mode và ModeCatalog (tính năng 3, 4, 5)

**Files:** Create `Sources/LuminaCore/DisplayModeInfo.swift`, `ModeCatalog.swift`; Test `Tests/LuminaCoreTests/ModeCatalogTests.swift`

**Interfaces:**
- Produces:
  - `public struct DisplayModeInfo: Hashable, Codable, Sendable { public let id: Int32; width, height, pixelWidth, pixelHeight: Int; refreshRate: Double; isUsableForDesktopGUI: Bool; var isHiDPI: Bool { pixelWidth >= width * 2 } }`
  - `public struct Resolution: Hashable, Codable, Sendable { width, height: Int; isHiDPI: Bool; var label: String /* "2560 × 1440" */ }`
  - `public enum ModeCatalog { static func resolutions(_ modes: [DisplayModeInfo]) -> [Resolution]; static func refreshRates(for r: Resolution, in modes: [DisplayModeInfo]) -> [Double]; static func sliderModes(_ modes: [DisplayModeInfo], current: DisplayModeInfo) -> [Resolution]; static func bestMode(for r: Resolution, preferredRefresh: Double?, in modes: [DisplayModeInfo]) -> DisplayModeInfo? }`

- [ ] **Step 1: Test**

```swift
func m(_ id: Int32, _ w: Int, _ h: Int, hidpi: Bool = false, hz: Double = 60, gui: Bool = true) -> DisplayModeInfo {
  DisplayModeInfo(id: id, width: w, height: h, pixelWidth: hidpi ? w*2 : w, pixelHeight: hidpi ? h*2 : h, refreshRate: hz, isUsableForDesktopGUI: gui)
}
@Test func resolutionsDedupedSortedBySizeSkippingNonGUI() {
  let r = ModeCatalog.resolutions([m(1,2560,1440,hidpi:true), m(2,2560,1440,hidpi:true,hz:50), m(3,1920,1080), m(4,640,480,gui:false), m(5,1920,1080,hidpi:true)])
  #expect(r.map(\.label) == ["1920 × 1080", "1920 × 1080", "2560 × 1440"])
  #expect(r.map(\.isHiDPI) == [false, true, true])
}
@Test func refreshRatesDescendingUnique() {
  let ms = [m(1,2560,1440,hidpi:true,hz:50), m(2,2560,1440,hidpi:true,hz:60), m(3,2560,1440,hidpi:true,hz:60)]
  #expect(ModeCatalog.refreshRates(for: Resolution(width:2560,height:1440,isHiDPI:true), in: ms) == [60, 50])
}
@Test func sliderKeepsSameKindAndAspectAsCurrent() {
  let cur = m(1,2560,1440,hidpi:true)
  let ms = [cur, m(2,1920,1080,hidpi:true), m(3,1920,1200,hidpi:true), m(4,3840,2160), m(5,3200,1800,hidpi:true)]
  #expect(ModeCatalog.sliderModes(ms, current: cur).map(\.label) == ["1920 × 1080", "2560 × 1440", "3200 × 1800"])
}
@Test func sliderWithSingleModeHasOneStop() {   // Review Focus 3
  let cur = m(1,1920,1080)
  #expect(ModeCatalog.sliderModes([cur], current: cur).count == 1)
}
@Test func bestModePrefersRequestedRefreshElseHighest() {
  let ms = [m(1,2560,1440,hidpi:true,hz:50), m(2,2560,1440,hidpi:true,hz:60)]
  let r = Resolution(width:2560,height:1440,isHiDPI:true)
  #expect(ModeCatalog.bestMode(for: r, preferredRefresh: 50, in: ms)?.id == 1)
  #expect(ModeCatalog.bestMode(for: r, preferredRefresh: 75, in: ms)?.id == 2)
}
```

- [ ] **Step 2:** `swift test --filter ModeCatalogTests` → FAIL (chưa có type).
- [ ] **Step 3:** Cài đặt. Cùng tỉ lệ = `abs(w/h - cw/ch) < 0.01`. Sắp theo `width*height`, rồi `isHiDPI` false trước. Refresh so sánh làm tròn 0.1.
- [ ] **Step 4:** `swift test --filter ModeCatalogTests` → PASS.
- [ ] **Step 5:** Commit `feat(core): mode catalog`.

---

### Task 3: Nhận diện màn hình và DisplayRegistry (tính năng 24 phần dữ liệu)

**Files:** Create `Sources/LuminaCore/DisplayIdentity.swift`, `Sources/Lumina/System/DisplayRegistry.swift`, `DisplayInfoReader.swift`, `Sources/Lumina/AppState.swift`; Test `Tests/LuminaCoreTests/DisplayIdentityTests.swift`

**Interfaces:**
- Consumes: `DisplayModeInfo`.
- Produces:
  - `public struct DisplayIdentity: Hashable, Codable, Sendable { vendor, model, serial, unitNumber: UInt32; var key: String }` — `key` = `"\(vendor)-\(model)-\(serial)"`, và khi `serial == 0` thì `"\(vendor)-\(model)-u\(unitNumber)"`.
  - `public func diagonalInches(widthMM: Double, heightMM: Double) -> Double`
  - `struct DisplaySnapshot: Identifiable { id: CGDirectDisplayID; identity: DisplayIdentity; name: String; isBuiltIn, isMain: Bool; mirrorOf: CGDirectDisplayID?; bounds: CGRect; rotation: Int; current: DisplayModeInfo; modes: [DisplayModeInfo]; canRotate: Bool; sizeMM: CGSize }`
  - `@MainActor @Observable final class DisplayRegistry { private(set) var displays: [DisplaySnapshot]; func reload(); func modeObject(id: Int32, display: CGDirectDisplayID) -> CGDisplayMode? }`
  - `@MainActor @Observable final class AppState` giữ `registry`, các service, và `pending: PendingChange?` (Task 4).

- [ ] **Step 1: Test**

```swift
@Test func keyUsesSerialWhenPresent() {
  #expect(DisplayIdentity(vendor: 1, model: 2, serial: 3, unitNumber: 9).key == "1-2-3")
}
@Test func twoIdenticalMonitorsWithoutSerialGetDifferentKeys() {   // Review Focus 4
  let a = DisplayIdentity(vendor: 1, model: 2, serial: 0, unitNumber: 4)
  let b = DisplayIdentity(vendor: 1, model: 2, serial: 0, unitNumber: 5)
  #expect(a.key != b.key)
}
@Test func diagonalOf27InchPanel() {
  #expect(abs(diagonalInches(widthMM: 597, heightMM: 336) - 27.0) < 0.1)
}
```

- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt Core.
- [ ] **Step 4:** `DisplayRegistry.reload()`: `CGGetOnlineDisplayList`; mode qua `CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true])`, giữ map `ioDisplayModeID → CGDisplayMode`; tên từ `NSScreen.screens` khớp `NSScreenNumber` (màn đang mirror không có NSScreen → tên lấy từ `DisplayInfoReader` IORegistry `DisplayAttributes.ProductAttributes.ProductName`, cuối cùng "Màn hình \(id)"); `canRotate` từ `MPDisplay.canChangeOrientation`. Đăng ký `CGDisplayRegisterReconfigurationCallback`, debounce 300 ms trên main rồi `reload()`.
- [ ] **Step 5:** `swift test` → PASS. Chạy app, log `displays` ra console: thấy 2 màn ("Color LCD"/tích hợp và "Kuycon P27G") với mode 1512×982 và 2560×1440.
- [ ] **Step 6:** Commit `feat: display registry`.

---

### Task 4: Đổi mode và tự hoàn tác 15 giây

**Files:** Create `Sources/LuminaCore/AutoRevert.swift`, `Sources/Lumina/System/ModeService.swift`, `Sources/Lumina/UI/ConfirmRevertPanel.swift`; Test `Tests/LuminaCoreTests/AutoRevertTests.swift`

**Interfaces:**
- Consumes: `DisplayRegistry.modeObject`, `DisplaySnapshot`.
- Produces:
  - `public struct AutoRevert: Sendable { public init(start: Date, duration: TimeInterval = 15); func remaining(at: Date) -> Int /* làm tròn lên, không âm */; func isExpired(at: Date) -> Bool }`
  - `struct PendingChange { let displayID: CGDirectDisplayID; let summary: String; let revert: @MainActor () -> Void; let timer: AutoRevert }`
  - `@MainActor final class ModeService { func apply(_ mode: DisplayModeInfo, to id: CGDirectDisplayID) throws }` — `CGBeginDisplayConfiguration` → `CGConfigureDisplayWithDisplayMode` → `CGCompleteDisplayConfiguration(.permanently)`; lỗi trả `LuminaError.configuration(CGError)`.
  - `AppState.perform(_ summary: String, displayID:, change: () throws -> Void, revert: @escaping @MainActor () -> Void)` — chạy change, đặt `pending`, mở `ConfirmRevertPanel`.

- [ ] **Step 1: Test**

```swift
@Test func countsDownFrom15() {
  let t0 = Date(timeIntervalSince1970: 0)
  let r = AutoRevert(start: t0)
  #expect(r.remaining(at: t0) == 15)
  #expect(r.remaining(at: t0.addingTimeInterval(3.2)) == 12)
  #expect(!r.isExpired(at: t0.addingTimeInterval(14.9)))
}
@Test func expiresAndNeverGoesNegative() {   // Review Focus 2
  let t0 = Date(timeIntervalSince1970: 0)
  let r = AutoRevert(start: t0)
  #expect(r.isExpired(at: t0.addingTimeInterval(15)))
  #expect(r.remaining(at: t0.addingTimeInterval(99)) == 0)
}
```

- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt `AutoRevert`. **Step 4:** Chạy → PASS.
- [ ] **Step 5:** `ConfirmRevertPanel`: `NSPanel` `.nonactivatingPanel`, level `.modalPanel`, căn giữa **mọi** màn còn sống (một panel mỗi màn, để vẫn thấy dù màn vừa đổi bị đen); nội dung theo artboard `Overlays` (vòng đếm ngược 44 pt, tiêu đề "Giữ độ phân giải mới?" hoặc tóm tắt tương ứng, nút "Hoàn tác" / "Giữ thay đổi"). Timer 1 Hz chạy trong `AppState`, không phụ thuộc popover. Hết hạn → `revert()`.
- [ ] **Step 6:** Trước khi `revert()`, nếu `displayID` không còn trong `registry.displays` thì chỉ đóng panel (Review Focus 1). Mỗi lần `reload()` mà màn của `pending` biến mất cũng đóng panel.
- [ ] **Step 7:** Thủ công: đổi Kuycon sang 1920×1080 qua lệnh debug tạm, chờ 15 giây → tự về 2560×1440; lặp lại và bấm "Giữ thay đổi" → giữ.
- [ ] **Step 8:** Commit `feat: mode switching with auto-revert`.

---

### Task 5: Xoay, mirror, màn chính (tính năng 7, 21)

**Files:** Create `Sources/LuminaCore/ArrangementPlanner.swift`, `Sources/Lumina/System/RotationService.swift`, `ArrangementService.swift`; Test `Tests/LuminaCoreTests/ArrangementPlannerTests.swift`

**Interfaces:**
- Produces:
  - `public enum ArrangementPlanner { static func originsMakingMain(_ id: UInt32, bounds: [UInt32: CGRect]) -> [UInt32: CGPoint]; static func canMirror(source: UInt32, into target: UInt32, mirrorOf: [UInt32: UInt32]) -> Bool }`
  - `RotationService.setRotation(_ degrees: Int, display: CGDirectDisplayID) throws` (0/90/180/270 qua `MPDisplay.setOrientation`).
  - `ArrangementService.setMain(_ id:) throws`, `.mirror(_ source:, into target:) throws`, `.stopMirroring(_ id:) throws` (`CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)`).

- [ ] **Step 1: Test**

```swift
@Test func newMainMovesToOriginOthersShiftTogether() {
  let o = ArrangementPlanner.originsMakingMain(4, bounds: [1: CGRect(x: 0, y: 0, width: 1512, height: 982), 4: CGRect(x: 1512, y: -458, width: 2560, height: 1440)])
  #expect(o[4] == CGPoint(x: 0, y: 0))
  #expect(o[1] == CGPoint(x: -1512, y: 458))
}
@Test func cannotMirrorIntoSelfOrIntoADisplayThatMirrorsSource() {
  #expect(!ArrangementPlanner.canMirror(source: 1, into: 1, mirrorOf: [:]))
  #expect(!ArrangementPlanner.canMirror(source: 1, into: 4, mirrorOf: [4: 1]))
  #expect(ArrangementPlanner.canMirror(source: 4, into: 1, mirrorOf: [:]))
}
```

- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt. **Step 4:** Chạy → PASS.
- [ ] **Step 5:** Service: mọi thay đổi đi qua `AppState.perform` (Task 4) với hàm revert khôi phục rotation/origin/mirror cũ.
- [ ] **Step 6:** Thủ công: xoay Kuycon 90° rồi để tự hoàn tác; đặt Kuycon làm màn chính rồi giữ, đặt lại MacBook; mirror Kuycon vào MacBook rồi hoàn tác.
- [ ] **Step 7:** Commit `feat: rotation, mirroring and main display`.

---

### Task 6: Giao diện popover và chi tiết (tính năng 3, 4, 5 trên UI) + yêu thích

**Files:** Create `Sources/LuminaCore/FavoritesStore.swift`, `Sources/Lumina/UI/Theme.swift`, `Components.swift`, `PopoverView.swift`, `DisplayCardView.swift`, `DetailView.swift`; Test `Tests/LuminaCoreTests/FavoritesStoreTests.swift`

**Interfaces:**
- Consumes: `ModeCatalog`, `DisplayIdentity.key`, `AppState.perform`, `ModeService.apply`, `RotationService`, `ArrangementService`.
- Produces:
  - `public final class FavoritesStore { public init(fileURL: URL); func isFavorite(_ r: Resolution, display key: String) -> Bool; func toggle(_ r: Resolution, display key: String); func favorites(display key: String) -> [Resolution] }` — ghi JSON ngay sau mỗi `toggle`. File mặc định `~/Library/Application Support/Lumina/favorites.json`.
  - Components: `LuminaSlider(value: Binding<Double>, range: ClosedRange<Double>, style: .pill | .thin)`, `ChipButton`, `LuminaToggleStyle`, `CardBackground`.

- [ ] **Step 1: Test**

```swift
@Test func favoritesPersistAcrossInstances() throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
  let r = Resolution(width: 2560, height: 1440, isHiDPI: true)
  FavoritesStore(fileURL: url).toggle(r, display: "1-2-3")
  #expect(FavoritesStore(fileURL: url).isFavorite(r, display: "1-2-3"))
  #expect(!FavoritesStore(fileURL: url).isFavorite(r, display: "1-2-4"))
}
@Test func toggleTwiceRemoves() {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
  let s = FavoritesStore(fileURL: url); let r = Resolution(width: 1920, height: 1080, isHiDPI: false)
  s.toggle(r, display: "k"); s.toggle(r, display: "k")
  #expect(s.favorites(display: "k").isEmpty)
}
```

- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt. **Step 4:** Chạy → PASS.
- [ ] **Step 5:** `PopoverView` theo artboard `Main`, chỉ phần thuộc Đợt 1: header (logo + "Lumina"; **chưa** có chip preset), một `DisplayCardView` mỗi màn (icon màn ngoài/laptop, tên, dòng phụ `"2560 × 1440 HiDPI · 60 Hz"`, chevron), hàng chip: chip độ phân giải là `Menu` (mục yêu thích có ★ ở trên, rồi tất cả), chip Hz là `Menu`, chip "HiDPI" nổi bật khi mode hiện tại là HiDPI. Lưới công cụ chỉ có ô **Mirror** (menu chọn màn đích / "Tắt mirror"). Footer: "Cài đặt…" (mở Settings window), "Thoát Lumina". Chưa có slider độ sáng/âm lượng, khu màn hình ảo, PIP… (Đợt 2–4).
- [ ] **Step 6:** `DetailView` (bấm thẻ → thay nội dung popover, nút ‹ quay lại) theo artboard `Detail` tab Hiển thị: thanh trượt độ phân giải (ẩn khi `sliderModes.count < 2`; nhả tay mới áp dụng), danh sách mode có dấu ✓ và ★, segmented Hz, segmented xoay (ẩn khi `!canRotate`), công tắc "Màn hình chính", "Mirror sang …". Nút "Thông tin" (Task 7). Chưa có segmented tab vì chỉ có 1 tab.
- [ ] **Step 7:** Thủ công: mở popover, so với thiết kế; đổi 2560×1440 → 3200×1800 qua thanh trượt, thấy hộp xác nhận; gắn sao 2 mode, mở lại app vẫn còn sao.
- [ ] **Step 8:** Commit `feat: popover and display detail UI`.

---

### Task 7: Thông tin màn hình (tính năng 24)

**Files:** Create `Sources/Lumina/UI/InfoView.swift`; Modify `Sources/Lumina/System/DisplayInfoReader.swift`

**Interfaces:**
- Consumes: `DisplaySnapshot`, `diagonalInches`.
- Produces: `struct DisplayDetails { manufacturer: String?; productName: String?; serialString: String?; yearOfManufacture: Int?; vendorHex: String; modelHex: String; diagonal: Double?; nativeResolution: String; maxRefresh: Double; edidUUID: String? }` + `DisplayInfoReader.details(for: DisplaySnapshot) -> DisplayDetails` (đọc IORegistry `IOMobileFramebufferShim`/`AppleCLCD2` khớp theo `DisplayAttributes`; trường nào không đọc được thì `nil` và UI hiện "—").

- [ ] **Step 1:** Cài đặt reader + `InfoView` (danh sách nhãn/giá trị kiểu bảng, nút "Sao chép" chép toàn bộ ra clipboard dạng văn bản).
- [ ] **Step 2:** Thủ công: Kuycon hiện hãng, model, 27", độ phân giải gốc 5120 × 2880, Hz tối đa; màn tích hợp hiện "Liquid Retina XDR" hoặc tên từ IORegistry.
- [ ] **Step 3:** Commit `feat: display info`.

---

### Task 8: Phím tắt toàn cục, cửa sổ Cài đặt, khởi động cùng máy (tính năng 28, 31)

**Files:** Create `Sources/LuminaCore/KeyCombo.swift`, `Sources/Lumina/System/HotKeyCenter.swift`, `LoginItem.swift`, `Sources/Lumina/UI/SettingsWindow.swift`; Test `Tests/LuminaCoreTests/KeyComboTests.swift`

**Interfaces:**
- Produces:
  - `public struct KeyCombo: Hashable, Codable, Sendable { keyCode: UInt32; modifiers: Modifiers /* OptionSet: control, option, shift, command */; var description: String; var isValidGlobal: Bool }` — thứ tự ký hiệu `⌃⌥⇧⌘`; tên phím có bảng cho A–Z, 0–9, F1–F12, ←→↑↓, Space; `isValidGlobal` = có ít nhất 1 modifier, hoặc là F1–F12.
  - `enum HotKeyAction: String, Codable, CaseIterable { case openPopover, nextResolution, previousResolution, toggleMirror }` với nhãn tiếng Việt: "Mở Lumina", "Độ phân giải lớn hơn", "Độ phân giải nhỏ hơn", "Bật/tắt mirror". Hai lệnh độ phân giải áp lên màn đang chứa con trỏ, đi theo `sliderModes`.
  - `final class HotKeyCenter { func register(_ combo: KeyCombo, for action: HotKeyAction) -> Result<Void, HotKeyError>; func unregister(_ action: HotKeyAction) }` — `HotKeyError.inUse` khi `RegisterEventHotKey` trả `eventHotKeyExistsErr`, `.invalid` khi `!isValidGlobal`. Lưu bindings `~/Library/Application Support/Lumina/hotkeys.json`.
  - `LoginItem.isEnabled: Bool { get set }` qua `SMAppService.mainApp`.

- [ ] **Step 1: Test**

```swift
@Test func describesInMacOrder() {
  #expect(KeyCombo(keyCode: 18 /* 1 */, modifiers: [.command, .option]).description == "⌥⌘1")
  #expect(KeyCombo(keyCode: 0 /* A */, modifiers: [.shift, .control]).description == "⌃⇧A")
}
@Test func plainLetterIsNotValidGlobalButF5Is() {   // Review Focus 5
  #expect(!KeyCombo(keyCode: 0, modifiers: []).isValidGlobal)
  #expect(KeyCombo(keyCode: 96 /* F5 */, modifiers: []).isValidGlobal)
}
@Test func roundTripsThroughJSON() throws {
  let k = KeyCombo(keyCode: 18, modifiers: [.command, .option])
  #expect(try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(k)) == k)
}
```

- [ ] **Step 2:** Chạy → FAIL. **Step 3:** Cài đặt `KeyCombo`. **Step 4:** Chạy → PASS.
- [ ] **Step 5:** `SettingsWindow` (SwiftUI `Window(id: "settings")`, 960×640) theo artboard `Settings`: sidebar chỉ gồm các mục đã làm — **Chung** (công tắc "Khởi động cùng máy", phiên bản) và **Phím tắt** (mỗi `HotKeyAction` một hàng với ô ghi phím; bấm vào → chờ tổ hợp qua `NSEvent.addLocalMonitorForEvents(.keyDown)`; lỗi hiện chữ đỏ "Phím tắt này đang được dùng" / "Cần ít nhất một phím ⌘ ⌥ ⌃ ⇧"; nút xoá). Các mục khác thêm ở đợt sau. Mở cửa sổ phải `NSApp.activate()` vì app là `LSUIElement`.
- [ ] **Step 6:** Thủ công: gán ⌥⌘= / ⌥⌘- cho độ phân giải lớn/nhỏ, bấm khi con trỏ ở Kuycon → đổi mode + hộp xác nhận; thử gán phím trùng (⌘Space) → báo lỗi. Bật "Khởi động cùng máy" từ `~/Applications/Lumina.app` → xuất hiện trong System Settings › General › Login Items.
- [ ] **Step 7:** Commit `feat: global hotkeys, settings window, launch at login`.

---

### Task 9: Kiểm tra toàn bộ Đợt 1 trên máy thật

- [ ] **Step 1:** `swift test` → toàn bộ PASS. `scripts/bundle.sh --install && open ~/Applications/Lumina.app`.
- [ ] **Step 2:** Đi qua bảng kiểm, ghi kết quả vào `docs/superpowers/plans/2026-11-02-lumina-phase1-results.md`: mỗi tính năng 3, 4, 5, 7, 21, 24, 28, 31 trên MacBook và Kuycon → Đạt / Lỗi (mô tả).
- [ ] **Step 3:** Rút cáp Kuycon khi đang đếm ngược hoàn tác → app không crash, panel đóng (Review Focus 1). Cắm lại → thẻ Kuycon hiện lại trong ≤ 1 giây.
- [ ] **Step 4:** `top -l 2 -pid $(pgrep -x Lumina) -stats cpu` khi rảnh → < 1%.
- [ ] **Step 5:** Commit `docs: phase 1 verification results`.
