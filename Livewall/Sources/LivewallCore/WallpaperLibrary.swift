import Foundation

public enum VideoShape: String, Codable, CaseIterable, Sendable {
    case standard, wide, ultrawide, portrait

    public init(width: Int, height: Int) {
        guard width > 0, height > 0 else {
            self = .standard
            return
        }
        let ratio = Double(width) / Double(height)
        switch ratio {
        case ..<1: self = .portrait
        case ..<2: self = .standard
        case ..<2.9: self = .wide
        default: self = .ultrawide
        }
    }
}

public enum LoopMode: Sendable, CaseIterable {
    /// The end jumps back to the start, for motion that only makes sense one way.
    case continuous
    /// Forward then back, which has no jump at all.
    case backAndForth
}

public struct Wallpaper: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var fileName: String
    public var contentHash: String
    public var duration: Double
    public var width: Int
    public var height: Int
    public var hasAudio: Bool
    public var tags: [String]
    public var coverTime: Double
    public var addedAt: Date
    /// The rendered forward-then-back loop, when this video uses one.
    public var pingPongFileName: String?
    /// The loop's sound, crossfaded and kept apart so it never needs a video re-render.
    public var pingPongAudioFileName: String?
    /// Black bars found in the video; nil until it has been checked.
    public var crop: VideoCrop?

    public init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        contentHash: String,
        duration: Double,
        width: Int,
        height: Int,
        hasAudio: Bool,
        tags: [String] = [],
        coverTime: Double = 0,
        addedAt: Date = Date(),
        pingPongFileName: String? = nil,
        pingPongAudioFileName: String? = nil,
        crop: VideoCrop? = nil
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.contentHash = contentHash
        self.duration = duration
        self.width = width
        self.height = height
        self.hasAudio = hasAudio
        self.tags = tags
        self.coverTime = coverTime
        self.addedAt = addedAt
        self.pingPongFileName = pingPongFileName
        self.pingPongAudioFileName = pingPongAudioFileName
        self.crop = crop
    }

    public var shape: VideoShape { VideoShape(width: width, height: height) }
    public var coverFileName: String { "\(id.uuidString).jpg" }
    /// Cropped stills get a new name, so the desktop picks up the change.
    public var stillFileName: String {
        let cropped = crop.map { $0.isEmpty ? "" : "-c" } ?? ""
        return "\(id.uuidString)-\(Int(coverTime * 100))\(cropped).png"
    }
    public var loopMode: LoopMode { pingPongFileName == nil ? .continuous : .backAndForth }
    public var playbackFileName: String { pingPongFileName ?? fileName }
    public var playsAudio: Bool { hasAudio && (pingPongFileName == nil || pingPongAudioFileName != nil) }
}

public struct WallpaperFilter: Equatable, Sendable {
    public var text: String
    public var soundOnly: Bool
    public var shape: VideoShape?

    public init(text: String = "", soundOnly: Bool = false, shape: VideoShape? = nil) {
        self.text = text
        self.soundOnly = soundOnly
        self.shape = shape
    }

    public var isActive: Bool { soundOnly || shape != nil }
}

public enum Tags {
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { seen.insert($0).inserted }
    }
}

public struct WallpaperLibrary: Codable, Equatable, Sendable {
    public private(set) var items: [Wallpaper] = []

    public init() {}

    /// Returns the existing entry when the same video was imported before.
    @discardableResult
    public mutating func add(_ new: Wallpaper) -> Wallpaper {
        if let existing = wallpaper(withHash: new.contentHash) { return existing }
        items.append(new)
        items.sort { $0.addedAt > $1.addedAt }
        return new
    }

    public func wallpaper(withHash hash: String) -> Wallpaper? {
        items.first { $0.contentHash == hash }
    }

    public func wallpaper(id: UUID) -> Wallpaper? {
        items.first { $0.id == id }
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func update(_ wallpaper: Wallpaper) {
        guard let index = items.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        items[index] = wallpaper
    }

    public func filtered(by filter: WallpaperFilter) -> [Wallpaper] {
        let query = Self.normalized(filter.text.trimmingCharacters(in: .whitespacesAndNewlines))
        return items.filter { item in
            if filter.soundOnly && !item.hasAudio { return false }
            if let shape = filter.shape, item.shape != shape { return false }
            guard !query.isEmpty else { return true }
            return ([item.name] + item.tags).contains { Self.normalized($0).contains(query) }
        }
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
