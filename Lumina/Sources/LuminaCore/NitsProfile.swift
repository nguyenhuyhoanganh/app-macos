import Foundation

/// Ước lượng độ sáng thật (nit) của một màn theo giá trị độ sáng 0…1:
/// `nit = min + (max − min) · giá trị^gamma`.
///
/// Không có máy đo thì đây chỉ là ước lượng theo thông số hãng; người dùng chỉnh `maxNits` và
/// `ratio` (bù khi so bằng mắt) để hai màn trông sáng như nhau.
public struct NitsProfile: Codable, Hashable, Sendable {
    public var minNits: Double
    public var maxNits: Double
    /// 2.2: thanh trượt theo cảm nhận (màn Apple, làm tối gamma). 1.0: đèn nền tăng đều (DDC).
    public var gamma: Double
    /// Bù khi đồng bộ: màn này sáng bằng `ratio` × số nit của màn chuẩn (1 = bằng nhau).
    public var ratio: Double

    public init(minNits: Double, maxNits: Double, gamma: Double, ratio: Double = 1) {
        self.minNits = minNits
        self.maxNits = maxNits
        self.gamma = gamma
        self.ratio = ratio
    }

    public func nits(at value: Double) -> Double {
        minNits + (maxNits - minNits) * pow(min(max(value, 0), 1), gamma)
    }

    /// Giá trị 0…1 cho ra số nit này (kẹp trong khả năng của màn).
    public func value(forNits nits: Double) -> Double {
        let span = max(maxNits - minNits, 0.001)
        let t = min(max((nits - minNits) / span, 0), 1)
        return pow(t, 1 / gamma)
    }

    // MARK: Mặc định

    /// Màn tích hợp MacBook Pro (Liquid Retina XDR): SDR trong nhà tối đa ~600 nit
    /// (1000 nit chỉ khi ngoài trời, máy tự đẩy lên); thanh độ sáng theo cảm nhận.
    /// Số đo: Notebookcheck (14″ M5) tối đa 646 / tối thiểu 1,2 cd/m²; Tom's Guide 558 (M5), 540 (M5 Pro).
    /// Đường cong thanh trượt → nit không có số công bố: mũ 2,2 vẫn là ước lượng.
    public static let macBookXDR = NitsProfile(minNits: 1, maxNits: 600, gamma: 2.2)
    /// Màn tích hợp khác (MacBook Air…): ~500 nit.
    public static let builtIn = NitsProfile(minNits: 2, maxNits: 500, gamma: 2.2)
    /// Kuycon P27G (4K 27″ IPS): 500 nit theo thông số bán lẻ; DDC tăng đèn nền gần tuyến tính.
    public static let kuyconP27G = NitsProfile(minNits: 50, maxNits: 500, gamma: 1)
    /// Màn ngoài chưa biết, điều khiển qua DDC.
    public static let externalDDC = NitsProfile(minNits: 40, maxNits: 350, gamma: 1)
    /// Màn ngoài không có DDC: làm tối bằng gamma (giữ tối thiểu 10%).
    public static let externalSoftware = NitsProfile(minNits: 35, maxNits: 350, gamma: 2.2)

    /// Hồ sơ mặc định theo tên màn của hệ thống, cách điều khiển và khoảng HDR của màn
    /// (`NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue`).
    /// Màn XDR nhận theo khoảng HDR (16× = 1600 nit đỉnh), không theo tên: macOS có thể gọi nó là
    /// "Built-in Retina Display" (đã gặp trên MacBook Pro M5 Pro).
    public static func defaults(name: String, isBuiltIn: Bool, hardwareControl: Bool, hdrHeadroom: Double = 1) -> NitsProfile {
        if isBuiltIn {
            return hdrHeadroom >= 8 || name.localizedCaseInsensitiveContains("XDR") ? macBookXDR : builtIn
        }
        if name.localizedCaseInsensitiveContains("Kuycon") && name.localizedCaseInsensitiveContains("P27G") { return kuyconP27G }
        return hardwareControl ? externalDDC : externalSoftware
    }
}

/// Đồng bộ độ sáng: các màn khác bám theo số nit của màn chuẩn (thường là màn tích hợp).
///
/// Màn chuẩn luôn kéo được hết 0…100%. Khi nó sáng hơn (hoặc tối hơn) mức màn kia làm được,
/// màn kia đứng ở giới hạn của nó (`limit`) — không kéo màn chuẩn theo.
public enum BrightnessSync {
    public enum Limit: Equatable, Sendable {
        case none
        case atMax   // màn chuẩn sáng hơn mức tối đa của màn này
        case atMin   // màn chuẩn tối hơn mức tối thiểu của màn này
    }

    public static func limit(sourceValue: Double, source: NitsProfile, target: NitsProfile) -> Limit {
        let want = source.nits(at: sourceValue) * target.ratio
        if want > target.maxNits + 0.5 { return .atMax }
        if want < target.minNits - 0.5 { return .atMin }
        return .none
    }

    /// Kéo màn phụ tới sát hai đầu nghĩa là "sáng/tối hết cỡ", không phải chỉnh cho khớp mắt:
    /// không học mức bù từ đó.
    public static func isCalibrationDrag(_ targetValue: Double) -> Bool {
        targetValue > 0.01 && targetValue < 0.99
    }

    /// Giá trị 0…1 cho màn `target` để sáng bằng `ratio` × số nit của màn chuẩn.
    public static func target(sourceValue: Double, source: NitsProfile, target: NitsProfile) -> Double {
        target.value(forNits: source.nits(at: sourceValue) * target.ratio)
    }

    /// Người dùng kéo màn `target` tới `targetValue` trong lúc đồng bộ: suy ra mức bù mới
    /// (giữ trong 0.25…4 để một lần kéo nhầm không làm hỏng việc đồng bộ).
    public static func ratio(sourceValue: Double, source: NitsProfile, targetValue: Double, target: NitsProfile) -> Double {
        let s = max(source.nits(at: sourceValue), 0.5)
        return min(max(target.nits(at: targetValue) / s, 0.25), 4)
    }
}
