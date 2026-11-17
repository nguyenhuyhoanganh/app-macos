import CoreGraphics
import Foundation
import LuminaCore

/// Lệnh dòng lệnh để kiểm thử và tự động hoá:
///   Lumina list
///   Lumina get-brightness <displayID>
///   Lumina set-brightness <displayID> <0-100>
///   Lumina set-resolution <displayID> <WxH> [--lowres]
///   Lumina login-item [on|off]      (chạy binary bên trong Lumina.app)
///   Lumina arrange <displayID> <x> <y>   (đặt màn vào toạ độ, tự hít cạnh)
///   Lumina vcp <displayID> <mã hex> [giá trị]   (đọc/ghi một mã DDC/CI, vd 0x14 = chế độ màu)
@MainActor
enum CLI {
    static func run(_ args: [String]) -> Int32 {
        let registry = DisplayRegistry()
        let brightness = BrightnessService()
        brightness.rescan(registry.displays)

        func display(_ arg: String?) -> DisplaySnapshot? {
            guard let arg, let id = UInt32(arg), let d = registry.display(id) else {
                fputs("Không thấy màn hình \(arg ?? "?"). Chạy `Lumina list` để xem ID.\n", stderr)
                return nil
            }
            return d
        }

        switch args[0] {
        case "list":
            for d in registry.displays {
                let state = wait { await brightness.read(d) }
                let kind = switch state.kind { case .system: "system"; case .hardware: "ddc"; case .software: "software" }
                print("""
                \(d.id)\t\(d.name)\t\(d.identity.vendorCode ?? "-") vendor=\(d.identity.vendor) model=\(d.identity.model) key=\(d.identity.key)
                \tbounds=\(Int(d.bounds.minX)),\(Int(d.bounds.minY)) \(Int(d.bounds.width))×\(Int(d.bounds.height))\(d.isMain ? " (chính)" : "")
                \tmode=\(d.current.resolution.label)\(d.current.isHiDPI ? " HiDPI" : "") @\(Int(d.current.refreshRate.rounded()))Hz \
                pixels=\(d.current.pixelWidth)x\(d.current.pixelHeight) brightness=\(Int((state.value * 100).rounded()))% (\(kind)) \
                slider=\(ModeCatalog.sliderModes(d.modes, current: d.current).map(\.label).joined(separator: ", "))
                """)
            }
            return 0

        case "vcp":
            guard let d = display(args[safe: 1]), let codeArg = args[safe: 2],
                  let code = UInt8(codeArg.replacingOccurrences(of: "0x", with: ""), radix: 16) else {
                fputs("Cách dùng: Lumina vcp <displayID> <mã hex> [giá trị]\n", stderr); return 2
            }
            guard let channel = brightness.ddc[d.id] else { fputs("Màn này không có DDC.\n", stderr); return 3 }
            if let valueArg = args[safe: 3], let value = UInt16(valueArg) {
                channel.write(code, value: value)
                Thread.sleep(forTimeInterval: 0.4)
            }
            guard let reply = wait({ await channel.read(code) }) else { print("không trả lời"); return 4 }
            print("0x\(String(code, radix: 16)) = \(reply.current) / tối đa \(reply.maximum)")
            return 0

        case "get-brightness":
            guard let d = display(args[safe: 1]) else { return 2 }
            let state = wait { await brightness.read(d) }
            print(Int((state.value * 100).rounded()))
            return 0

        case "set-brightness":
            guard let d = display(args[safe: 1]), let pct = args[safe: 2].flatMap(Double.init) else {
                fputs("Cách dùng: Lumina set-brightness <displayID> <0-100>\n", stderr); return 2
            }
            let state = wait { await brightness.read(d) }
            if state.kind == .software {
                fputs("Màn này không có DDC; làm tối phần mềm chỉ giữ khi app đang chạy.\n", stderr); return 3
            }
            brightness.set(pct / 100, for: d, kind: state.kind)
            Thread.sleep(forTimeInterval: 0.3)  // đợi hàng đợi DDC gửi xong
            let after = wait { await brightness.read(d) }
            print(Int((after.value * 100).rounded()))
            return 0

        case "set-resolution":
            guard let d = display(args[safe: 1]), let spec = args[safe: 2] else {
                fputs("Cách dùng: Lumina set-resolution <displayID> <WxH> [--lowres]\n", stderr); return 2
            }
            let parts = spec.lowercased().split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { fputs("Sai định dạng WxH\n", stderr); return 2 }
            let r = Resolution(width: parts[0], height: parts[1], isHiDPI: !args.contains("--lowres"))
            guard let mode = ModeCatalog.bestMode(for: r, preferredRefresh: d.current.refreshRate, in: d.modes) else {
                fputs("Màn \(d.id) không có \(r.label)\(r.isHiDPI ? " HiDPI" : "")\n", stderr); return 3
            }
            do {
                try ModeService(registry: registry).apply(modeID: mode.id, to: d.id)
                print("ok \(r.label) mode=\(mode.id)")
                return 0
            } catch {
                fputs("\(error.localizedDescription)\n", stderr); return 1
            }

        case "arrange":
            guard let d = display(args[safe: 1]), let x = args[safe: 2].flatMap(Double.init),
                  let y = args[safe: 3].flatMap(Double.init) else {
                fputs("Cách dùng: Lumina arrange <displayID> <x> <y>\n", stderr); return 2
            }
            do {
                let o = try ArrangementService().move(d.id, to: CGPoint(x: x, y: y), in: registry.displays)
                for (id, p) in o.sorted(by: { $0.key < $1.key }) { print("\(id)\t\(Int(p.x)),\(Int(p.y))") }
                return 0
            } catch { fputs("\(error.localizedDescription)\n", stderr); return 1 }

        case "login-item":
            if let arg = args[safe: 1] {
                do { try LoginItem.set(arg == "on") }
                catch { fputs("Không đổi được: \(error.localizedDescription)\n", stderr); return 1 }
            }
            print("Mở cùng máy: \(LoginItem.statusText)")
            return 0

        default:
            fputs("Lệnh không rõ: \(args[0])\n", stderr)
            return 2
        }
    }

    /// Chạy một hàm async tới khi xong mà vẫn cho main run loop chạy.
    private static func wait<T>(_ body: @escaping @MainActor () async -> T) -> T {
        var result: T?
        Task { @MainActor in result = await body() }
        while result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return result!
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
