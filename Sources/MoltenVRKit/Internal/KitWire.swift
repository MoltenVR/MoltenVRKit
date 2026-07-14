import Foundation

/// The "MVRK" v1 wire protocol between apps and the kit broker inside MoltenVR. MoltenVR
/// builds this same file, so the byte layout here is the contract.
///
/// Each message is a 12-byte header {magic u32, ver u16, type u16, payloadLen u32} and a
/// packed little-endian payload. Receivers skip unknown message types
/// by payload length and accept payloads longer than they understand (structs only ever
/// grow at the tail), so v1 peers survive additive protocol growth. Feature bits are
/// exchanged in HELLO/HELLO_ACK; the version bumps only for breaking changes.
enum KitWire {
    static let magic: UInt32 = 0x4b52564d   // "MVRK"
    static let protoVer: UInt16 = 1
    static let headerSize = 12
    static let socketName = "moltenvrkit.sock"

    /// HELLO/HELLO_ACK feature bits.
    enum Feature {
        static let keyboard: UInt32 = 1 << 0      // broker routes VR-keyboard text/keys
        static let rawSurfaces: UInt32 = 1 << 1    // bring-your-own-IOSurface panels
    }

    enum MsgType: UInt16 {
        // client -> broker
        case hello = 1          // protoVer u32, featureFlags u32, pid u32, appName char[64]
        case panelUpsert = 3    // KitPanelDesc
        case panelRemove = 4    // panelId u32
        case textFocus = 5      // panelId u32, active u32
        case appIcon = 13       // raw image bytes (PNG preferred, ≤128px, ≤256KB) for the dock
        // broker -> client
        case helloAck = 2       // protoVer u32, featureFlags u32, maxPanels u32, shellOpen u32
        case panelRejected = 6  // panelId u32, reason u32
        case shellState = 7     // open u32
        case pointer = 8        // panelId u32, hand u32, u f32, v f32, buttons u32, scroll f32[2]
        case panelMoved = 9     // panelId u32, pos f32[3], quat f32[4], size f32[2], curvature f32
        case key = 10           // panelId u32, keyCode u16, _pad u16, modifiers u32, isDown u32
        case text = 11          // panelId u32, utf8 bytes (length from payloadLen)
        case keyboardState = 12 // panelId u32, visible u32
    }

    enum RejectReason: UInt32 {
        case panelBudget = 1
        case badSurface = 2
        case protocolError = 3
    }

    /// Pointer button bits (same values as the bridge's SHELL_BTN_*).
    enum Button {
        static let trigger: UInt32 = 1 << 0
        static let squeeze: UInt32 = 1 << 1
        static let a: UInt32 = 1 << 2
        static let b: UInt32 = 1 << 3
        static let stick: UInt32 = 1 << 4
    }

    // MARK: - message structs

    struct Hello {
        var protoVer: UInt32
        var featureFlags: UInt32
        var pid: UInt32
        var appName: String   // truncated to 63 UTF-8 bytes on the wire
    }

    struct HelloAck {
        var protoVer: UInt32
        var featureFlags: UInt32
        var maxPanels: UInt32
        var shellOpen: Bool
    }

    struct PanelDesc {
        var panelId: UInt32
        var surfaceId: UInt32
        var pos: (Float, Float, Float)
        var quat: (Float, Float, Float, Float)   // x,y,z,w
        var size: (Float, Float)                 // meters
        var curvature: Float
        var opacity: Float
        var z: Int32
        var flags: UInt32                        // bit0 visible, bit1 hitTestable
        var title: String                        // truncated to 63 UTF-8 bytes
    }

    struct Pointer {
        var panelId: UInt32
        var hand: UInt32
        var u: Float, v: Float
        var buttons: UInt32
        var scrollX: Float, scrollY: Float
    }

    struct PanelMoved {
        var panelId: UInt32
        var pos: (Float, Float, Float)
        var quat: (Float, Float, Float, Float)
        var size: (Float, Float)
        var curvature: Float
    }

    struct Key {
        var panelId: UInt32
        var keyCode: UInt16
        var modifiers: UInt32   // ShellKeyModifiers raw: 1 shift, 2 cmd, 4 opt, 8 ctrl
        var isDown: Bool
    }

    // MARK: - framing

