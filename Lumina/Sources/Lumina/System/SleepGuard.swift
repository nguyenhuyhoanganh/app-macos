import Foundation
import IOKit.pwr_mgt

/// Ngăn màn hình (và máy) tự ngủ khi để yên — giữ một IOPM assertion trong lúc bật.
/// Assertion tự mất khi app thoát, nên không bao giờ "kẹt" ở trạng thái ngăn ngủ.
final class SleepGuard {
    private var assertion: IOPMAssertionID = 0

    var isActive: Bool { assertion != 0 }

    @discardableResult
    func set(_ on: Bool) -> Bool {
        if on {
            guard assertion == 0 else { return true }
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Lumina: Prevent Sleep" as CFString, &id)
            guard r == kIOReturnSuccess else { return false }
            assertion = id
        } else if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        return true
    }

    deinit { set(false) }
}
