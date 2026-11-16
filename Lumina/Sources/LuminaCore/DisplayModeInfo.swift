import Foundation

public enum LuminaCore {
    public static let version = "0.1.0"
}

/// Một chế độ hiển thị, tách khỏi `CGDisplayMode` để test được.
public struct DisplayModeInfo: Hashable, Codable, Sendable {
    public let id: Int32
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isUsableForDesktopGUI: Bool

    public init(id: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int,
                refreshRate: Double, isUsableForDesktopGUI: Bool) {
        self.id = id
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isUsableForDesktopGUI = isUsableForDesktopGUI
    }

    public var isHiDPI: Bool { pixelWidth >= width * 2 }
    public var resolution: Resolution { Resolution(width: width, height: height, isHiDPI: isHiDPI) }
}

/// Độ phân giải (kích thước điểm + HiDPI), bỏ qua tần số quét.
public struct Resolution: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int
    public let isHiDPI: Bool

    public init(width: Int, height: Int, isHiDPI: Bool) {
        self.width = width
        self.height = height
        self.isHiDPI = isHiDPI
    }

    public var label: String { "\(width) × \(height)" }
    public var aspect: Double { Double(width) / Double(max(height, 1)) }
}
