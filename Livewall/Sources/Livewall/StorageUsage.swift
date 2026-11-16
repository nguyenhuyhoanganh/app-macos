import Foundation
import LivewallCore

struct StorageUsage: Sendable {
    let total: Int64
    let rendered: Int64

    var totalText: String { Self.text(total) }
    var renderedText: String? { rendered > 0 ? Self.text(rendered) : nil }

    static func measure(library: WallpaperLibrary) -> StorageUsage {
        var total: Int64 = 0
        var rendered: Int64 = 0
        let files = FileManager.default.enumerator(at: Paths.root, includingPropertiesForKeys: [.fileSizeKey])
        while let url = files?.nextObject() as? URL {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            total += size
            if StorageAudit.isRendered(url.lastPathComponent) { rendered += size }
        }
        return StorageUsage(total: total, rendered: rendered)
    }

    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct CleanupResult {
    var freed: Int64 = 0
    var videosMovedToTrash = 0

    var message: String {
        var parts: [String] = []
        if freed > 0 { parts.append("Đã dọn \(StorageUsage.text(freed)).") }
        if videosMovedToTrash > 0 { parts.append("\(videosMovedToTrash) video lạ đã vào Thùng rác.") }
        return parts.isEmpty ? "Không có file thừa." : parts.joined(separator: " ")
    }
}
