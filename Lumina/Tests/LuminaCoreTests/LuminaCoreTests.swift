import Foundation
import Testing
@testable import LuminaCore

func m(_ id: Int32, _ w: Int, _ h: Int, hidpi: Bool = false, hz: Double = 60, gui: Bool = true) -> DisplayModeInfo {
    DisplayModeInfo(id: id, width: w, height: h, pixelWidth: hidpi ? w * 2 : w, pixelHeight: hidpi ? h * 2 : h,
                    refreshRate: hz, isUsableForDesktopGUI: gui)
}

@Suite struct ModeCatalogTests {
    @Test func resolutionsDedupedSortedBySizeSkippingNonGUI() {
        let r = ModeCatalog.resolutions([m(1, 2560, 1440, hidpi: true), m(2, 2560, 1440, hidpi: true, hz: 50),
                                         m(3, 1920, 1080), m(4, 640, 480, gui: false), m(5, 1920, 1080, hidpi: true)])
        #expect(r.map(\.label) == ["1920 × 1080", "1920 × 1080", "2560 × 1440"])
        #expect(r.map(\.isHiDPI) == [false, true, true])
    }

    @Test func refreshRatesDescendingUnique() {
        let ms = [m(1, 2560, 1440, hidpi: true, hz: 50), m(2, 2560, 1440, hidpi: true, hz: 60), m(3, 2560, 1440, hidpi: true, hz: 60)]
        #expect(ModeCatalog.refreshRates(for: Resolution(width: 2560, height: 1440, isHiDPI: true), in: ms) == [60, 50])
    }

    @Test func sliderKeepsSameKindAndAspectAsCurrent() {
        let cur = m(1, 2560, 1440, hidpi: true)
        let ms = [cur, m(2, 1920, 1080, hidpi: true), m(3, 1920, 1200, hidpi: true), m(4, 3840, 2160), m(5, 3200, 1800, hidpi: true)]
        #expect(ModeCatalog.sliderModes(ms, current: cur).map(\.label) == ["1920 × 1080", "2560 × 1440", "3200 × 1800"])
    }

    @Test func sliderWithSingleModeHasOneStop() {
        let cur = m(1, 1920, 1080)
        #expect(ModeCatalog.sliderModes([cur], current: cur).count == 1)
    }

