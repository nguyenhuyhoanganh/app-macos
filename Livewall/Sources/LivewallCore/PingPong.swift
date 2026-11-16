import AVFoundation
import CoreVideo

public enum PingPong {
    /// Source frame indices for a seamless forward-then-back loop. The turning frames
    /// appear once, so playback does not stall on them.
    public static func frameOrder(count: Int, skipping skipped: Int) -> [Int] {
        guard count > 0 else { return [] }
        let first = count - skipped >= 3 ? skipped : 0
        return Array(first..<count) + Array(stride(from: count - 2, to: first, by: -1))
    }
}

public enum PingPongError: Error {
    case noVideoTrack, unreadableFrames, writerRejectedVideo
}

/// Renders the loop to a file because playing long-GOP video backwards live is not
/// smooth; the result then costs the same to play as any other video.
public enum PingPongRenderer {
    /// A clip's first keyframe is visibly sharper than what follows, which would
    /// show as a tick each time the loop turns around.
    private static let skippedFrames = 2
    /// Reversing buffers decoded frames, so this bounds memory: about 300 MB at 4K.
    private static let chunkLength = 24

    public static func render(
        from source: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw PingPongError.noVideoTrack
        }
        let (size, transform, rate, range, dataRate) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .timeRange, .estimatedDataRate
        )
        let frameRate = rate > 0 ? rate : 30
        let frameDuration = CMTime(seconds: 1 / Double(frameRate), preferredTimescale: 60_000)

        try? FileManager.default.removeItem(at: destination)
        let writer = try LoopWriter(
            url: destination,
            size: size,
            transform: transform,
            frameRate: frameRate,
            frameDuration: frameDuration,
            bitRate: max(Int(dataRate), 2_000_000)
        )

        do {
            let estimated = Int((range.duration.seconds * Double(frameRate)).rounded())
            let first = PingPong.frameOrder(count: estimated, skipping: skippedFrames).first ?? 0

            var times: [CMTime] = []
            try readFrames(of: track, in: asset, range: nil) { buffer, time in
                if times.count >= first { try writer.append(buffer) }
                times.append(time)
                progress(Double(writer.written) / Double(max(estimated * 2 - 2, 1)))
            }

            let order = PingPong.frameOrder(count: times.count, skipping: first)
            let backward = Array(order.dropFirst(writer.written))
            for start in stride(from: 0, to: backward.count, by: chunkLength) {
                let chunk = Array(backward[start..<min(start + chunkLength, backward.count)])
                try appendReversed(chunk, times: times, track: track, asset: asset, frameDuration: frameDuration, writer: writer)
                progress(Double(writer.written) / Double(order.count))
            }
            try await writer.finish()
        } catch {
            writer.cancel()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func appendReversed(
        _ indices: [Int],
        times: [CMTime],
        track: AVAssetTrack,
        asset: AVAsset,
        frameDuration: CMTime,
        writer: LoopWriter
    ) throws {
        guard let low = indices.min(), let high = indices.max() else { return }
        let wanted = Dictionary(uniqueKeysWithValues: indices.map { (times[$0], $0) })
        let range = CMTimeRange(start: times[low], end: times[high] + frameDuration)

        var buffers: [Int: CVPixelBuffer] = [:]
        try readFrames(of: track, in: asset, range: range) { buffer, time in
            if let index = wanted[time] { buffers[index] = buffer }
        }
        for index in indices {
            guard let buffer = buffers[index] else { throw PingPongError.unreadableFrames }
            try writer.append(buffer)
        }
    }

    private static func readFrames(
        of track: AVAssetTrack,
        in asset: AVAsset,
        range: CMTimeRange?,
        handle: (CVPixelBuffer, CMTime) throws -> Void
    ) throws {
        let reader = try AVAssetReader(asset: asset)
        if let range { reader.timeRange = range }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? PingPongError.unreadableFrames }

        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            try handle(buffer, CMSampleBufferGetPresentationTimeStamp(sample))
        }
        if reader.status == .failed { throw reader.error ?? PingPongError.unreadableFrames }
    }
}

private final class LoopWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let frameDuration: CMTime
    private(set) var written = 0

    init(
        url: URL,
        size: CGSize,
        transform: CGAffineTransform,
        frameRate: Float,
        frameDuration: CMTime,
        bitRate: Int
    ) throws {
        self.frameDuration = frameDuration
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
            ],
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? PingPongError.writerRejectedVideo }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ buffer: CVPixelBuffer) throws {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error ?? PingPongError.writerRejectedVideo }
            usleep(2_000)
        }
        let time = CMTimeMultiply(frameDuration, multiplier: Int32(written))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw writer.error ?? PingPongError.writerRejectedVideo
        }
        written += 1
    }

    func finish() async throws {
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed { throw writer.error ?? PingPongError.writerRejectedVideo }
    }

    func cancel() {
        writer.cancelWriting()
    }
}
