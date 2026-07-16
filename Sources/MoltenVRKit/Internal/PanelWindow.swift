import AppKit
import SwiftUI

// Takes clicks while its window isn't key. Otherwise AppKit treats posted mouseDowns as
// activation clicks and swallows them.
final class PanelHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        // the capture size, the quad's aspect and the pointer mapping all assume pointSize,
        // so SwiftUI must never resize the window
        sizingOptions = []
    }

    required init?(coder: NSCoder) { fatalError("unused") }
}

// Borderless and transparent, parked with a 1px sliver on the primary screen so it's never
// seen but WindowServer keeps rendering it for capture.
final class PanelWindow: NSWindow {
    // text editing needs key status; the rest of the time stay out of the app's way
    var textInputActive = false

    init(size: CGSize, content: AnyView) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        setFrameOrigin(Self.hiddenOrigin(for: size))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        sharingType = .readOnly
        let host = PanelHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: size)
        contentView = host
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { textInputActive }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // the body has to sit where no other display is
    static func hiddenOrigin(for size: CGSize) -> CGPoint {
        guard let primary = NSScreen.screens.first?.frame else { return CGPoint(x: -8000, y: -8000) }
        let others = NSScreen.screens.dropFirst().map(\.frame)
        let candidates = [
            CGPoint(x: primary.midX - size.width / 2, y: primary.minY - size.height + 1), // below
            CGPoint(x: primary.midX - size.width / 2, y: primary.maxY - 1),               // above
            CGPoint(x: primary.maxX - 1, y: primary.midY - size.height / 2),              // right
            CGPoint(x: primary.minX - size.width + 1, y: primary.midY - size.height / 2), // left
            CGPoint(x: primary.maxX - 1, y: primary.minY - size.height + 1),              // corner
        ]
        for origin in candidates {
            let body = NSRect(origin: origin, size: size)
            if !others.contains(where: { $0.intersects(body) }) { return origin }
        }
        return candidates.last!
    }

    func replaceHidden() {
        setFrameOrigin(Self.hiddenOrigin(for: frame.size))
    }

    func setContent(_ content: AnyView, size: CGSize) {
        setContentSize(size)
        (contentView as? NSHostingView<AnyView>)?.rootView = content
    }
}
