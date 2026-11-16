import AppKit
import AVFoundation
import CryptoKit
import LivewallCore

struct VideoProbe: Sendable {
    var facts: VideoFacts
    var duration: Double
    var hasAudio: Bool
}

enum VideoImporter {
    private static let sampleFractions = [0.05, 0.25, 0.5, 0.75, 0.9]

    static func inspect(_ url: URL) async -> VideoProbe {
        let asset = AVURLAsset(url: url)
        var facts = VideoFacts(isPlayable: false, hasVideoTrack: false, width: 0, height: 0, badFrames: 0)
        guard
            let isPlayable = try? await asset.load(.isPlayable),
            let duration = try? await asset.load(.duration)
        else {
            return VideoProbe(facts: facts, duration: 0, hasAudio: false)
        }
        facts.isPlayable = isPlayable

        let video = try? await asset.loadTracks(withMediaType: .video).first
        let audio = try? await asset.loadTracks(withMediaType: .audio)
        if let video, let (size, transform) = try? await video.load(.naturalSize, .preferredTransform) {
            let oriented = size.applying(transform)
            facts.hasVideoTrack = true
            facts.width = Int(abs(oriented.width))
            facts.height = Int(abs(oriented.height))
        }

        let seconds = duration.seconds
        if facts.isPlayable, facts.hasVideoTrack, seconds > 0 {
            let generator = AVAssetImageGenerator(asset: asset)
            for fraction in sampleFractions {
                let time = CMTime(seconds: seconds * fraction, preferredTimescale: 600)
                if (try? await generator.image(at: time)) == nil { facts.badFrames += 1 }
            }
        }
        return VideoProbe(facts: facts, duration: seconds, hasAudio: audio?.isEmpty == false)
    }

    static func sha256(of url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    static func copyIntoLibrary(_ url: URL, as destination: URL) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.copyItem(at: url, to: destination)
        }.value
    }

    static func frame(of url: URL, at seconds: Double, maxWidth: CGFloat? = nil) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        if let maxWidth { generator.maximumSize = CGSize(width: maxWidth, height: 0) }
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// Samples the same frames as `inspect` at full size, so a bar a few pixels wide is
    /// measured exactly.
    static func crop(of url: URL, duration: Double) async -> VideoCrop {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        var columns: [[Double]] = []
        var rows: [[Double]] = []
        for fraction in sampleFractions {
            let time = CMTime(seconds: duration * fraction, preferredTimescale: 600)
            guard
                let image = try? await generator.image(at: time).image,
                let levels = brightness(of: image)
            else { continue }
            columns.append(levels.columns)
            rows.append(levels.rows)
        }
        return BlackBorders.crop(columns: columns, rows: rows)
    }

    /// Mean brightness of every column and row, top row first.
    private static func brightness(of image: CGImage) -> (columns: [Double], rows: [Double])? {
        let width = image.width
        let height = image.height
        guard
            width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        var columnSums = [Int](repeating: 0, count: width)
        var rows = [Double](repeating: 0, count: height)
        for y in 0..<height {
            let row = data + y * context.bytesPerRow
            var sum = 0
            for x in 0..<width {
                let level = Int(row[x])
                columnSums[x] += level
                sum += level
            }
            rows[y] = Double(sum) / Double(width)
        }
        return (columnSums.map { Double($0) / Double(height) }, rows)
    }

    /// Rounds inward so no sliver of a bar survives.
    static func cropped(_ image: CGImage, by crop: VideoCrop) -> CGImage {
        guard !crop.isEmpty else { return image }
        let width = Double(image.width)
        let height = Double(image.height)
        let minX = (width * crop.left).rounded(.up)
        let maxX = (width * (1 - crop.right)).rounded(.down)
        let minY = (height * crop.top).rounded(.up)
        let maxY = (height * (1 - crop.bottom)).rounded(.down)
        guard maxX > minX, maxY > minY else { return image }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)) ?? image
    }

    static func write(_ image: CGImage, to url: URL, as type: NSBitmapImageRep.FileType) throws {
        let properties: [NSBitmapImageRep.PropertyKey: Any] =
            type == .jpeg ? [.compressionFactor: 0.82] : [:]
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: type, properties: properties) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}