    @Test func macBookAspectModesStayOnSlider() {
        // Mode thật của màn 14" (1512×982 hiện tại), 1512×945 là 16:10 nên bị loại.
        let cur = m(54, 1512, 982, hidpi: true, hz: 120)
        let ms = [cur, m(12, 1024, 665, hidpi: true), m(24, 1147, 745, hidpi: true), m(42, 1352, 878, hidpi: true),
                  m(48, 1512, 945, hidpi: true), m(66, 1800, 1169, hidpi: true)]
        #expect(ModeCatalog.sliderModes(ms, current: cur).map(\.label)
                == ["1024 × 665", "1147 × 745", "1352 × 878", "1512 × 982", "1800 × 1169"])
    }

    @Test func listModesDefaultMatchesSliderLargestFirst() {
        // Không lặp 3200×1800 thường + HiDPI như danh sách thô của Kuycon.
        let cur = m(41, 2560, 1440, hidpi: true)
        let ms = [cur, m(42, 2560, 1440), m(46, 3200, 1800, hidpi: true), m(45, 3200, 1800),
                  m(49, 3840, 2160), m(30, 1600, 1200)]
        #expect(ModeCatalog.listModes(ms, current: cur, showAll: false).map(\.label) == ["3200 × 1800", "2560 × 1440"])
        #expect(ModeCatalog.listModes(ms, current: cur, showAll: true).count == 6)
    }

    @Test func bestModePrefersRequestedRefreshElseHighest() {
        let ms = [m(1, 2560, 1440, hidpi: true, hz: 50), m(2, 2560, 1440, hidpi: true, hz: 60)]
        let r = Resolution(width: 2560, height: 1440, isHiDPI: true)
        #expect(ModeCatalog.bestMode(for: r, preferredRefresh: 50, in: ms)?.id == 1)
        #expect(ModeCatalog.bestMode(for: r, preferredRefresh: 75, in: ms)?.id == 2)
    }

    // MARK: Công tắc HiDPI

    @Test func hidpiOffKeepsSameSizeWhenAvailable() {
        let cur = m(41, 2560, 1440, hidpi: true)
        let ms = [cur, m(42, 2560, 1440), m(45, 3200, 1800), m(30, 1920, 1080)]
        #expect(ModeCatalog.hidpiCounterpart(ms, current: cur, hidpi: false)
                == Resolution(width: 2560, height: 1440, isHiDPI: false))
    }

    @Test func hidpiOnPicksNearestSizeOfSameAspect() {
        // Màn 4K đang 3840×2160 thường: không có 3840×2160 HiDPI → lấy mức HiDPI cùng tỉ lệ gần nhất.
        let cur = m(49, 3840, 2160)
        let ms = [cur, m(41, 2560, 1440, hidpi: true), m(46, 3200, 1800, hidpi: true),
                  m(20, 1920, 1200, hidpi: true), m(21, 2880, 1800, hidpi: true)]
        #expect(ModeCatalog.hidpiCounterpart(ms, current: cur, hidpi: true)
                == Resolution(width: 3200, height: 1800, isHiDPI: true))
    }

    @Test func hidpiFallsBackToNearestSizeOfAnyAspect() {
        let cur = m(1, 1600, 1200)
        let ms = [cur, m(2, 1920, 1080, hidpi: true), m(3, 1280, 720, hidpi: true)]
        #expect(ModeCatalog.hidpiCounterpart(ms, current: cur, hidpi: true)?.label == "1920 × 1080")
    }

    @Test func hidpiNoChangeWhenAlreadyInRequestedKindOrNoModes() {
        let cur = m(1, 1920, 1080, hidpi: true)
        #expect(ModeCatalog.hidpiCounterpart([cur, m(2, 1920, 1080)], current: cur, hidpi: true) == nil)
        #expect(ModeCatalog.hidpiCounterpart([cur, m(3, 1280, 720, hidpi: true)], current: cur, hidpi: false) == nil)
        // Mode không dùng cho desktop không được tính
        #expect(ModeCatalog.hidpiCounterpart([cur, m(4, 1920, 1080, gui: false)], current: cur, hidpi: false) == nil)
    }
}

@Suite struct DisplayIdentityTests {
    @Test func keyWithoutSerialSurvivesRestart() {
        // Kuycon không có serial; sau khi khởi động lại macOS đổi unit number 4 → 3, UUID giữ nguyên.
        let before = DisplayIdentity(vendor: 11961, model: 624, serial: 0, unitNumber: 4, uuid: "2EB97002-0000-0000-0B22-0104B53C2278")
        let after = DisplayIdentity(vendor: 11961, model: 624, serial: 0, unitNumber: 3, uuid: "2EB97002-0000-0000-0B22-0104B53C2278")
        #expect(before.key == after.key)
        #expect(before.legacyKey == "11961-624-u4")
        #expect(after.legacyKey.hasPrefix(before.legacyKeyPrefix))
    }

    @Test func keyUsesSerialWhenPresent() {
        #expect(DisplayIdentity(vendor: 1, model: 2, serial: 3, unitNumber: 9).key == "1-2-3")
    }

    @Test func twoIdenticalMonitorsWithoutSerialGetDifferentKeys() {
        let a = DisplayIdentity(vendor: 1, model: 2, serial: 0, unitNumber: 4, uuid: "AAAA")
        let b = DisplayIdentity(vendor: 1, model: 2, serial: 0, unitNumber: 5, uuid: "BBBB")
        #expect(a.key != b.key)
    }

    @Test func diagonalOf27InchPanel() {
        #expect(abs(diagonalInches(widthMM: 597, heightMM: 336) - 27.0) < 0.1)
    }

    @Test func kuyconVendorCode() {
        // CGDisplayVendorNumber của Kuycon P27G = 11961 = 0x2EB9.
        #expect(DisplayIdentity(vendor: 11961, model: 624, serial: 0, unitNumber: 4).vendorCode == "KUY")
        #expect(EDID.manufacturerCode(0x0610) == "APP")
    }

