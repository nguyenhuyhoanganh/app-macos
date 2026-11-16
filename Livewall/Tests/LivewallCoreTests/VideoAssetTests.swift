import AVFoundation
import Foundation
import Testing
@testable import LivewallCore

/// The fixture's audio runs 0.2 s past its video, as many exported clips do.
@MainActor
struct VideoAssetTests {
    private let url = Bundle.module.url(forResource: "Fixtures/audio-longer-than-video", withExtension: "mp4")!

    private func videoEnd(of asset: AVAsset) async throws -> Double {
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        return try await track.load(.timeRange).end.seconds
    }

    private func sourceVideoEnd() async throws -> Double {
        try await videoEnd(of: AVURLAsset(url: url))
    }

    @Test func silentPlaybackEndsWithTheLastVideoFrame() async throws {
        let asset = await VideoAsset.make(url: url, withAudio: false)
        let duration = try await asset.load(.duration).seconds
        let expected = try await sourceVideoEnd()
        #expect(abs(duration - expected) < 0.001)
    }

    @Test func audiblePlaybackEndsWithTheLastVideoFrame() async throws {
        let asset = await VideoAsset.make(url: url, withAudio: true)
        let duration = try await asset.load(.duration).seconds
        let expected = try await sourceVideoEnd()
        #expect(abs(duration - expected) < 0.001)
    }

    @Test func silentPlaybackHasNoAudioTrack() async throws {
        let asset = await VideoAsset.make(url: url, withAudio: false)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func audiblePlaybackKeepsItsAudioTrack() async throws {
        let asset = await VideoAsset.make(url: url, withAudio: true)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    @Test func aSeparateLoopAudioFileReplacesTheVideosOwnSound() async throws {
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: audio) }
        let end = try await sourceVideoEnd()
        try await AudioLoopRenderer.render(from: url, to: audio, loopDuration: end)

        let asset = await VideoAsset.make(url: url, audioURL: audio, withAudio: true)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let range = try await track.load(.timeRange)
        #expect(abs(range.duration.seconds - end) < 0.001)
    }

    @Test func aLoopAudioFileIsIgnoredWhileSilent() async throws {
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: audio) }
        try await AudioLoopRenderer.render(from: url, to: audio, loopDuration: 0.5)
        let asset = await VideoAsset.make(url: url, audioURL: audio, withAudio: false)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
    }
}
