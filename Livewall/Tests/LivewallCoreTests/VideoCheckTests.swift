import Testing
@testable import LivewallCore

struct VideoCheckTests {
    private let good = VideoFacts(isPlayable: true, hasVideoTrack: true, width: 1920, height: 1080, badFrames: 0)

    @Test func aHealthyHDVideoIsAcceptedWithoutWarning() {
        #expect(VideoCheck.evaluate(good) == .accepted(warning: nil))
    }

    @Test func anUnplayableFileIsRejected() {
        var facts = good
        facts.isPlayable = false
        #expect(VideoCheck.evaluate(facts) == .rejected(.unsupportedFormat))
    }

    @Test func aFileWithoutVideoIsRejected() {
        var facts = good
        facts.hasVideoTrack = false
        #expect(VideoCheck.evaluate(facts) == .rejected(.noVideoTrack))
    }

    @Test func corruptedFramesAreRejected() {
        var facts = good
        facts.badFrames = 1
        #expect(VideoCheck.evaluate(facts) == .rejected(.corruptedFrames))
    }

    @Test func lowResolutionIsAcceptedWithAWarning() {
        var facts = good
        facts.width = 640
        facts.height = 360
        #expect(VideoCheck.evaluate(facts) == .accepted(warning: .lowResolution))
    }

    @Test func portraitHDIsNotLowResolution() {
        var facts = good
        facts.width = 1080
        facts.height = 1920
        #expect(VideoCheck.evaluate(facts) == .accepted(warning: nil))
    }
}
