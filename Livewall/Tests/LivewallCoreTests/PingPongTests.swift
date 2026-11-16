import AVFoundation
import Foundation
import Testing
@testable import LivewallCore

struct PingPongOrderTests {
    @Test func playsForwardThenBackWithoutRepeatingTheTurningFrames() {
        #expect(PingPong.frameOrder(count: 6, skipping: 0) == [0, 1, 2, 3, 4, 5, 4, 3, 2, 1])
    }

    @Test func leadingFramesAreLeftOutOfBothDirections() {
        #expect(PingPong.frameOrder(count: 6, skipping: 2) == [2, 3, 4, 5, 4, 3])
    }

    @Test func aClipTooShortToSkipFramesKeepsThemAll() {
        #expect(PingPong.frameOrder(count: 3, skipping: 2) == [0, 1, 2, 1])
    }

    @Test func aSingleFrameStaysASingleFrame() {
        #expect(PingPong.frameOrder(count: 1, skipping: 2) == [0])
    }

    @Test func noFramesProduceNoOrder() {
        #expect(PingPong.frameOrder(count: 0, skipping: 2).isEmpty)
    }
}

struct WallpaperPlaybackTests {
    private func wallpaper(pingPong: String? = nil) -> Wallpaper {
        Wallpaper(
            name: "a", fileName: "a.mp4", contentHash: "h", duration: 1,
            width: 10, height: 10, hasAudio: true, pingPongFileName: pingPong
        )
    }

    @Test func playsTheOriginalFileByDefault() {
        #expect(wallpaper().playbackFileName == "a.mp4")
    }

    @Test func playsTheRenderedLoopWhenThereIsOne() {
        #expect(wallpaper(pingPong: "a-loop.mp4").playbackFileName == "a-loop.mp4")
    }

    @Test func aRenderedLoopIsSilentUntilItsAudioExists() {
        var item = wallpaper(pingPong: "a-loop.mp4")
        #expect(!item.playsAudio)
        item.pingPongAudioFileName = "a-loop.caf"
        #expect(item.playsAudio)
    }

    @Test func aVideoLoopsContinuouslyByDefault() {
        #expect(wallpaper().loopMode == .continuous)
    }

    @Test func aRenderedLoopPlaysBackAndForth() {
        #expect(wallpaper(pingPong: "a-loop.mp4").loopMode == .backAndForth)
    }

    @Test func aLoopOfAVideoWithoutSoundStaysSilent() {
        var item = wallpaper(pingPong: "a-loop.mp4")
        item.hasAudio = false
        item.pingPongAudioFileName = "a-loop.caf"
        #expect(!item.playsAudio)
    }

    @Test func librariesSavedBeforeThisFeatureStillLoad() throws {
        let json = """
        {"items":[{"id":"7BC5C3E0-E7B6-4172-A15B-6DDFF60AEF54","name":"a","fileName":"a.mp4",
        "contentHash":"h","duration":1,"width":10,"height":10,"hasAudio":true,"tags":[],
        "coverTime":0,"addedAt":0}]}
        """
        let library = try JSONDecoder().decode(WallpaperLibrary.self, from: Data(json.utf8))
        #expect(library.items.first?.playbackFileName == "a.mp4")
    }
}

/// The fixture has 12 video frames, so skipping 2 gives 2...11 then 10...3: 18 frames.
struct PingPongRendererTests {
    private let source = Bundle.module.url(forResource: "Fixtures/audio-longer-than-video", withExtension: "mp4")!

    private func rendered() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try await PingPongRenderer.render(from: source, to: url) { _ in }
        return url
    }

    private func frames(of url: URL) async throws -> [[UInt8]] {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        #expect(reader.startReading())
        var result: [[UInt8]] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let bytes = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
            result.append(Array(UnsafeBufferPointer(start: base, count: bytes)))
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        return result
    }

    private func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0
        for index in stride(from: 0, to: min(a.count, b.count), by: 4) {
            total += abs(Int(a[index]) - Int(b[index]))
        }
        return Double(total) / Double(a.count / 4)
    }

    @Test func containsEachDirectionOnce() async throws {
        let url = try await rendered()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await frames(of: url).count == 18)
    }

    @Test func hasNoAudio() async throws {
        let url = try await rendered()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func theSecondHalfMirrorsTheFirst() async throws {
        let url = try await rendered()
        defer { try? FileManager.default.removeItem(at: url) }
        let all = try await frames(of: url)
        // Output 1 and 17 both show source frame 3; output 9 shows source frame 11.
        let mirrored = difference(all[1], all[17])
        let distant = difference(all[1], all[9])
        #expect(mirrored < distant / 3)
    }

    @Test func aFailedRenderLeavesNoFileBehind() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let missing = URL(fileURLWithPath: "/nonexistent/video.mp4")
        await #expect(throws: (any Error).self) {
            try await PingPongRenderer.render(from: missing, to: url) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
