import Foundation
import Testing
@testable import LivewallCore

struct AppStateTests {
    private let wallpaper = UUID()
    private let systemImage = URL(fileURLWithPath: "/System/Library/Desktop Pictures/a.heic")

    @Test func assigningAWallpaperEnablesTheDisplay() {
        var state = AppState()
        state.assign(wallpaper, to: "display", previousSystemImage: systemImage)
        #expect(state.config(for: "display").wallpaperID == wallpaper)
        #expect(state.config(for: "display").isEnabled)
    }

    @Test func theOriginalSystemImageIsNotOverwrittenByLaterAssignments() {
        var state = AppState()
        state.assign(wallpaper, to: "display", previousSystemImage: systemImage)
        state.assign(UUID(), to: "display", previousSystemImage: URL(fileURLWithPath: "/tmp/ours.png"))
        #expect(state.config(for: "display").systemImage == systemImage)
    }

    @Test func clearingReturnsTheImageToRestore() {
        var state = AppState()
        state.assign(wallpaper, to: "display", previousSystemImage: systemImage)
        let restored = state.clear("display")
        #expect(restored == systemImage)
        #expect(state.config(for: "display").wallpaperID == nil)
        #expect(state.config(for: "display").systemImage == nil)
    }

    @Test func deletingAWallpaperClearsEveryDisplayUsingIt() {
        var state = AppState()
        state.assign(wallpaper, to: "one", previousSystemImage: systemImage)
        state.assign(wallpaper, to: "two", previousSystemImage: nil)
        let restored = state.removeWallpaper(wallpaper)
        #expect(state.config(for: "one").wallpaperID == nil)
        #expect(state.config(for: "two").wallpaperID == nil)
        #expect(restored == ["one": systemImage])
    }

    @Test func volumeIsKeptPerDisplayAndClamped() {
        var state = AppState()
        state.setVolume(0.4, for: "one")
        state.setVolume(3, for: "two")
        #expect(state.config(for: "one").volume == 0.4)
        #expect(state.config(for: "two").volume == 1)
    }

    @Test func aNewlyConnectedDisplayTakesTheMainDisplaysWallpaper() {
        var state = AppState()
        state.assign(wallpaper, to: "main", previousSystemImage: nil)
        let adoption = state.adoption(connected: ["main", "external"])
        #expect(adoption?.wallpaper == wallpaper)
        #expect(adoption?.displays == ["external"])
    }

    @Test func theFirstConnectedDisplayWithAWallpaperIsTheSource() {
        var state = AppState()
        let other = UUID()
        state.assign(other, to: "second", previousSystemImage: nil)
        state.assign(wallpaper, to: "first", previousSystemImage: nil)
        #expect(state.adoption(connected: ["first", "second", "new"])?.wallpaper == wallpaper)
    }

    @Test func aRememberedDisplayIsTheSourceWhenNoConnectedOneHasAWallpaper() {
        var state = AppState()
        state.assign(wallpaper, to: "laptop", previousSystemImage: nil)
        let adoption = state.adoption(connected: ["external"])
        #expect(adoption?.wallpaper == wallpaper)
        #expect(adoption?.displays == ["external"])
    }

    @Test func aDisplayWhoseWallpaperWasRemovedStaysEmpty() {
        var state = AppState()
        state.assign(wallpaper, to: "main", previousSystemImage: nil)
        state.assign(wallpaper, to: "external", previousSystemImage: nil)
        state.clear("external")
        #expect(state.adoption(connected: ["main", "external"]) == nil)
    }

    @Test func nothingIsAdoptedWithoutAnyWallpaper() {
        #expect(AppState().adoption(connected: ["main", "external"]) == nil)
    }

    @Test func aNewDisplayStartsMuted() {
        #expect(AppState().config(for: "unknown").volume == 0)
    }

    @Test func aDisabledDisplayKeepsItsWallpaperButIsNotActive() {
        var state = AppState()
        state.assign(wallpaper, to: "display", previousSystemImage: nil)
        state.setEnabled(false, for: "display")
        #expect(state.config(for: "display").wallpaperID == wallpaper)
        #expect(!state.config(for: "display").isActive)
    }

    @Test func stateSurvivesASaveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONStore<AppState>(url: directory.appendingPathComponent("state.json"))
        var state = AppState()
        state.assign(wallpaper, to: "display", previousSystemImage: systemImage)
        state.energy = EnergySettings(pauseWhenCovered: false, batteryRule: .below(20))
        state.hidesDesktopIcons = true
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func aMissingOrDamagedFileLoadsAsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONStore<AppState>(url: url)
        #expect(store.load() == nil)
        try Data("not json".utf8).write(to: url)
        #expect(store.load() == nil)
    }
}
