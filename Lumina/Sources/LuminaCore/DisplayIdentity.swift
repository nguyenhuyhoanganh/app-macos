import Foundation

/// Khoá nhận diện một màn hình ổn định qua các lần cắm/rút.
public struct DisplayIdentity: Hashable, Codable, Sendable {
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32
    public let unitNumber: UInt32

    public init(vendor: UInt32, model: UInt32, serial: UInt32, unitNumber: UInt32) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.unitNumber = unitNumber
    }

    /// Khi serial = 0 (nhiều màn rẻ không ghi serial) thì thêm unit number để hai màn giống hệt không lẫn nhau.
    public var key: String {
        serial == 0 ? "\(vendor)-\(model)-u\(unitNumber)" : "\(vendor)-\(model)-\(serial)"
    }

    /// Mã hãng 3 chữ cái theo EDID (vd 0x2EB9 → "KUY").
    public var vendorCode: String? { EDID.manufacturerCode(vendor) }
}

/// Đường chéo màn hình (inch) từ kích thước vật lý (mm).
public func diagonalInches(widthMM: Double, heightMM: Double) -> Double {
    (widthMM * widthMM + heightMM * heightMM).squareRoot() / 25.4
}

public enum EDID {
    /// Mã hãng PNP 3 chữ cái nén trong 16 bit (mỗi chữ 5 bit, 'A' = 1).
    public static func manufacturerCode(_ vendor: UInt32) -> String? {
        let v = vendor & 0x7FFF
        let letters = [(v >> 10) & 0x1F, (v >> 5) & 0x1F, v & 0x1F]
        guard letters.allSatisfy({ (1...26).contains($0) }) else { return nil }
        return String(letters.map { Character(UnicodeScalar(UInt8($0) + 64)) })
    }

    /// Đọc vendor + product từ thuộc tính "EDID UUID" của IOMobileFramebuffer.
    /// Dạng "2EB97002-0000-…": 4 hex đầu là vendor (big-endian như EDID byte 8–9),
    /// 4 hex sau là product id lưu little-endian (EDID byte 10–11).
    public static func vendorProduct(fromUUID uuid: String) -> (vendor: UInt32, product: UInt32)? {
        let hex = uuid.replacingOccurrences(of: "-", with: "")
        guard hex.count >= 8,
              let vendor = UInt32(hex.prefix(4), radix: 16),
              let raw = UInt32(hex.dropFirst(4).prefix(4), radix: 16) else { return nil }
        let product = ((raw & 0xFF) << 8) | (raw >> 8)
        return (vendor, product)
    }
}

/// Ghép kênh DDC (DCPAVServiceProxy) với màn hình CoreGraphics.
public enum DDCMatcher {
    public struct Display: Sendable {
        public let id: UInt32
        public let vendor: UInt32
        public let model: UInt32
        public init(id: UInt32, vendor: UInt32, model: UInt32) {
            self.id = id; self.vendor = vendor; self.model = model
        }
    }

    public struct Service: Sendable {
        public let index: Int
        public let edidUUID: String?
        public init(index: Int, edidUUID: String?) {
            self.index = index; self.edidUUID = edidUUID
        }
    }

    /// Trả về map displayID → chỉ số service. Ghép theo vendor+product trong EDID UUID;
    /// phần còn lại chỉ ghép khi mỗi bên còn đúng một (trường hợp phổ biến: 1 màn ngoài).
    public static func match(displays: [Display], services: [Service]) -> [UInt32: Int] {
        var result: [UInt32: Int] = [:]
        var freeServices = services
        var freeDisplays: [Display] = []

        for d in displays {
            if let i = freeServices.firstIndex(where: { s in
                guard let uuid = s.edidUUID, let vp = EDID.vendorProduct(fromUUID: uuid) else { return false }
                return vp.vendor == d.vendor && vp.product == d.model
            }) {
                result[d.id] = freeServices[i].index
                freeServices.remove(at: i)
            } else {
                freeDisplays.append(d)
            }
        }
        if freeDisplays.count == 1, freeServices.count == 1 {
            result[freeDisplays[0].id] = freeServices[0].index
        }
        return result
    }
}
