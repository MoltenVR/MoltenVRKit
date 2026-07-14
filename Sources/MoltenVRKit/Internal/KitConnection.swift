import Foundation

/// Socket client for MoltenVR's kit broker. Retries until MoltenVR is running, sends HELLO
/// and hands decoded messages to the session on the main queue.
final class KitConnection: @unchecked Sendable {
    static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["MOLTENVRKIT_SOCKET"] {
            return override
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MoltenVR")
            .appendingPathComponent(KitWire.socketName).path
    }

    let appName: String

    var onConnected: ((KitWire.HelloAck) -> Void)?
    var onDisconnected: (() -> Void)?
    var onPointer: ((KitWire.Pointer) -> Void)?
    var onPanelMoved: ((KitWire.PanelMoved) -> Void)?
    var onKey: ((KitWire.Key) -> Void)?
    var onText: ((UInt32, String) -> Void)?
    var onShellState: ((Bool) -> Void)?
    var onKeyboardState: ((UInt32, Bool) -> Void)?
    var onRejected: ((UInt32, UInt32) -> Void)?

    private(set) var connected = false
    private var fd: Int32 = -1
    private let sendLock = NSLock()
    private let queue = DispatchQueue(label: "moltenvrkit.connection")
    private var retryTimer: DispatchSourceTimer?

    init(appName: String) {
        self.appName = appName
    }

    func start() {
        guard retryTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.5)
        t.setEventHandler { [weak self] in self?.tryConnect() }
        t.resume()
        retryTimer = t
    }

    func stop() {
        retryTimer?.cancel(); retryTimer = nil
        queue.async { self.closeSocket(notify: true) }
    }

    private func tryConnect() {
        guard !connected else { return }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { src in
            withUnsafeMutableBytes(of: &addr.sun_path) { dst in
                _ = strlcpy(dst.baseAddress!.assumingMemoryBound(to: CChar.self), src, dst.count)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, len) }
        } == 0
        guard ok else { close(s); return }
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        fd = s
        connected = true
        send(.hello, KitWire.encode(KitWire.Hello(
            protoVer: UInt32(KitWire.protoVer),
            featureFlags: 0,
            pid: UInt32(getpid()),
            appName: appName)))
        Thread.detachNewThread { [weak self] in self?.readLoop(s) }
    }

    private func closeSocket(notify: Bool) {
        guard fd >= 0 else { return }
        close(fd); fd = -1
        connected = false
        if notify { DispatchQueue.main.async { self.onDisconnected?() } }
    }

    func send(_ type: KitWire.MsgType, _ payload: Data) {
        guard connected else { return }
        let d = KitWire.frame(type, payload)
        sendLock.lock(); defer { sendLock.unlock() }
        let n = d.withUnsafeBytes { write(fd, $0.baseAddress, d.count) }
        if n != d.count { queue.async { self.closeSocket(notify: true) } }
    }

    private func readLoop(_ s: Int32) {
        func readAll(_ buf: UnsafeMutableRawPointer, _ len: Int) -> Bool {
            var p = buf, remain = len
            while remain > 0 {
                let n = read(s, p, remain)
                if n <= 0 { return false }
                p += n; remain -= n
            }
            return true
        }
        var hdr = [UInt8](repeating: 0, count: KitWire.headerSize)
        // twice the largest payload (a 256KB icon), same as the broker
        var body = [UInt8](repeating: 0, count: 512 * 1024)
        while true {
            guard readAll(&hdr, KitWire.headerSize) else { break }
            let magic = hdr.loadLE(UInt32.self, 0)
            let type = hdr.loadLE(UInt16.self, 6)
            let plen = Int(hdr.loadLE(UInt32.self, 8))
            guard magic == KitWire.magic, plen <= body.count else { break }
            if plen > 0, !readAll(&body, plen) { break }
            dispatch(type: type, payload: Array(body[0..<plen]), length: plen)
        }
        queue.async { self.closeSocket(notify: true) }
    }

    private func dispatch(type: UInt16, payload: [UInt8], length: Int) {
        DispatchQueue.main.async { [self] in
            switch KitWire.MsgType(rawValue: type) {
            case .helloAck:
                if let ack = KitWire.decodeHelloAck(payload) { onConnected?(ack) }
            case .pointer:
                if let p = KitWire.decodePointer(payload) { onPointer?(p) }
            case .panelMoved:
                if let m = KitWire.decodePanelMoved(payload) { onPanelMoved?(m) }
            case .key:
                if let k = KitWire.decodeKey(payload) { onKey?(k) }
            case .text:
                if let (id, s) = KitWire.decodeText(payload, length: length) { onText?(id, s) }
            case .shellState:
                if let v = KitWire.decodeU32(payload) { onShellState?(v != 0) }
            case .keyboardState:
                if let (id, v) = KitWire.decodePair(payload) { onKeyboardState?(id, v != 0) }
            case .panelRejected:
                if let (id, reason) = KitWire.decodePair(payload) { onRejected?(id, reason) }
            default:
                break
            }
        }
    }
}
