import Foundation
import IOKit.ps
import LivewallCore

@MainActor
final class PowerMonitor {
    private(set) var status = PowerMonitor.read()
    var onChange: (() -> Void)?
    private var source: CFRunLoopSource?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }
        guard let created = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }
        source = created
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
    }

    private func refresh() {
        status = Self.read()
        onChange?()
    }

    private static func read() -> PowerStatus {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return PowerStatus(hasBattery: false, isOnAC: true, percent: 100)
        }
        let isOnAC = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? == kIOPSACPowerValue
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else { continue }
            return PowerStatus(hasBattery: true, isOnAC: isOnAC, percent: current * 100 / maximum)
        }
        return PowerStatus(hasBattery: false, isOnAC: isOnAC, percent: 100)
    }
}
