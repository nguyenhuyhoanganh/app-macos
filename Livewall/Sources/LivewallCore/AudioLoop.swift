import AVFoundation

/// How a clip's sound repeats inside a loop so it always comes out the same length
/// as the picture and cannot drift against it.
public struct AudioLoopPlan: Equatable, Sendable {
    public static let shortestOverlap = 0.05
    public static let longestOverlap = 0.5

    public let repetitions: Int
    public let stride: Double
    public let overlap: Double

    public static func make(audioDuration: Double, loopDuration: Double) -> AudioLoopPlan? {
        guard loopDuration > 0, audioDuration > shortestOverlap * 2 else { return nil }
        let usable = audioDuration - shortestOverlap
        let repetitions = max(1, Int((loopDuration / usable - 1e-9).rounded(.up)))
        let stride = loopDuration / Double(repetitions)
        let overlap = min(audioDuration - stride, longestOverlap, stride)
        return AudioLoopPlan(repetitions: repetitions, stride: stride, overlap: overlap)
    }
}

public enum AudioLoopMixer {
    /// Lays the repetitions end to end, overlapping each join on an equal-power curve.
    /// The last join wraps onto the start, so the output itself loops seamlessly.
    public static func mix(
        _ source: [Float],
        channels: Int,
        sampleRate: Double,
        plan: AudioLoopPlan,
        loopDuration: Double
    ) -> [Float] {
        let total = Int((loopDuration * sampleRate).rounded())
        let overlap = Int((plan.overlap * sampleRate).rounded())
        let sourceFrames = source.count / channels
        var mixed = [Float](repeating: 0, count: total * channels)
        guard total > 0 else { return mixed }

        for repetition in 0..<plan.repetitions {
            let start = total * repetition / plan.repetitions
            let next = total * (repetition + 1) / plan.repetitions
            let segment = min(next - start + overlap, sourceFrames)
            for frame in 0..<segment {
                let gain = gain(at: frame, of: segment, overlap: overlap)
                let position = (start + frame) % total
                for channel in 0..<channels {
                    mixed[position * channels + channel] += source[frame * channels + channel] * gain
                }
            }
        }
        return mixed.map { min(max($0, -1), 1) }
    }

    private static func gain(at frame: Int, of segment: Int, overlap: Int) -> Float {
        guard overlap > 0 else { return 1 }
        if frame < overlap {
            return sin(.pi / 2 * (Float(frame) + 0.5) / Float(overlap))
        }
        if frame >= segment - overlap {
            return cos(.pi / 2 * (Float(frame - (segment - overlap)) + 0.5) / Float(overlap))
        }
        return 1
    }
}

public enum AudioLoopError: Error {
    case noAudioTrack, audioTooShort, unreadableAudio
}

/// Writes PCM rather than AAC: AAC's encoder delay would leave a tiny gap at the join.
public enum AudioLoopRenderer {
    private static let sampleRate = 48_000.0
    private static let channels = 2

    public static func render(from source: URL, to destination: URL, loopDuration: Double) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioLoopError.noAudioTrack
        }
        let samples = try readSamples(of: track, in: asset)
        let duration = Double(samples.count / channels) / sampleRate
        guard let plan = AudioLoopPlan.make(audioDuration: duration, loopDuration: loopDuration) else {
            throw AudioLoopError.audioTooShort
        }
        let mixed = AudioLoopMixer.mix(
            samples, channels: channels, sampleRate: sampleRate, plan: plan, loopDuration: loopDuration
        )
        try? FileManager.default.removeItem(at: destination)
        try write(mixed, to: destination)
    }

    private static func readSamples(of track: AVAssetTrack, in asset: AVAsset) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? AudioLoopError.unreadableAudio }

        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = chunk.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw AudioLoopError.unreadableAudio }
            samples += chunk
        }
        if reader.status == .failed { throw reader.error ?? AudioLoopError.unreadableAudio }
        return samples
    }

    private static func write(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { file.close() }
        let frames = samples.count / channels
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)),
            let data = buffer.floatChannelData
        else { throw AudioLoopError.unreadableAudio }
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            for channel in 0..<channels {
                data[channel][frame] = samples[frame * channels + channel]
            }
        }
        try file.write(from: buffer)
    }
}
