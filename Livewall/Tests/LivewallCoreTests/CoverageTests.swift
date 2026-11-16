import CoreGraphics
import Testing
@testable import LivewallCore

struct CoverageTests {
    private let screen = CGRect(x: 0, y: 25, width: 1000, height: 600)

    @Test func noWindowsLeaveTheDesktopVisible() {
        #expect(!Coverage.isCovered(screen, by: []))
    }

    @Test func oneWindowOverTheWholeAreaCoversIt() {
        #expect(Coverage.isCovered(screen, by: [screen]))
    }

    @Test func aWindowLargerThanTheAreaCoversIt() {
        #expect(Coverage.isCovered(screen, by: [screen.insetBy(dx: -50, dy: -50)]))
    }

    @Test func aMediumWindowDoesNotCoverTheArea() {
        let window = CGRect(x: 200, y: 100, width: 600, height: 400)
        #expect(!Coverage.isCovered(screen, by: [window]))
    }

    @Test func twoWindowsSideBySideCoverTheArea() {
        let left = CGRect(x: 0, y: 25, width: 500, height: 600)
        let right = CGRect(x: 500, y: 25, width: 500, height: 600)
        #expect(Coverage.isCovered(screen, by: [left, right]))
    }

    @Test func aStripOfDesktopAlongOneEdgeCountsAsVisible() {
        let window = CGRect(x: 0, y: 25, width: 900, height: 600)
        #expect(!Coverage.isCovered(screen, by: [window]))
    }

    @Test func aWindowOnAnotherDisplayDoesNotCoverThisOne() {
        let elsewhere = CGRect(x: 1000, y: 0, width: 1000, height: 700)
        #expect(!Coverage.isCovered(screen, by: [elsewhere]))
    }

    @Test func anEmptyAreaIsNeverCovered() {
        #expect(!Coverage.isCovered(.zero, by: [screen]))
    }
}
