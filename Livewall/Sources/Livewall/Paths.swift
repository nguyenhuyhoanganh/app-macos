import Foundation

enum Paths {
    static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["LIVEWALL_HOME"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Livewall", isDirectory: true)
    }()

    static let videos = root.appendingPathComponent("Videos", isDirectory: true)
    static let covers = root.appendingPathComponent("Covers", isDirectory: true)
    static let desktopImages = root.appendingPathComponent("Desktop", isDirectory: true)
    static let library = root.appendingPathComponent("library.json")
    static let state = root.appendingPathComponent("state.json")

    static func prepare() {
        for directory in [videos, covers, desktopImages] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
