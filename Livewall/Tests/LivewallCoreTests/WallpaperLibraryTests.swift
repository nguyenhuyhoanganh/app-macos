import Foundation
import Testing
@testable import LivewallCore

struct WallpaperLibraryTests {
    private func item(
        _ name: String,
        hash: String = UUID().uuidString,
        width: Int = 1920,
        height: Int = 1080,
        audio: Bool = false,
        tags: [String] = [],
        added: Date = Date(timeIntervalSince1970: 0)
    ) -> Wallpaper {
        Wallpaper(
            name: name,
            fileName: "\(UUID().uuidString).mov",
            contentHash: hash,
            duration: 10,
            width: width,
            height: height,
            hasAudio: audio,
            tags: tags,
            addedAt: added
        )
    }

    @Test func newestWallpaperComesFirst() {
        var library = WallpaperLibrary()
        library.add(item("old", added: Date(timeIntervalSince1970: 1)))
        library.add(item("new", added: Date(timeIntervalSince1970: 2)))
        #expect(library.items.map(\.name) == ["new", "old"])
    }

    @Test func addingTheSameContentReturnsTheExistingWallpaper() {
        var library = WallpaperLibrary()
        let first = library.add(item("a", hash: "same"))
        let second = library.add(item("b", hash: "same"))
        #expect(second.id == first.id)
        #expect(library.items.count == 1)
    }

    @Test func searchIgnoresCaseAndVietnameseDiacritics() {
        var library = WallpaperLibrary()
        library.add(item("Biển Đêm"))
        library.add(item("Rừng"))
        let found = library.filtered(by: WallpaperFilter(text: "bien"))
        #expect(found.map(\.name) == ["Biển Đêm"])
    }

    @Test func searchMatchesTags() {
        var library = WallpaperLibrary()
        library.add(item("clip", tags: ["mèo"]))
        library.add(item("other"))
        #expect(library.filtered(by: WallpaperFilter(text: "meo")).map(\.name) == ["clip"])
    }

    @Test func filterKeepsOnlyVideosWithSound() {
        var library = WallpaperLibrary()
        library.add(item("loud", audio: true))
        library.add(item("quiet", audio: false))
        #expect(library.filtered(by: WallpaperFilter(soundOnly: true)).map(\.name) == ["loud"])
    }

    @Test func filterKeepsOnlyTheRequestedShape() {
        var library = WallpaperLibrary()
        library.add(item("wide", width: 3440, height: 1440))
        library.add(item("normal", width: 1920, height: 1080))
        #expect(library.filtered(by: WallpaperFilter(shape: .wide)).map(\.name) == ["wide"])
    }

    @Test func removeDropsTheWallpaper() {
        var library = WallpaperLibrary()
        let added = library.add(item("gone"))
        library.remove(added.id)
        #expect(library.items.isEmpty)
    }

    @Test(arguments: [
        (1920, 1080, VideoShape.standard),
        (2560, 1600, VideoShape.standard),
        (3440, 1440, VideoShape.wide),
        (5120, 1440, VideoShape.ultrawide),
        (1080, 1920, VideoShape.portrait),
    ])
    func shapeFollowsTheAspectRatio(width: Int, height: Int, expected: VideoShape) {
        #expect(VideoShape(width: width, height: height) == expected)
    }

    @Test func tagsAreSplitTrimmedAndDeduplicated() {
        #expect(Tags.parse("  biển, mèo   biển ") == ["biển", "mèo"])
    }
}