    static func frame(_ type: MsgType, _ payload: Data) -> Data {
        var d = Data(capacity: headerSize + payload.count)
        d.appendLE(magic)
        d.appendLE(protoVer)
        d.appendLE(type.rawValue)
        d.appendLE(UInt32(payload.count))
        d.append(payload)
        return d
    }

    // MARK: - encode

    static func encode(_ m: Hello) -> Data {
        var p = Data(capacity: 76)
        p.appendLE(m.protoVer)
        p.appendLE(m.featureFlags)
        p.appendLE(m.pid)
        p.appendFixedString(m.appName, length: 64)
        return p
    }

    static func encode(_ m: HelloAck) -> Data {
        var p = Data(capacity: 16)
        p.appendLE(m.protoVer)
        p.appendLE(m.featureFlags)
        p.appendLE(m.maxPanels)
        p.appendLE(UInt32(m.shellOpen ? 1 : 0))
        return p
    }

    static func encode(_ m: PanelDesc) -> Data {
        var p = Data(capacity: 124)
        p.appendLE(m.panelId)
        p.appendLE(m.surfaceId)
        p.appendLE(m.pos.0); p.appendLE(m.pos.1); p.appendLE(m.pos.2)
        p.appendLE(m.quat.0); p.appendLE(m.quat.1); p.appendLE(m.quat.2); p.appendLE(m.quat.3)
        p.appendLE(m.size.0); p.appendLE(m.size.1)
        p.appendLE(m.curvature)
        p.appendLE(m.opacity)
        p.appendLE(UInt32(bitPattern: m.z))
        p.appendLE(m.flags)
        p.appendFixedString(m.title, length: 64)
        return p
    }

    static func encode(_ m: Pointer) -> Data {
        var p = Data(capacity: 28)
        p.appendLE(m.panelId)
        p.appendLE(m.hand)
        p.appendLE(m.u); p.appendLE(m.v)
        p.appendLE(m.buttons)
        p.appendLE(m.scrollX); p.appendLE(m.scrollY)
        return p
    }

    static func encode(_ m: PanelMoved) -> Data {
        var p = Data(capacity: 44)
        p.appendLE(m.panelId)
        p.appendLE(m.pos.0); p.appendLE(m.pos.1); p.appendLE(m.pos.2)
        p.appendLE(m.quat.0); p.appendLE(m.quat.1); p.appendLE(m.quat.2); p.appendLE(m.quat.3)
        p.appendLE(m.size.0); p.appendLE(m.size.1)
        p.appendLE(m.curvature)
        return p
    }

    static func encode(_ m: Key) -> Data {
        var p = Data(capacity: 16)
        p.appendLE(m.panelId)
        p.appendLE(m.keyCode)
        p.appendLE(UInt16(0))
        p.appendLE(m.modifiers)
        p.appendLE(UInt32(m.isDown ? 1 : 0))
        return p
    }

    static func encodeText(panelId: UInt32, _ text: String) -> Data {
        var p = Data()
        p.appendLE(panelId)
        p.append(contentsOf: Array(text.utf8))
        return p
    }

    /// Generic {u32, u32} payloads (textFocus, panelRejected, keyboardState) and
    /// single-u32 payloads (panelRemove, shellState).
    static func encodePair(_ a: UInt32, _ b: UInt32) -> Data {
        var p = Data(capacity: 8); p.appendLE(a); p.appendLE(b); return p
    }
    static func encodeU32(_ a: UInt32) -> Data {
        var p = Data(capacity: 4); p.appendLE(a); return p
    }

    // MARK: - decode ([UInt8] payload; returns nil when too short)

    static func decodeHello(_ b: [UInt8]) -> Hello? {
        guard b.count >= 76 else { return nil }
        return Hello(protoVer: b.loadLE(UInt32.self, 0),
                     featureFlags: b.loadLE(UInt32.self, 4),
                     pid: b.loadLE(UInt32.self, 8),
                     appName: b.loadFixedString(12, length: 64))
    }

    static func decodeHelloAck(_ b: [UInt8]) -> HelloAck? {
        guard b.count >= 16 else { return nil }
        return HelloAck(protoVer: b.loadLE(UInt32.self, 0),
                        featureFlags: b.loadLE(UInt32.self, 4),
                        maxPanels: b.loadLE(UInt32.self, 8),
                        shellOpen: b.loadLE(UInt32.self, 12) != 0)
    }

