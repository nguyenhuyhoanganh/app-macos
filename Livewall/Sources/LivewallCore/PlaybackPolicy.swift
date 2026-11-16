public struct PowerStatus: Equatable, Sendable {
    public var hasBattery: Bool
    public var isOnAC: Bool
    public var percent: Int

    public init(hasBattery: Bool, isOnAC: Bool, percent: Int) {
        self.hasBattery = hasBattery
        self.isOnAC = isOnAC
        self.percent = percent
    }
}

public enum BatteryRule: Codable, Equatable, Hashable, Sendable {
    case off
    case below(Int)
    case always
}

public struct EnergySettings: Codable, Equatable, Sendable {
    public var pauseWhenCovered: Bool
    public var batteryRule: BatteryRule

    public init(pauseWhenCovered: Bool = true, batteryRule: BatteryRule = .below(20)) {
        self.pauseWhenCovered = pauseWhenCovered
        self.batteryRule = batteryRule
    }
}

/// The single decision every display goes through whenever anything changes.
public enum PlaybackPolicy {
    public static func shouldPlay(
        hasActiveWallpaper: Bool,
        displaysAsleep: Bool,
        isOccluded: Bool,
        power: PowerStatus,
        energy: EnergySettings
    ) -> Bool {
        guard hasActiveWallpaper, !displaysAsleep else { return false }
        if energy.pauseWhenCovered && isOccluded { return false }
        return !batterySavingApplies(power: power, rule: energy.batteryRule)
    }

    private static func batterySavingApplies(power: PowerStatus, rule: BatteryRule) -> Bool {
        guard power.hasBattery, !power.isOnAC else { return false }
        switch rule {
        case .off: return false
        case .always: return true
        case .below(let level): return power.percent <= level
        }
    }
}
