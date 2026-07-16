import AppKit
import SwiftUI
import ScreenCaptureKit

/// Everything behind one SwiftUI panel: the offscreen window, its capture at 2x into a
/// global IOSurface, laser input turned into mouse events, hover, and VR keyboard input.
@MainActor
final class PanelHost: NSObject, SCStreamOutput {
    static let captureScale: CGFloat = 2

    let window: PanelWindow
    nonisolated(unsafe) let surfacePublisher = SurfacePublisher()
    let hover = MVRHoverModel()
    let pointSize: CGSize

    var onTextFocusChanged: ((Bool) -> Void)?
    var onCaptureBlocked: (() -> Void)?

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "moltenvrkit.panel.capture")

    init(pointSize: CGSize, content: AnyView) {
        self.pointSize = pointSize
        self.window = PanelWindow(size: pointSize, content: AnyView(EmptyView()))
        super.init()
        window.setContent(AnyView(content.environmentObject(hover)), size: pointSize)
        surfacePublisher.prepare(pixelSize: CGSize(width: pointSize.width * Self.captureScale,
                                                   height: pointSize.height * Self.captureScale))
    }

    func tearDown() {
        stopCapture()
        window.orderOut(nil)
    }

    // MARK: - pointer

    private var eventNumber = 0
    private var buttons: UInt32 = 0
    private var lastPoint: CGPoint = .zero
    private var textFocused = false
    // Trigger pulls kick the controller and hands tremble at distance; both cancel
    // SwiftUI buttons if replayed literally. Latch the click point from ~120 ms before
    // the trigger edge and swallow drags inside a slop radius so presses read as
    // stationary taps (movement beyond the slop becomes a normal drag).
    private static let aimLatchSeconds: TimeInterval = 0.12
    private static let tapSlopPoints: CGFloat = 20
    private var downPoint: CGPoint = .zero
    private var pressOrigin: CGPoint = .zero
    private var dragging = false
    private var history: [(t: TimeInterval, point: CGPoint)] = []

    func handlePointer(_ ev: MVRPointerEvent) {
        // UV -> window points (AppKit origin is bottom-left; v=0 is content top),
        // quantized to whole points so tracking jitter doesn't spray mouseMoved events
        let pt = CGPoint(x: (CGFloat(ev.u) * pointSize.width).rounded(),
                         y: ((1 - CGFloat(ev.v)) * pointSize.height).rounded())
        let wasDown = buttons & MVRPointerEvent.trigger != 0
        let isDown = ev.buttons & MVRPointerEvent.trigger != 0

        let now = ProcessInfo.processInfo.systemUptime
        history = history.filter { now - $0.t < 1.0 }
        history.append((now, pt))

        if isDown && !wasDown {
            // change-driven stream: with a long-static aim the oldest sample IS the
            // pre-kick point, so fall back to it
            let latched = (history.last { now - $0.t >= Self.aimLatchSeconds }
                           ?? history.first)?.point ?? pt
            downPoint = latched
            pressOrigin = pt
            dragging = false
            post(.leftMouseDown, at: latched)
        } else if !isDown && wasDown {
            post(.leftMouseUp, at: dragging ? pt : downPoint)
            dragging = false
            // first-responder changes settle after the click completes
            DispatchQueue.main.async { self.checkTextFocus() }
        } else if isDown {
            dragging = dragging || hypot(pt.x - pressOrigin.x,
                                         pt.y - pressOrigin.y) > Self.tapSlopPoints
            if dragging, pt != lastPoint { post(.leftMouseDragged, at: pt) }
        } else if pt != lastPoint {
            post(.mouseMoved, at: pt)
        }

        let wasA = buttons & MVRPointerEvent.a != 0
        let isA = ev.buttons & MVRPointerEvent.a != 0
        if isA && !wasA { post(.rightMouseDown, at: pt) }
        else if !isA && wasA { post(.rightMouseUp, at: pt) }

        if abs(ev.scrollY) > 0.15 || abs(ev.scrollX) > 0.15 {
            postScroll(dx: CGFloat(ev.scrollX) * 12, dy: CGFloat(ev.scrollY) * 12, at: pt)
        }

        buttons = ev.buttons
        lastPoint = pt
        updateHover(ev)
    }

    func pointerLeft() {
        if buttons & MVRPointerEvent.trigger != 0 {
            post(.leftMouseUp, at: dragging ? lastPoint : downPoint)
        }
        buttons = 0
        dragging = false
        if hover.point != nil { hover.point = nil }
    }

    private func post(_ type: NSEvent.EventType, at pt: CGPoint) {
        eventNumber += 1
        guard let e = NSEvent.mouseEvent(
            with: type, location: pt, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: eventNumber, clickCount: 1, pressure: 1) else { return }
        // through the app's queue, not window.sendEvent: a click in a text field starts
        // AppKit's mouse-tracking loop, which only ever sees the mouseUp if it comes from the queue
        NSApp.postEvent(e, atStart: false)
    }

    private func postScroll(dx: CGFloat, dy: CGFloat, at pt: CGPoint) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return }
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let winPt = window.frame.origin
        cg.location = CGPoint(x: winPt.x + pt.x, y: screenH - (winPt.y + pt.y))
        guard let e = NSEvent(cgEvent: cg) else { return }
        // deliver straight to the view under the laser: sendEvent routes scrolls by
        // screen location, which is meaningless for an off-screen-parked window
        if let cv = window.contentView, let target = cv.hitTest(cv.convert(pt, from: nil)) {
            target.scrollWheel(with: e)
        } else {
            window.sendEvent(e)
        }
    }

    private func updateHover(_ ev: MVRPointerEvent) {
        // quantize to a 4pt grid and only publish real changes: tracking jitter would
        // otherwise re-render the panel's view tree at 90 Hz
        let q = CGPoint(x: (CGFloat(ev.u) * pointSize.width / 4).rounded() * 4,
                        y: (CGFloat(ev.v) * pointSize.height / 4).rounded() * 4)
        if hover.point != q { hover.point = q }
    }

    // MARK: - keyboard

    private func checkTextFocus() {
        let focused = window.firstResponder is NSTextView
            || window.firstResponder is NSTextField
        if focused != textFocused {
            textFocused = focused
            window.textInputActive = focused
            if focused { window.makeKey() }   // SwiftUI text editing needs key status
            onTextFocusChanged?(focused)
        }
    }

    func insertText(_ s: String) {
        if let client = window.firstResponder as? NSTextInputClient {
            client.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            sendKeyEvent(chars: s, keyCode: 0, down: true)
            sendKeyEvent(chars: s, keyCode: 0, down: false)
        }
    }

    func sendKey(_ key: KitWire.Key) {
        guard key.isDown else { return }   // AppKit text views act on keyDown
        let chars: String
        switch Int(key.keyCode) {
        case kVK_Return: chars = "\r"
        case kVK_Tab: chars = "\t"
        case kVK_Delete: chars = "\u{7f}"
        case kVK_Escape:
            // escape drops text focus instead of typing anything
            window.makeFirstResponder(nil)
            DispatchQueue.main.async { self.checkTextFocus() }
            return
        case kVK_LeftArrow: chars = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case kVK_RightArrow: chars = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case kVK_UpArrow: chars = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case kVK_DownArrow: chars = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        default: return
        }
        sendKeyEvent(chars: chars, keyCode: key.keyCode, down: true)
        sendKeyEvent(chars: chars, keyCode: key.keyCode, down: false)
        // return/escape usually end editing; re-check focus afterwards
        if Int(key.keyCode) == kVK_Return {
            DispatchQueue.main.async { self.checkTextFocus() }
        }
    }

    private func sendKeyEvent(chars: String, keyCode: UInt16, down: Bool) {
        guard let e = NSEvent.keyEvent(
            with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: chars, charactersIgnoringModifiers: chars,
            isARepeat: false, keyCode: keyCode) else { return }
        window.sendEvent(e)
    }

    // MARK: - capture

    private var startingCapture = false
    func startCapture() {
        guard stream == nil, !startingCapture else { return }
        startingCapture = true
        let windowID = CGWindowID(window.windowNumber)
        Task {
            defer { startingCapture = false }
            do {
                // a just-created window takes a beat to show up in shareable content
                var scWin: SCWindow?
                for attempt in 0..<10 {
                    let content = try await Self.ownWindows()
                    scWin = content.windows.first { $0.windowID == windowID }
                    if scWin != nil { break }
                    if attempt == 9 { return }
                    try await Task.sleep(for: .milliseconds(250))
                }
                let filter = SCContentFilter(desktopIndependentWindow: scWin!)
                let cfg = SCStreamConfiguration()
                cfg.width = Int(pointSize.width * Self.captureScale)
                cfg.height = Int(pointSize.height * Self.captureScale)
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.backgroundColor = .clear
                cfg.showsCursor = false
                cfg.ignoreShadowsSingleWindow = true
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                cfg.queueDepth = 3
                let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
                try await s.startCapture()
                stream = s
            } catch {
                // -3801 is Screen Recording denied: keep retrying so granting it brings
                // the panel up without a relaunch
                if (error as NSError).code == -3801 {
                    onCaptureBlocked?()
                    try? await Task.sleep(for: .seconds(5))
                    startingCapture = false
                    startCapture()
                }
            }
        }
    }

    private static func ownWindows() async throws -> SCShareableContent {
        if #available(macOS 14.4, *) { return try await SCShareableContent.currentProcess }
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }

    func stopCapture() {
        guard let s = stream else { return }
        stream = nil
        Task { try? await s.stopCapture() }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        surfacePublisher.publish(pb)
    }
}

// Carbon's kVK_* values, without importing Carbon
let kVK_Return = 36
let kVK_Tab = 48
let kVK_Delete = 51
let kVK_Escape = 53
let kVK_LeftArrow = 123
let kVK_RightArrow = 124
let kVK_DownArrow = 125
let kVK_UpArrow = 126