    static func decodePanelDesc(_ b: [UInt8]) -> PanelDesc? {
        guard b.count >= 124 else { return nil }
        return PanelDesc(
            panelId: b.loadLE(UInt32.self, 0),
            surfaceId: b.loadLE(UInt32.self, 4),
            pos: (b.loadLE(Float.self, 8), b.loadLE(Float.self, 12), b.loadLE(Float.self, 16)),
            quat: (b.loadLE(Float.self, 20), b.loadLE(Float.self, 24),
                   b.loadLE(Float.self, 28), b.loadLE(Float.self, 32)),
            size: (b.loadLE(Float.self, 36), b.loadLE(Float.self, 40)),
            curvature: b.loadLE(Float.self, 44),
            opacity: b.loadLE(Float.self, 48),
            z: Int32(bitPattern: b.loadLE(UInt32.self, 52)),
            flags: b.loadLE(UInt32.self, 56),
            title: b.loadFixedString(60, length: 64))
    }

    static func decodePointer(_ b: [UInt8]) -> Pointer? {
        guard b.count >= 28 else { return nil }
        return Pointer(panelId: b.loadLE(UInt32.self, 0),
                       hand: b.loadLE(UInt32.self, 4),
                       u: b.loadLE(Float.self, 8), v: b.loadLE(Float.self, 12),
                       buttons: b.loadLE(UInt32.self, 16),
                       scrollX: b.loadLE(Float.self, 20), scrollY: b.loadLE(Float.self, 24))
    }

    static func decodePanelMoved(_ b: [UInt8]) -> PanelMoved? {
        guard b.count >= 44 else { return nil }
        return PanelMoved(
            panelId: b.loadLE(UInt32.self, 0),
            pos: (b.loadLE(Float.self, 4), b.loadLE(Float.self, 8), b.loadLE(Float.self, 12)),
            quat: (b.loadLE(Float.self, 16), b.loadLE(Float.self, 20),
                   b.loadLE(Float.self, 24), b.loadLE(Float.self, 28)),
            size: (b.loadLE(Float.self, 32), b.loadLE(Float.self, 36)),
            curvature: b.loadLE(Float.self, 40))
    }

    static func decodeKey(_ b: [UInt8]) -> Key? {
        guard b.count >= 16 else { return nil }
        return Key(panelId: b.loadLE(UInt32.self, 0),
                   keyCode: b.loadLE(UInt16.self, 4),
                   modifiers: b.loadLE(UInt32.self, 8),
                   isDown: b.loadLE(UInt32.self, 12) != 0)
    }

    static func decodeText(_ b: [UInt8], length: Int) -> (panelId: UInt32, text: String)? {
        guard length >= 4, b.count >= length else { return nil }
        let id = b.loadLE(UInt32.self, 0)
        let text = String(decoding: b[4..<length], as: UTF8.self)
        return (id, text)
    }

    static func decodePair(_ b: [UInt8]) -> (UInt32, UInt32)? {
        guard b.count >= 8 else { return nil }
        return (b.loadLE(UInt32.self, 0), b.loadLE(UInt32.self, 4))
    }

    static func decodeU32(_ b: [UInt8]) -> UInt32? {
        guard b.count >= 4 else { return nil }
        return b.loadLE(UInt32.self, 0)
    }
}

// MARK: - little-endian helpers

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ v: Float) {
        var x = v.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
    /// NUL-padded fixed-width UTF-8 field; always writes exactly `length` bytes and
    /// keeps the last byte NUL so readers can't run off the end.
    mutating func appendFixedString(_ s: String, length: Int) {
        var bytes = Array(s.utf8.prefix(length - 1))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: length - bytes.count))
        append(contentsOf: bytes)
    }
}

extension [UInt8] {
    func loadLE<T>(_ type: T.Type, _ offset: Int) -> T {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
    func loadFixedString(_ offset: Int, length: Int) -> String {
        let slice = self[offset..<Swift.min(offset + length, count)]
        let nul = slice.firstIndex(of: 0) ?? slice.endIndex
        return String(decoding: slice[slice.startIndex..<nul], as: UTF8.self)
    }
}
