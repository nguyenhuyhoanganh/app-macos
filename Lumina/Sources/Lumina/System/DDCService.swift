import CoreGraphics
import Foundation
import IOKit
import LuminaCore

/// Một kênh DDC tới một màn ngoài (IOAVService của DCPAVServiceProxy "External").
/// Mọi lệnh I2C chạy tuần tự trên hàng đợi riêng; lệnh ghi được gộp, chỉ gửi giá trị mới nhất.
final class DDCChannel: @unchecked Sendable {
    let edidUUID: String?
    private let service: CFTypeRef
    private let queue = DispatchQueue(label: "lumina.ddc", qos: .userInitiated)
    private let lock = NSLock()
    private var pendingWrites: [UInt8: UInt16] = [:]
    private var draining = false

    init(service: CFTypeRef, edidUUID: String?) {
        self.service = service
        self.edidUUID = edidUUID
    }

    /// Đọc một VCP (có thử lại). Trả về nil nếu màn không trả lời hợp lệ.
    func read(_ vcp: UInt8) async -> DDCPacket.Reply? {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.readSync(vcp)) }
        }
    }

    /// Ghi một VCP. Gọi liên tục khi kéo thanh trượt cũng không làm nghẽn màn.
    func write(_ vcp: UInt8, value: UInt16) {
        lock.lock()
        pendingWrites[vcp] = value
        let start = !draining
        draining = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let (vcp, value) = pendingWrites.first else {
                draining = false
                lock.unlock()
                return
            }
            pendingWrites.removeValue(forKey: vcp)
            lock.unlock()
            writeSync(DDCPacket.setRequest(vcp, value: value))
            usleep(50_000) // màn DDC cần ≥ 50 ms giữa hai lệnh
        }
    }

    @discardableResult
    private func writeSync(_ packet: [UInt8]) -> Bool {
        guard let write = PrivateAPI.avServiceWriteI2C else { return false }
        var data = packet
        var ok = false
        for _ in 0..<2 { // một số màn bỏ lệnh đầu, gửi 2 lần như MonitorControl
            usleep(10_000)
            if write(service, DDCPacket.chipAddress, DDCPacket.dataAddress, &data, UInt32(data.count)) == 0 { ok = true }
        }
        return ok
    }

    private func readSync(_ vcp: UInt8) -> DDCPacket.Reply? {
        guard let read = PrivateAPI.avServiceReadI2C else { return nil }
        for _ in 0..<4 {
            if writeSync(DDCPacket.getRequest(vcp)) {
                usleep(50_000)
                var reply = [UInt8](repeating: 0, count: 11)
                if read(service, DDCPacket.chipAddress, 0, &reply, UInt32(reply.count)) == 0,
                   let parsed = DDCPacket.parseReply(reply, vcp: vcp) {
                    return parsed
                }
            }
            usleep(20_000)
        }
        return nil
    }
}

/// Quét IORegistry tìm các DCPAVServiceProxy ngoài và ghép với màn hình CoreGraphics.
enum DDCDiscovery {
    static func channels(for displays: [DisplaySnapshot]) -> [CGDirectDisplayID: DDCChannel] {
        guard PrivateAPI.hasDDC, let create = PrivateAPI.avServiceCreate else { return [:] }

        var found: [DDCChannel] = []
        var iterator: io_iterator_t = 0
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }   // người gọi phải giải phóng gốc (tài liệu IOKit)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        // Thứ tự duyệt: framebuffer (có "EDID UUID") xuất hiện trước DCPAVServiceProxy của nó.
        var lastUUID: String?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let uuid = property(entry, "EDID UUID") as? String {
                lastUUID = uuid
            }
            guard className(entry) == "DCPAVServiceProxy",
                  property(entry, "Location") as? String == "External",
                  let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            found.append(DDCChannel(service: service, edidUUID: lastUUID))
            lastUUID = nil
        }

        let externals = displays.filter { !$0.isBuiltIn }
        let matches = DDCMatcher.match(
            displays: externals.map { .init(id: $0.id, vendor: $0.identity.vendor, model: $0.identity.model) },
            services: found.enumerated().map { .init(index: $0.offset, edidUUID: $0.element.edidUUID) }
        )
        return matches.mapValues { found[$0] }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func className(_ entry: io_registry_entry_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &buf)
        return String(cString: buf)
    }
}
