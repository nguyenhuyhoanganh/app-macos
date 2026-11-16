import Testing
@testable import LivewallCore

struct ShelfScrollTests {
    /// Eleven 156-point items in an 884-point strip, as on the 1040-point window.
    private let strip = ShelfScroll(contentWidth: 1716, visibleWidth: 884)

    @Test func atTheStartOnlyTheNextButtonShows() {
        let edges = strip.edges(at: 0)
        #expect(edges.hasEarlier == false)
        #expect(edges.hasLater == true)
    }

    @Test func inTheMiddleBothButtonsShow() {
        let edges = strip.edges(at: 400)
        #expect(edges.hasEarlier && edges.hasLater)
    }

    @Test func atTheEndOnlyThePreviousButtonShows() {
        let edges = strip.edges(at: 832)
        #expect(edges.hasEarlier == true)
        #expect(edges.hasLater == false)
    }

    @Test func aStripThatFitsShowsNoButtons() {
        let edges = ShelfScroll(contentWidth: 600, visibleWidth: 884).edges(at: 0)
        #expect(!edges.hasEarlier && !edges.hasLater)
    }

    @Test func aPageMovesMostOfTheVisibleWidthAndStopsAtTheEnds() {
        #expect(strip.page(from: 0, forward: true) == 884 * 0.8)
        #expect(strip.page(from: 800, forward: true) == 832)
        #expect(strip.page(from: 100, forward: false) == 0)
    }

    @Test func aMouseWheelTurnsVerticalScrollingSideways() {
        #expect(strip.wheel(from: 100, deltaX: 0, deltaY: -3, isPrecise: false) == 100 + 3 * ShelfScroll.pointsPerLine)
        #expect(strip.wheel(from: 100, deltaX: 0, deltaY: 30, isPrecise: true) == 70)
    }

    @Test func wheelScrollingStopsAtTheEnds() {
        #expect(strip.wheel(from: 10, deltaX: 0, deltaY: 50, isPrecise: true) == 0)
        #expect(strip.wheel(from: 820, deltaX: 0, deltaY: -50, isPrecise: true) == 832)
    }

    @Test func sidewaysTrackpadSwipesAreLeftToTheScrollView() {
        #expect(strip.wheel(from: 100, deltaX: -20, deltaY: 4, isPrecise: true) == nil)
    }

    @Test func aStripThatFitsIgnoresTheWheel() {
        #expect(ShelfScroll(contentWidth: 600, visibleWidth: 884).wheel(from: 0, deltaX: 0, deltaY: -3, isPrecise: false) == nil)
    }
}