    @Test func edidUUIDGivesVendorAndProduct() {
        let vp = EDID.vendorProduct(fromUUID: "2EB97002-0000-0000-1B23-0104B53C2278")
        #expect(vp?.vendor == 11961)
        #expect(vp?.product == 624)
    }
}

@Suite struct DDCMatcherTests {
    @Test func matchesKuyconByEDID() {
        let displays = [DDCMatcher.Display(id: 5, vendor: 11961, model: 624)]
        let services = [DDCMatcher.Service(index: 0, edidUUID: "2EB97002-0000-0000-1B23-0104B53C2278")]
        #expect(DDCMatcher.match(displays: displays, services: services) == [5: 0])
    }

    @Test func singleLeftoverPairsWithoutEDID() {
        let displays = [DDCMatcher.Display(id: 7, vendor: 1, model: 2)]
        let services = [DDCMatcher.Service(index: 3, edidUUID: nil)]
        #expect(DDCMatcher.match(displays: displays, services: services) == [7: 3])
    }

    @Test func ambiguousLeftoversStayUnmatched() {
        let displays = [DDCMatcher.Display(id: 7, vendor: 1, model: 2), DDCMatcher.Display(id: 8, vendor: 1, model: 2)]
        let services = [DDCMatcher.Service(index: 0, edidUUID: nil), DDCMatcher.Service(index: 1, edidUUID: nil)]
        #expect(DDCMatcher.match(displays: displays, services: services).isEmpty)
    }
}

@Suite struct DDCPacketTests {
    @Test func getBrightnessRequest() {
        // 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
        #expect(DDCPacket.getRequest(0x10) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func setBrightnessRequest() {
        let p = DDCPacket.setRequest(0x10, value: 50)
        #expect(Array(p.prefix(5)) == [0x84, 0x03, 0x10, 0x00, 0x32])
        #expect(p[5] == 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32)
    }

    @Test func parsesRealKuyconReply() {
        // Trả lời thật của Kuycon P27G: độ sáng phần cứng 6/100.
        let r: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x06, 0xC6]
        #expect(DDCPacket.parseReply(r, vcp: 0x10) == .init(current: 6, maximum: 100))
    }

    @Test func rejectsBadChecksumOrWrongVCP() {
        let r: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x06, 0xC7]
        #expect(DDCPacket.parseReply(r, vcp: 0x10) == nil)
        let ok: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x06, 0xC6]
        #expect(DDCPacket.parseReply(ok, vcp: 0x62) == nil)
    }
}

@Suite struct AutoRevertTests {
    @Test func countsDownFrom15() {
        let t0 = Date(timeIntervalSince1970: 0)
        let r = AutoRevert(start: t0)
        #expect(r.remaining(at: t0) == 15)
        #expect(r.remaining(at: t0.addingTimeInterval(3.2)) == 12)
        #expect(!r.isExpired(at: t0.addingTimeInterval(14.9)))
    }

    @Test func expiresAndNeverGoesNegative() {
        let t0 = Date(timeIntervalSince1970: 0)
        let r = AutoRevert(start: t0)
        #expect(r.isExpired(at: t0.addingTimeInterval(15)))
        #expect(r.remaining(at: t0.addingTimeInterval(99)) == 0)
    }
}

@Suite struct PopoverPlacementTests {
    // Toạ độ AppKit (gốc dưới-trái). Kuycon 2560×1440 đặt bên trái màn chính, menu bar cao 33.
    let screen = CGRect(x: -2560, y: -229, width: 2560, height: 1440)
    var visible: CGRect { CGRect(x: -2560, y: -229, width: 2560, height: 1440 - 33) }

    @Test func hangsCenteredUnderIcon() {
        let icon = CGRect(x: -496, y: 1178, width: 34, height: 33)
        let f = PopoverPlacement.frame(anchor: icon, visibleFrame: visible, size: CGSize(width: 380, height: 600))
        #expect(f.midX == icon.midX)
        #expect(f.maxY == icon.minY - PopoverPlacement.gap)
        #expect(f.size == CGSize(width: 380, height: 600))
    }

