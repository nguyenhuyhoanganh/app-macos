import CoreGraphics
import Testing
@testable import LivewallCore

struct DisplayLayoutTests {
    @Test func aSingleDisplayFillsTheAvailableWidth() {
        let frames = ["a": CGRect(x: 0, y: 0, width: 1000, height: 500)]
        let fitted = DisplayLayout.fit(frames, in: CGSize(width: 100, height: 100))
        #expect(fitted["a"] == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func sideBySideDisplaysKeepTheirArrangement() {
        let frames = [
            "left": CGRect(x: -1000, y: 0, width: 1000, height: 500),
            "right": CGRect(x: 0, y: 0, width: 1000, height: 500),
        ]
        let fitted = DisplayLayout.fit(frames, in: CGSize(width: 100, height: 100))
        #expect(fitted["left"]?.minX == 0)
        #expect(fitted["right"]?.minX == 50)
    }

    @Test func aDisplayAboveInAppKitCoordinatesIsDrawnHigherInTheView() {
        let frames = [
            "bottom": CGRect(x: 0, y: 0, width: 1000, height: 500),
            "top": CGRect(x: 0, y: 500, width: 1000, height: 500),
        ]
        let fitted = DisplayLayout.fit(frames, in: CGSize(width: 100, height: 100))
        #expect(fitted["top"]!.minY < fitted["bottom"]!.minY)
    }

    @Test func noDisplaysProducesNoLayout() {
        #expect(DisplayLayout.fit([:], in: CGSize(width: 10, height: 10)).isEmpty)
    }
}
