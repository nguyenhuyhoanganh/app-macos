import Testing
@testable import LivewallCore

struct PlaybackPolicyTests {
    private let wired = PowerStatus(hasBattery: true, isOnAC: true, percent: 100)
    private let onBattery40 = PowerStatus(hasBattery: true, isOnAC: false, percent: 40)

    private func decide(
        asleep: Bool = false,
        occluded: Bool = false,
        power: PowerStatus? = nil,
        energy: EnergySettings = EnergySettings(),
        active: Bool = true
    ) -> Bool {
        PlaybackPolicy.shouldPlay(
            hasActiveWallpaper: active,
            displaysAsleep: asleep,
            isOccluded: occluded,
            power: power ?? wired,
            energy: energy
        )
    }

    @Test func playsWhenNothingPreventsIt() {
        #expect(decide())
    }

    @Test func pausesWhileDisplaysSleep() {
        #expect(!decide(asleep: true))
    }

    @Test func pausesWithoutAnActiveWallpaper() {
        #expect(!decide(active: false))
    }

    @Test func pausesWhenCoveredIfOcclusionPausingIsOn() {
        #expect(!decide(occluded: true, energy: EnergySettings(pauseWhenCovered: true)))
    }

    @Test func keepsPlayingWhenCoveredIfOcclusionPausingIsOff() {
        #expect(decide(occluded: true, energy: EnergySettings(pauseWhenCovered: false)))
    }

    @Test func batteryRuleIsIgnoredWhenSavingIsOff() {
        #expect(decide(power: onBattery40, energy: EnergySettings(batteryRule: .off)))
    }

    @Test func pausesWhenBatteryIsAtTheThreshold() {
        let power = PowerStatus(hasBattery: true, isOnAC: false, percent: 50)
        #expect(!decide(power: power, energy: EnergySettings(batteryRule: .below(50))))
    }

    @Test func playsWhenBatteryIsAboveTheThreshold() {
        let power = PowerStatus(hasBattery: true, isOnAC: false, percent: 51)
        #expect(decide(power: power, energy: EnergySettings(batteryRule: .below(50))))
    }

    @Test func alwaysOnBatteryPausesEvenWhenFull() {
        let power = PowerStatus(hasBattery: true, isOnAC: false, percent: 100)
        #expect(!decide(power: power, energy: EnergySettings(batteryRule: .always)))
    }

    @Test func wallPowerOverridesTheBatteryRule() {
        let power = PowerStatus(hasBattery: true, isOnAC: true, percent: 3)
        #expect(decide(power: power, energy: EnergySettings(batteryRule: .always)))
    }

    @Test func desktopsWithoutBatteryIgnoreTheBatteryRule() {
        let power = PowerStatus(hasBattery: false, isOnAC: false, percent: 0)
        #expect(decide(power: power, energy: EnergySettings(batteryRule: .always)))
    }
}