    @Test func clampedInsideRightEdge() {
        let icon = CGRect(x: -60, y: 1178, width: 34, height: 33)
        let f = PopoverPlacement.frame(anchor: icon, visibleFrame: visible, size: CGSize(width: 380, height: 600))
        #expect(f.maxX == visible.maxX - PopoverPlacement.margin)
    }

    @Test func clampedInsideLeftEdge() {
        let icon = CGRect(x: -2550, y: 1178, width: 34, height: 33)
        let f = PopoverPlacement.frame(anchor: icon, visibleFrame: visible, size: CGSize(width: 380, height: 600))
        #expect(f.minX == visible.minX + PopoverPlacement.margin)
    }

    @Test func tallContentShrinksToFitShortScreen() {
        // Màn tích hợp ở 1024×665: popover không được thò ra khỏi màn.
        let small = CGRect(x: 0, y: 0, width: 1024, height: 665 - 38)
        let icon = CGRect(x: 900, y: 627, width: 34, height: 38)
        let f = PopoverPlacement.frame(anchor: icon, visibleFrame: small, size: CGSize(width: 380, height: 900))
        #expect(f.maxY == icon.minY - PopoverPlacement.gap)
        #expect(f.minY == small.minY + PopoverPlacement.margin)
        #expect(f.height == PopoverPlacement.maxHeight(anchor: icon, visibleFrame: small))
    }

    @Test(arguments: [3545.0, 3900.0, 2600.0])
    func iconOnAnotherMenuBarKeepsDistanceFromRightEdge(iconX: CGFloat) {
        // Kuycon làm màn chính (0…2560, menu bar 30), MacBook bên phải (2560…4072, menu bar có tai thỏ 37);
        // icon thật nằm trên menu bar MacBook, cửa sổ icon thò dưới đáy menu bar 2 pt (như đo thật).
        let kuycon = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let kuyconVisible = CGRect(x: 0, y: 0, width: 2560, height: 1410)
        let mac = CGRect(x: 2560, y: 0, width: 1512, height: 982)
        let macVisible = CGRect(x: 2560, y: 0, width: 1512, height: 945)
        let icon = CGRect(x: iconX, y: 943, width: 38, height: 33)
        let a = PopoverPlacement.mirroredAnchor(icon, from: mac, sourceVisibleFrame: macVisible,
                                                to: kuycon, targetVisibleFrame: kuyconVisible)
        #expect(kuycon.maxX - a.minX == mac.maxX - icon.minX)
        #expect(a.minY == kuyconVisible.maxY - 2)
        #expect(a.size == icon.size)
        // Cùng màn: giữ nguyên.
        #expect(PopoverPlacement.mirroredAnchor(icon, from: mac, sourceVisibleFrame: macVisible,
                                                to: mac, targetVisibleFrame: macVisible) == icon)
        // Menu bar tự ẩn (vùng dùng được tới tận mép trên): bám mép trên như màn nguồn.
        let hidden = PopoverPlacement.mirroredAnchor(icon, from: mac, sourceVisibleFrame: mac,
                                                     to: kuycon, targetVisibleFrame: kuycon)
        #expect(kuycon.maxY - hidden.minY == mac.maxY - icon.minY)
    }

    @Test func iconWithoutScreenIsRejected() {
        // Lúc đổi độ phân giải icon có thể tạm nằm ngoài mọi màn ({2864,110} trong trace).
        #expect(!PopoverPlacement.isUsableAnchor(CGRect(x: 2864, y: 110, width: 34, height: 33), screenFrame: nil))
        #expect(PopoverPlacement.isUsableAnchor(CGRect(x: -496, y: 1178, width: 34, height: 33), screenFrame: screen))
        #expect(!PopoverPlacement.isUsableAnchor(CGRect(x: 0, y: -33, width: 34, height: 33),
                                                 screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
    }
}

@Suite struct ArrangementPlannerTests {
    // Bố cục thật: màn tích hợp 1512×982 là màn chính ở (0,0); Kuycon 2560×1440 bên trái.
    let mac = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let kuy = CGRect(x: -2560, y: -229, width: 2560, height: 1440)

