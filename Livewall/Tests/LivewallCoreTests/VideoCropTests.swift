import CoreGraphics
import Foundation
import Testing
@testable import LivewallCore

struct VideoCropTests {
    /// One frame's brightness per column or row, black for the first `leading` and last `trailing` samples.
    private func profile(_ count: Int, leading: Int, trailing: Int) -> [Double] {
        (0..<count).map { $0 < leading || $0 >= count - trailing ? 1 : 120 }
    }

    private func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        [a.minX - b.minX, a.minY - b.minY, a.width - b.width, a.height - b.height].allSatisfy { abs($0) < 0.001 }
    }

    @Test func barsBakedIntoTheVideoAreMeasuredAsFractions() {
        let crop = BlackBorders.crop(
            columns: [profile(3840, leading: 14, trailing: 14)],
            rows: [profile(2160, leading: 0, trailing: 0)]
        )
        #expect(crop == VideoCrop(left: 14.0 / 3840, right: 14.0 / 3840, top: 0, bottom: 0))
    }

    @Test func aBarMustBeDarkInEverySampledFrame() {
        let crop = BlackBorders.crop(
            columns: [profile(100, leading: 30, trailing: 2), profile(100, leading: 3, trailing: 2)],
            rows: [profile(50, leading: 0, trailing: 0), profile(50, leading: 0, trailing: 0)]
        )
        #expect(crop == VideoCrop(left: 0.03, right: 0.02, top: 0, bottom: 0))
    }

    @Test func aMostlyDarkSideIsTreatedAsSceneNotBar() {
        let crop = BlackBorders.crop(
            columns: [profile(100, leading: 40, trailing: 0)],
            rows: [profile(50, leading: 0, trailing: 0)]
        )
        #expect(crop == .none)
    }

    @Test func noFramesMeansNoCrop() {
        #expect(BlackBorders.crop(columns: [], rows: []) == .none)
    }

    @Test func withoutBarsTheVideoFillsTheScreenCentred() {
        let frame = VideoCrop.none.playerFrame(videoSize: CGSize(width: 3840, height: 2160), in: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        #expect(isClose(frame, CGRect(x: 0, y: 0, width: 2560, height: 1440)))
    }

    @Test func sideBarsArePushedJustPastTheScreenEdges() {
        let crop = VideoCrop(left: 14.0 / 3840, right: 14.0 / 3840, top: 0, bottom: 0)
        let bounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let frame = crop.playerFrame(videoSize: CGSize(width: 3840, height: 2160), in: bounds)
        let scale = 2560 / (3840.0 - 28)
        #expect(abs(frame.width - 3840 * scale) < 0.001)
        #expect(abs(frame.minX + 14 * scale) < 0.001)
        #expect(abs(frame.maxX - (2560 + 14 * scale)) < 0.001)
        #expect(abs(frame.midY - bounds.midY) < 0.001)
    }

    @Test func aTopBarShiftsTheVideoUpBecauseLayersCountFromTheBottom() {
        let crop = VideoCrop(left: 0, right: 0, top: 0.1, bottom: 0)
        let frame = crop.playerFrame(videoSize: CGSize(width: 1000, height: 1000), in: CGRect(x: 0, y: 0, width: 900, height: 900))
        #expect(abs(frame.minY - 0) < 0.001)
        #expect(abs(frame.maxY - 1000) < 0.001)
    }

    @Test func aWiderVideoIsStillCroppedToFillWithoutStretching() {
        let frame = VideoCrop.none.playerFrame(videoSize: CGSize(width: 2000, height: 500), in: CGRect(x: 0, y: 0, width: 1000, height: 500))
        #expect(isClose(frame, CGRect(x: -500, y: 0, width: 2000, height: 500)))
    }

    @Test func aCroppedStillGetsItsOwnFileName() {
        var item = Wallpaper(name: "a", fileName: "a.mp4", contentHash: "h", duration: 1, width: 10, height: 10, hasAudio: false)
        let plain = item.stillFileName
        item.crop = VideoCrop(left: 0.01, right: 0.01, top: 0, bottom: 0)
        #expect(item.stillFileName != plain)
    }

    @Test func libraryEntriesWithoutACropStillDecode() throws {
        let json = #"{"id":"B9826FDE-FD62-4D39-8A50-06E670EDAEE0","name":"a","fileName":"a.mp4","contentHash":"h","duration":1,"width":10,"height":10,"hasAudio":false,"tags":[],"coverTime":0,"addedAt":0}"#
        let item = try JSONDecoder().decode(Wallpaper.self, from: Data(json.utf8))
        #expect(item.crop == nil)
    }
}
