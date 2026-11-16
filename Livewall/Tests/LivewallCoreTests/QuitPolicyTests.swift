import Testing
@testable import LivewallCore

struct QuitPolicyTests {
    @Test func theDockOrCommandQOnlyClosesTheWindowWhileAWallpaperPlays() {
        #expect(QuitPolicy.action(for: .ordinary, hasActiveWallpaper: true, showsMenuBarIcon: true) == .closeWindow)
    }

    @Test func withNothingPlayingAnOrdinaryQuitQuits() {
        #expect(QuitPolicy.action(for: .ordinary, hasActiveWallpaper: false, showsMenuBarIcon: true) == .quit)
    }

    @Test func withoutTheMenuBarIconAnOrdinaryQuitQuitsSoTheAppCanStillBeClosed() {
        #expect(QuitPolicy.action(for: .ordinary, hasActiveWallpaper: true, showsMenuBarIcon: false) == .quit)
    }

    @Test func quittingFromTheMenuBarAlwaysQuits() {
        #expect(QuitPolicy.action(for: .explicit, hasActiveWallpaper: true, showsMenuBarIcon: true) == .quit)
    }

    @Test func logoutRestartAndShutDownAreNeverBlocked() {
        #expect(QuitPolicy.action(for: .system, hasActiveWallpaper: true, showsMenuBarIcon: true) == .quit)
    }
}
