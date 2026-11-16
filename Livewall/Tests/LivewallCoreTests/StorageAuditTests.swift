import Foundation
import Testing
@testable import LivewallCore

struct StorageAuditTests {
    private let id = UUID(uuidString: "7BC5C3E0-E7B6-4172-A15B-6DDFF60AEF54")!

    private func library(loop: Bool = false, coverTime: Double = 7.58) -> WallpaperLibrary {
        var library = WallpaperLibrary()
        library.add(Wallpaper(
            id: id, name: "a", fileName: "\(id.uuidString).mp4", contentHash: "h",
            duration: 15, width: 3840, height: 2160, hasAudio: true, coverTime: coverTime,
            pingPongFileName: loop ? "\(id.uuidString)-loop.mp4" : nil,
            pingPongAudioFileName: loop ? "\(id.uuidString)-loop.caf" : nil
        ))
        return library
    }

    private var used: StorageListing {
        StorageListing(
            videos: ["\(id.uuidString).mp4"],
            covers: ["\(id.uuidString).jpg"],
            stills: ["\(id.uuidString)-758.png"]
        )
    }

    @Test func filesTheLibraryUsesAreNeverOrphans() {
        #expect(StorageAudit.orphans(in: used, library: library()).isEmpty)
    }

    @Test func loopFilesInUseAreNeverOrphans() {
        var listing = used
        listing.videos += ["\(id.uuidString)-loop.mp4", "\(id.uuidString)-loop.caf"]
        #expect(StorageAudit.orphans(in: listing, library: library(loop: true)).isEmpty)
    }

    @Test func aLoopLeftByAnInterruptedRenderIsAnOrphan() {
        var listing = used
        listing.videos.append("\(id.uuidString)-loop.mp4")
        let orphans = StorageAudit.orphans(in: listing, library: library())
        #expect(orphans.videos == ["\(id.uuidString)-loop.mp4"])
    }

    @Test func aVideoMissingFromTheLibraryIsAnOrphan() {
        var listing = used
        listing.videos.append("ABCD.mp4")
        #expect(StorageAudit.orphans(in: listing, library: library()).videos == ["ABCD.mp4"])
    }

    @Test func aStillFromAnOlderCoverIsAnOrphan() {
        var listing = used
        listing.stills.append("\(id.uuidString)-100.png")
        #expect(StorageAudit.orphans(in: listing, library: library()).stills == ["\(id.uuidString)-100.png"])
    }

    @Test func aCoverOfADeletedVideoIsAnOrphan() {
        var listing = used
        listing.covers.append("GONE.jpg")
        #expect(StorageAudit.orphans(in: listing, library: library()).covers == ["GONE.jpg"])
    }

    @Test func protectedFilesAreKeptEvenWhenUnreferenced() {
        var listing = used
        listing.stills.append("\(id.uuidString)-100.png")
        let orphans = StorageAudit.orphans(
            in: listing, library: library(), keeping: ["\(id.uuidString)-100.png"]
        )
        #expect(orphans.isEmpty)
    }

    @Test func renderedFilesAreTellableFromImportedOriginals() {
        #expect(StorageAudit.isRendered("\(id.uuidString)-loop.mp4"))
        #expect(StorageAudit.isRendered("\(id.uuidString)-loop.caf"))
        #expect(!StorageAudit.isRendered("\(id.uuidString).mp4"))
    }

    @Test func aCoverChangeRenamesTheStill() {
        var item = library().items[0]
        let before = item.stillFileName
        item.coverTime = 1
        #expect(item.stillFileName != before)
    }
}

struct DiskSpaceTests {
    private let gigabyte: Int64 = 1_000_000_000

    @Test func thereIsRoomWhenTheFileFitsAndALittleSpaceRemains() {
        #expect(DiskSpace.hasRoom(for: gigabyte, available: 3 * gigabyte))
    }

    @Test func thereIsNoRoomWhenTheFileWouldNearlyFillTheDisk() {
        #expect(!DiskSpace.hasRoom(for: 2 * gigabyte, available: 2 * gigabyte + 1000))
    }

    @Test func aLoopIsEstimatedLargeEnoughForAFullReencode() {
        #expect(DiskSpace.estimatedLoopSize(ofVideo: gigabyte) >= 2 * gigabyte)
    }
}
