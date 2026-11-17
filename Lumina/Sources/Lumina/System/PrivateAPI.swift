import CoreGraphics
import Foundation
import IOKit

/// Private API nạp bằng dlsym: thiếu hàm nào thì tính năng tương ứng tự ẩn, app không crash.
/// Danh sách hàm đối chiếu với imports của BetterDisplay 5.2.1 (REA inspect_macho).
enum PrivateAPI {
    typealias AVCreate = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias AVI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    typealias DSGet = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias DSSet = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias DSCan = @convention(c) (CGDirectDisplayID) -> Bool
    typealias DSAutoEnabled = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32

    private static let displayServicesPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    static let avServiceCreate: AVCreate? = symbol("IOAVServiceCreateWithService")
    static let avServiceWriteI2C: AVI2C? = symbol("IOAVServiceWriteI2C")
    static let avServiceReadI2C: AVI2C? = symbol("IOAVServiceReadI2C")

    static let displayServicesGetBrightness: DSGet? = symbol("DisplayServicesGetBrightness", in: displayServicesPath)
    static let displayServicesSetBrightness: DSSet? = symbol("DisplayServicesSetBrightness", in: displayServicesPath)
    static let displayServicesCanChangeBrightness: DSCan? = symbol("DisplayServicesCanChangeBrightness", in: displayServicesPath)
    /// "Tự động điều chỉnh độ sáng" (cảm biến ánh sáng môi trường). Kiểu (màn, &kết quả) → mã lỗi, 0 = ok.
    static let displayServicesAutoBrightnessEnabled: DSAutoEnabled? =
        symbol("DisplayServicesAmbientLightCompensationEnabled", in: displayServicesPath)

    /// `nil` khi không đọc được (thiếu hàm hoặc màn không có cảm biến).
    static func isAutoBrightnessOn(_ id: CGDirectDisplayID) -> Bool? {
        guard let fn = displayServicesAutoBrightnessEnabled else { return nil }
        var on = false
        return fn(id, &on) == 0 ? on : nil
    }

    static var hasDDC: Bool { avServiceCreate != nil && avServiceWriteI2C != nil && avServiceReadI2C != nil }

    private static func symbol<T>(_ name: String, in path: String? = nil) -> T? {
        guard let handle = dlopen(path, RTLD_NOW), let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }
}
