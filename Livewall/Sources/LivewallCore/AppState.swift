import Foundation

public struct DisplayConfig: Codable, Equatable, Sendable {
    public var wallpaperID: UUID?
    public var isEnabled = true
    public var volume = 0.0
    /// The desktop picture that was set before Livewall replaced it.
    public var systemImage: URL?

    public init() {}

    public var isActive: Bool { wallpaperID != nil && isEnabled }
}

public struct AppState: Codable, Equatable, Sendable {
    public var displays: [String: DisplayConfig] = [:]
    public var energy = EnergySettings()
    public var hidesDesktopIcons = false
    public var hidesMenuBarIcon = false

    public init() {}

    public func config(for display: String) -> DisplayConfig {
        displays[display] ?? DisplayConfig()
    }

    public mutating func assign(_ wallpaper: UUID, to display: String, previousSystemImage: URL?) {
        var config = config(for: display)
        if config.wallpaperID == nil { config.systemImage = previousSystemImage }
        config.wallpaperID = wallpaper
        config.isEnabled = true
        displays[display] = config
    }

    /// Returns the desktop picture to put back, if one was remembered.
    @discardableResult
    public mutating func clear(_ display: String) -> URL? {
        var config = config(for: display)
        let restored = config.systemImage
        config.wallpaperID = nil
        config.systemImage = nil
        displays[display] = config
        return restored
    }

    /// Clears every display showing the wallpaper and returns the pictures to restore.
    public mutating func removeWallpaper(_ wallpaper: UUID) -> [String: URL] {
        var restored: [String: URL] = [:]
        for display in displays.keys where displays[display]?.wallpaperID == wallpaper {
            if let image = clear(display) { restored[display] = image }
        }
        return restored
    }

    /// Displays Livewall has never seen take the wallpaper of the first connected display
    /// that has one, so plugging in a monitor shows motion without setup. A display whose
    /// wallpaper the user removed keeps its entry and stays empty.
    public func adoption(connected: [String]) -> (wallpaper: UUID, displays: [String])? {
        let unseen = connected.filter { displays[$0] == nil }
        let sources = connected + displays.keys.sorted()
        guard
            !unseen.isEmpty,
            let wallpaper = sources.lazy.compactMap({ self.displays[$0]?.wallpaperID }).first
        else { return nil }
        return (wallpaper, unseen)
    }

    public mutating func setVolume(_ volume: Double, for display: String) {
        var config = config(for: display)
        config.volume = min(max(volume, 0), 1)
        displays[display] = config
    }

    public mutating func setEnabled(_ isEnabled: Bool, for display: String) {
        var config = config(for: display)
        config.isEnabled = isEnabled
        displays[display] = config
    }
}

public struct JSONStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
