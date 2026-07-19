import AppKit
import SwiftUI

/// Handle to one panel presented into the VR shell. Owned by the MVRShellSession that
/// created it; observe `placement` (updated live when the user grab-moves the panel in
/// VR) and call `update`/`setContent`/`remove` to drive it.
@MainActor
public final class MVRPanel: ObservableObject, Identifiable {
    public let id: String
    public let title: String
    @Published public private(set) var placement: MVRPanelPlacement
    @Published public private(set) var isPresented = true
    /// Fired after a grab-move in VR settles. Save the placement here if it should
    /// survive a relaunch.
    public var onMoved: ((MVRPanelPlacement) -> Void)?
    /// Raw pointer events. SwiftUI panels get these too, after the mouse events are posted.
    public var onPointer: ((MVRPointerEvent) -> Void)?

    let wireId: UInt32
    let host: PanelHost?
    let surfaceId: () -> UInt32
    let contentAspect: Float
    private unowned let session: MVRShellSession

    init(id: String, title: String, placement: MVRPanelPlacement, wireId: UInt32,
         host: PanelHost?, surfaceId: @escaping () -> UInt32, contentAspect: Float,
         session: MVRShellSession) {
        self.id = id
        self.title = title
        self.placement = placement
        self.wireId = wireId
        self.host = host
        self.surfaceId = surfaceId
        self.contentAspect = contentAspect
        self.session = session
    }

    /// Move/resize/restyle the panel programmatically.
    public func update(placement: MVRPanelPlacement) {
        self.placement = placement
        session.upsert(self)
    }

    /// Swap the SwiftUI content (SwiftUI panels only).
    public func setContent<V: View>(@ViewBuilder _ content: () -> V) {
        guard let host else { return }
        host.window.setContent(AnyView(content().environmentObject(host.hover)),
                               size: host.pointSize)
    }

    /// Take the panel out of the shell. The handle is dead afterwards.
    public func remove() {
        guard isPresented else { return }
        isPresented = false
        session.removePanel(self)
    }

    func adoptMove(_ mv: KitWire.PanelMoved) {
        var p = placement
        p.x = mv.pos.0; p.y = mv.pos.1; p.z = mv.pos.2
        let a = MVRPanelPlacement.angles(from: mv.quat)
        p.yawDegrees = a.yaw; p.pitchDegrees = a.pitch; p.rollDegrees = a.roll
        p.widthMeters = mv.size.0
        p.curvature = mv.curvature
        placement = p
        onMoved?(p)
    }
}
