import Foundation

public struct StorageListing: Equatable, Sendable {
    public var videos: [String]
    public var covers: [String]
    public var stills: [String]

    public init(videos: [String] = [], covers: [String] = [], stills: [String] = []) {
        self.videos = videos
        self.covers = covers
        self.stills = stills
    }

    public var isEmpty: Bool { videos.isEmpty && covers.isEmpty && stills.isEmpty }
}

public enum StorageAudit {
    /// Rendered files can always be made again; imported originals may be the only copy.
    public static func isRendered(_ fileName: String) -> Bool {
        fileName.contains("-loop.")
    }

    /// Files on disk that the library no longer refers to. Interrupted renders and
    /// failed imports end up here. `keeping` protects names in use elsewhere, such as
    /// the picture currently set on the desktop.
    public static func orphans(
        in listing: StorageListing,
        library: WallpaperLibrary,
        keeping protected: Set<String> = []
    ) -> StorageListing {
        var videos = protected
        var covers = protected
        var stills = protected
        for item in library.items {
            videos.formUnion([item.fileName, item.pingPongFileName, item.pingPongAudioFileName].compactMap { $0 })
            covers.insert(item.coverFileName)
            stills.insert(item.stillFileName)
        }
        return StorageListing(
            videos: listing.videos.filter { !videos.contains($0) },
            covers: listing.covers.filter { !covers.contains($0) },
            stills: listing.stills.filter { !stills.contains($0) }
        )
    }
}

public enum DiskSpace {
    /// Left free so filling the library can never run the disk out completely.
    private static let reserve: Int64 = 1_000_000_000

    public static func hasRoom(for size: Int64, available: Int64) -> Bool {
        size + reserve <= available
    }

    /// Forward plus backward at the source bitrate, with margin for the sound and
    /// for the encoder overshooting.
    public static func estimatedLoopSize(ofVideo size: Int64) -> Int64 {
        size * 5 / 2
    }
}