    @Test func dropRightOfMainSnapsToRightEdge() {
        let dropped = CGRect(x: 1600, y: 100, width: 2560, height: 1440)
        let p = ArrangementPlanner.snap(dropped, others: [mac])
        #expect(p.x == mac.maxX)
        #expect(touches(CGRect(origin: p, size: dropped.size), mac))
    }

    @Test func droppedOverlappingIsPushedToNearestFreeEdge() {
        // Thả Kuycon chồng lên gần mép trái màn chính → hít về bên trái, không chồng.
        let dropped = CGRect(x: -2400, y: -200, width: 2560, height: 1440)
        let p = ArrangementPlanner.snap(dropped, others: [mac])
        let r = CGRect(origin: p, size: dropped.size)
        #expect(p.x == -2560)
        #expect(!ArrangementPlanner.overlaps(r, mac))
    }

    @Test func nearTopEdgeAlignsTops() {
        let dropped = CGRect(x: 1520, y: 40, width: 1000, height: 600)
        #expect(ArrangementPlanner.snap(dropped, others: [mac]) == CGPoint(x: 1512, y: 0))
    }

    @Test func farAwayStillTouchesWithMinimumOverlap() {
        // Kéo xuống tít dưới: vị trí hợp lệ gần nhất là bám cạnh dưới màn chính, chung ≥ minOverlap.
        let dropped = CGRect(x: 1512, y: 5000, width: 2560, height: 1440)
        let r = CGRect(origin: ArrangementPlanner.snap(dropped, others: [mac]), size: dropped.size)
        #expect(touches(r, mac))
        #expect(!ArrangementPlanner.overlaps(r, mac))
    }

    /// Chung một đoạn cạnh dài ≥ minOverlap.
    func touches(_ a: CGRect, _ b: CGRect) -> Bool {
        let m = ArrangementPlanner.minOverlap
        let vertical = (a.maxX == b.minX || a.minX == b.maxX) && min(a.maxY, b.maxY) - max(a.minY, b.minY) >= m
        let horizontal = (a.maxY == b.minY || a.minY == b.maxY) && min(a.maxX, b.maxX) - max(a.minX, b.minX) >= m
        return vertical || horizontal
    }

    @Test func threeDisplaysNeverOverlap() {
        let third = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let dropped = CGRect(x: 1400, y: 50, width: 1280, height: 800)   // chồng lên cả mac và third
        let p = ArrangementPlanner.snap(dropped, others: [mac, kuy, third])
        let r = CGRect(origin: p, size: dropped.size)
        #expect(![mac, kuy, third].contains { ArrangementPlanner.overlaps($0, r) })
        #expect([mac, kuy, third].contains { touches(r, $0) })
    }

    @Test func normalizeKeepsMainAtOrigin() {
        let layout: [UInt32: CGRect] = [1: CGRect(x: 100, y: 50, width: 1512, height: 982),
                                        5: CGRect(x: 1612.4, y: 10, width: 2560, height: 1440)]
        let n = ArrangementPlanner.normalize(layout, main: 1)
        #expect(n[1] == .zero)
        #expect(n[5] == CGPoint(x: 1512, y: -40))
    }
}

@Suite struct AspectRatioTests {
    // Mode thật (rút gọn) của Kuycon P27G và MacBook 14".
    let kuycon = [m(1, 1280, 1024), m(2, 1152, 870), m(3, 1600, 1200), m(4, 800, 600, hidpi: true),
                  m(5, 1680, 1050), m(6, 840, 525, hidpi: true), m(7, 2560, 1440, hidpi: true),
                  m(8, 3840, 2160), m(9, 1920, 1080, hidpi: true)]
    let macbook = [m(1, 1512, 982, hidpi: true), m(2, 3024, 1964), m(3, 1512, 945, hidpi: true),
                   m(4, 1147, 716, hidpi: true), m(5, 3024, 1890), m(6, 1800, 1125, hidpi: true)]

