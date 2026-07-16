import SwiftUI

/// Laser-hover state for one panel. AppKit tracking areas only fire for the real cursor,
/// so SwiftUI's .onHover never sees the VR laser; use .onLaserHover instead. `point` is
/// in the panel's global space (top-left origin, points), nil when the laser is elsewhere.
@MainActor
public final class MVRHoverModel: ObservableObject {
    @Published public internal(set) var point: CGPoint?
}

struct MVRLaserHoverModifier: ViewModifier {
    @EnvironmentObject private var hover: MVRHoverModel
    let action: (Bool) -> Void
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in frame = f }
            })
            .onChange(of: hover.point) { _, pt in
                let now = pt.map { frame.contains($0) } ?? false
                if now != hovering { hovering = now; action(now) }
            }
    }
}

extension View {
    /// Like .onHover, but driven by the MoltenVR laser pointer. Only meaningful inside a
    /// view presented with `MVRShellSession.presentPanel`.
    public func onLaserHover(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(MVRLaserHoverModifier(action: action))
    }
}
