import AVFoundation
import Foundation
import Testing
@testable import LivewallCore

struct AudioLoopPlanTests {
    @Test func audioSlightlyLongerThanHalfTheLoopRepeatsTwiceWithAShortOverlap() throws {
        let plan = try #require(AudioLoopPlan.make(audioDuration: 15.09, loopDuration: 29.83))
        #expect(plan.repetitions == 2)
        #expect(abs(plan.overlap - 0.175) < 0.001)
    }

    @Test func repetitionsAlwaysAddUpToTheLoopSoSoundCannotDrift() throws {
        for (audio, loop) in [(15.09, 29.83), (5.0, 30.0), (0.7, 0.75), (40.0, 30.0)] {
            let plan = try #require(AudioLoopPlan.make(audioDuration: audio, loopDuration: loop))
            #expect(abs(Double(plan.repetitions) * plan.stride - loop) < 0.000_001)
        }
    }

    @Test func shortAudioRepeatsEnoughTimesToLeaveNoSilence() throws {
        let plan = try #require(AudioLoopPlan.make(audioDuration: 5, loopDuration: 30))
        #expect(plan.repetitions == 7)
        #expect(plan.stride + plan.overlap <= 5.000_001)
    }

    @Test func audioLongerThanTheLoopUsesAShortFadeInsteadOfAHugeOverlap() throws {
        let plan = try #require(AudioLoopPlan.make(audioDuration: 40, loopDuration: 30))
        #expect(plan.repetitions == 1)
        #expect(plan.overlap == AudioLoopPlan.longestOverlap)
    }

    @Test func audioTooShortToJoinHasNoPlan() {
        #expect(AudioLoopPlan.make(audioDuration: 0.02, loopDuration: 30) == nil)
    }
}

struct AudioLoopMixerTests {
    private func plan(_ audio: Double, _ loop: Double) throws -> AudioLoopPlan {
        try #require(AudioLoopPlan.make(audioDuration: audio, loopDuration: loop))
    }

    @Test func outputIsExactlyOneLoopLong() throws {
        let source = [Float](repeating: 0.5, count: 700 * 2)
        let mixed = AudioLoopMixer.mix(source, channels: 2, sampleRate: 1000, plan: try plan(0.7, 1.2), loopDuration: 1.2)
        #expect(mixed.count == 1200 * 2)
    }

    @Test func aSteadySignalNeverDipsAtAJoinIncludingTheWrapAround() throws {
        let source = [Float](repeating: 0.5, count: 700)
        let mixed = AudioLoopMixer.mix(source, channels: 1, sampleRate: 1000, plan: try plan(0.7, 1.2), loopDuration: 1.2)
        #expect((mixed.min() ?? 0) > 0.49)
    }

    @Test func loudOverlapsAreLimitedInsteadOfClipping() throws {
        let source = [Float](repeating: 1, count: 700)
        let mixed = AudioLoopMixer.mix(source, channels: 1, sampleRate: 1000, plan: try plan(0.7, 1.2), loopDuration: 1.2)
        #expect((mixed.max() ?? 0) <= 1)
    }

    @Test func theEndOfTheSourceIsMixedIntoTheStartOfTheLoop() throws {
        // Only the last samples are non-zero, so anything near position 0 proves the wrap.
        var source = [Float](repeating: 0, count: 700)
        for index in 640..<660 { source[index] = 1 }
        let plan = try plan(0.7, 0.65)
        #expect(plan.repetitions == 1)
        let mixed = AudioLoopMixer.mix(source, channels: 1, sampleRate: 1000, plan: plan, loopDuration: 0.65)
        #expect(mixed[0..<20].contains { $0 > 0 })
    }
}

struct AudioLoopRendererTests {
    private let source = Bundle.module.url(forResource: "Fixtures/audio-longer-than-video", withExtension: "mp4")!

    @Test func writesAudioExactlyAsLongAsTheLoop() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await AudioLoopRenderer.render(from: source, to: url, loopDuration: 0.75)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 0.75) < 0.001)
    }

    @Test func theWrittenAudioIsNotSilent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await AudioLoopRenderer.render(from: source, to: url, loopDuration: 0.75)
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(channel[$1])) }
        #expect(peak > 0.01)
    }

    @Test func aVideoWithoutSoundFailsWithoutLeavingAFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let silent = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: silent) }
        try await PingPongRenderer.render(from: source, to: silent) { _ in }
        await #expect(throws: (any Error).self) {
            try await AudioLoopRenderer.render(from: silent, to: url, loopDuration: 0.75)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
