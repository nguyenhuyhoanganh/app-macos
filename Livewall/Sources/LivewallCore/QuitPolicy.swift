import Foundation

/// The wallpaper is the app, so quitting from the Dock or with ⌘Q while one plays only
/// closes the window, the way other background apps behave. The menu bar item quits for
/// real, and logout, restart and shut down are never held up.
public enum QuitPolicy {
    public enum Source: Sendable {
        /// The Dock menu, ⌘Q, or an Apple Event from another app.
        case ordinary
        /// The menu bar's quit item, or a second copy giving way.
        case explicit
        /// Logout, restart or shut down.
        case system
    }

    public enum Action: Equatable, Sendable {
        case quit
        case closeWindow
    }

    /// Without the menu bar icon there would be no way left to quit, so the Dock quits then.
    public static func action(for source: Source, hasActiveWallpaper: Bool, showsMenuBarIcon: Bool) -> Action {
        switch source {
        case .explicit, .system:
            .quit
        case .ordinary:
            hasActiveWallpaper && showsMenuBarIcon ? .closeWindow : .quit
        }
    }
}