    @Test func kuyconGroupsNarrowToWide() {
        #expect(ModeCatalog.aspectGroups(kuycon).map(\.label) == ["5:4", "4:3", "16:10", "16:9"])
    }

    @Test func macbookNativeNotchAspectIsGoc() {
        let groups = ModeCatalog.aspectGroups(macbook)
        #expect(groups.map(\.label) == ["Gốc", "16:10"], "\(groups)")
    }

    @Test func ultrawideLabels() {
        #expect(ModeCatalog.aspectLabel(3440.0 / 1440, native: nil) == "21:9")
        #expect(ModeCatalog.aspectLabel(2560.0 / 1080, native: nil) == "21:9")
        #expect(ModeCatalog.aspectLabel(3840.0 / 1600, native: nil) == "21:9")
        #expect(ModeCatalog.aspectLabel(5120.0 / 1440, native: nil) == "32:9")
        #expect(ModeCatalog.aspectLabel(1.85, native: nil) == "1.85:1")
    }

    @Test func switchingAspectKeepsHeightClose() {
        let cur = m(7, 2560, 1440, hidpi: true)
        let groups = ModeCatalog.aspectGroups(kuycon)
        let g43 = groups.first { $0.label == "4:3" }!
        #expect(ModeCatalog.resolution(for: g43, modes: kuycon, current: cur)?.label == "1600 × 1200")
        let g169 = groups.first { $0.label == "16:9" }!
        #expect(ModeCatalog.resolution(for: g169, modes: kuycon, current: cur) == nil)
    }

    @Test func macbookToSixteenTenPrefersSameKind() {
        let cur = m(1, 1512, 982, hidpi: true)
        let g = ModeCatalog.aspectGroups(macbook).first { $0.label == "16:10" }!
        #expect(ModeCatalog.resolution(for: g, modes: macbook, current: cur)
                == Resolution(width: 1512, height: 945, isHiDPI: true))
    }
}

@Suite struct BrightnessSyncTests {
    @Test func nitsRoundTrip() {
        for p in [NitsProfile.macBookXDR, .kuyconP27G, .externalSoftware] {
            for v in stride(from: 0.0, through: 1.0, by: 0.1) {
                #expect(abs(p.value(forNits: p.nits(at: v)) - v) < 1e-9)
            }
        }
    }

    @Test func macBookCurveIsPerceptual() {
        #expect(NitsProfile.macBookXDR.nits(at: 1) == 600)
        // Nửa thanh trượt ≈ 22% độ sáng thật, không phải 50%.
        #expect(abs(NitsProfile.macBookXDR.nits(at: 0.5) - (1 + 599 * pow(0.5, 2.2))) < 1e-9)
        #expect(NitsProfile.macBookXDR.nits(at: 0.5) < 140)
    }

    @Test func kuyconFollowsMacBookNits() {
        // MacBook 56% ≈ 168 nit → Kuycon (50…500 nit tuyến tính) ≈ 26%.
        let v = BrightnessSync.target(sourceValue: 0.56, source: .macBookXDR, target: .kuyconP27G)
        let nits = NitsProfile.kuyconP27G.nits(at: v)
        #expect(abs(nits - NitsProfile.macBookXDR.nits(at: 0.56)) < 1e-6)
        #expect(v > 0.2 && v < 0.35)
    }

    @Test func clampsWhenTargetCannotGoThatDarkOrBright() {
        #expect(BrightnessSync.target(sourceValue: 0.05, source: .macBookXDR, target: .kuyconP27G) == 0)
        #expect(BrightnessSync.target(sourceValue: 1, source: .macBookXDR, target: .kuyconP27G) == 1)
    }

    @Test func sourceBrighterOrDarkerThanTargetCanReach() {
        // MacBook 100% = 600 nit > Kuycon tối đa 500 → Kuycon kịch max, MacBook vẫn kéo tiếp được.
        #expect(BrightnessSync.limit(sourceValue: 1, source: .macBookXDR, target: .kuyconP27G) == .atMax)
        #expect(BrightnessSync.target(sourceValue: 1, source: .macBookXDR, target: .kuyconP27G) == 1)
        // MacBook rất tối (< 50 nit) → Kuycon đứng ở mức tối nhất.
        #expect(BrightnessSync.limit(sourceValue: 0.2, source: .macBookXDR, target: .kuyconP27G) == .atMin)
        #expect(BrightnessSync.target(sourceValue: 0.2, source: .macBookXDR, target: .kuyconP27G) == 0)
        #expect(BrightnessSync.limit(sourceValue: 0.6, source: .macBookXDR, target: .kuyconP27G) == .none)
    }

