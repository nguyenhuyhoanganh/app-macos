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
}

@Suite struct DisplayIdentityTests {
    @Test func keyUsesSerialWhenPresent() {
        #expect(DisplayIdentity(vendor: 1, model: 2, serial: 3, unitNumber: 9).key == "1-2-3")
    }

    @Test func twoIdenticalMonitorsWithoutSerialGetDifferentKeys() {
        let a = DisplayIdentity(vendor: 1, model: 2, serial: 0, unitNumber: 4)
        let b = DisplayIdentity(vendor: 1, model: 2, serial: 0, unitNumber: 5)
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
