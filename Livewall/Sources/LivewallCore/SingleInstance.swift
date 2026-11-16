import Foundation

/// Two running copies would stack their wallpaper windows and overwrite each other's
/// saved library, so a later copy always gives way. Process IDs wrap around, which is
/// why launch time decides.
public enum SingleInstance {
    public static func earlierInstance<ID: Hashable>(launchDates: [ID: Date], current: ID) -> ID? {
        guard
            let mine = launchDates[current],
            let oldest = launchDates.min(by: { $0.value < $1.value }),
            oldest.value < mine
        else { return nil }
        return oldest.key
    }
}