    @Test func draggingToTheEndsIsNotCalibration() {
        #expect(!BrightnessSync.isCalibrationDrag(1))
        #expect(!BrightnessSync.isCalibrationDrag(0))
        #expect(BrightnessSync.isCalibrationDrag(0.4))
    }

    @Test func manualAdjustmentBecomesRelativeOffset() {
        // Đang đồng bộ, người dùng kéo Kuycon sáng hơn cho khớp mắt → lần sau vẫn giữ độ lệch đó.
        var kuy = NitsProfile.kuyconP27G
        kuy.ratio = BrightnessSync.ratio(sourceValue: 0.56, source: .macBookXDR, targetValue: 0.4, target: kuy)
        #expect(kuy.ratio > 1)
        #expect(abs(BrightnessSync.target(sourceValue: 0.56, source: .macBookXDR, target: kuy) - 0.4) < 1e-9)
    }

    @Test func defaultsByDisplay() {
        #expect(NitsProfile.defaults(name: "Kuycon P27G", isBuiltIn: false, hardwareControl: true) == .kuyconP27G)
        #expect(NitsProfile.defaults(name: "Built-in Liquid Retina XDR Display", isBuiltIn: true, hardwareControl: false) == .macBookXDR)
        #expect(NitsProfile.defaults(name: "Built-in Liquid Retina Display", isBuiltIn: true, hardwareControl: false) == .builtIn)
        // MacBook Pro M5 Pro thật: macOS gọi là "Built-in Retina Display" nhưng khoảng HDR 16× → XDR 600 nit.
        #expect(NitsProfile.defaults(name: "Built-in Retina Display", isBuiltIn: true, hardwareControl: false, hdrHeadroom: 16) == .macBookXDR)
        #expect(NitsProfile.defaults(name: "Built-in Retina Display", isBuiltIn: true, hardwareControl: false, hdrHeadroom: 1) == .builtIn)
        #expect(NitsProfile.defaults(name: "DELL U2720Q", isBuiltIn: false, hardwareControl: true) == .externalDDC)
    }
}

@Suite struct TopCutoutTests {
    @Test func macBookProNotchFromSystemValues() {
        // Số thật của MacBook Pro 14″ M5 Pro: safeTop 32, hai bên tai thỏ 663.5, ngang 1512.
        let c = TopCutout.detect(safeAreaTop: 32, leftArea: 663.5, rightArea: 663.5, screenWidth: 1512,
                                 name: "Built-in Retina Display")
        guard case .notch(let w) = c else { Issue.record("cần tai thỏ, ra \(c)"); return }
        #expect(abs(w - 185.0 / 1512) < 1e-9)
    }

    @Test func externalAndNoNotchDisplays() {
        #expect(TopCutout.detect(safeAreaTop: 0, leftArea: nil, rightArea: nil, screenWidth: 2560, name: "Kuycon P27G") == .none)
        #expect(TopCutout.detect(safeAreaTop: 0, leftArea: nil, rightArea: nil, screenWidth: 1440, name: "Built-in Display") == .none)
    }

    @Test func oledProGetsDynamicIsland() {
        let c = TopCutout.detect(safeAreaTop: 34, leftArea: 690, rightArea: 690, screenWidth: 1512,
                                 name: "Built-in PROLED XDR Display")
        guard case .island = c else { Issue.record("cần Dynamic Island, ra \(c)"); return }
    }

    @Test func missingSideAreasFallBackToTypicalWidth() {
        #expect(TopCutout.detect(safeAreaTop: 32, leftArea: nil, rightArea: nil, screenWidth: 1512, name: "x") == .notch(width: 0.12))
    }
}
