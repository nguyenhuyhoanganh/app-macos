import Foundation

/// Gói tin DDC/CI (VESA MCCS) gửi qua IOAVServiceWriteI2C(addr 0x37, offset 0x51).
public enum DDCPacket {
    public static let chipAddress: UInt32 = 0x37      // 7-bit; byte đích trên dây là 0x6E
    public static let dataAddress: UInt32 = 0x51      // byte nguồn (host)
    static let destByte: UInt8 = 0x6E
    static let replyChecksumSeed: UInt8 = 0x50

    public enum VCP: UInt8, Sendable {
        case brightness = 0x10
        case contrast = 0x12
        case volume = 0x62
    }

    /// Lệnh "Get VCP Feature": [0x82, 0x01, vcp, checksum].
    public static func getRequest(_ vcp: UInt8) -> [UInt8] {
        withChecksum([0x82, 0x01, vcp])
    }

    /// Lệnh "Set VCP Feature": [0x84, 0x03, vcp, hi, lo, checksum].
    public static func setRequest(_ vcp: UInt8, value: UInt16) -> [UInt8] {
        withChecksum([0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Checksum = XOR của byte đích 0x6E, byte nguồn 0x51 và toàn bộ thân gói.
    static func withChecksum(_ body: [UInt8]) -> [UInt8] {
        var chk = destByte ^ UInt8(dataAddress)
        for b in body { chk ^= b }
        return body + [chk]
    }

    public struct Reply: Equatable, Sendable {
        public let current: UInt16
        public let maximum: UInt16
    }

    /// Đọc trả lời 11 byte của "Get VCP Feature":
    /// [src 0x6E, 0x88, 0x02, result, vcp, type, maxHi, maxLo, curHi, curLo, checksum].
    public static func parseReply(_ r: [UInt8], vcp: UInt8) -> Reply? {
        guard r.count >= 11, r[2] == 0x02, r[3] == 0x00, r[4] == vcp else { return nil }
        var chk = replyChecksumSeed
        for b in r[0..<10] { chk ^= b }
        guard chk == r[10] else { return nil }
        let maximum = UInt16(r[6]) << 8 | UInt16(r[7])
        let current = UInt16(r[8]) << 8 | UInt16(r[9])
        guard maximum > 0 else { return nil }
        return Reply(current: current, maximum: maximum)
    }
}
