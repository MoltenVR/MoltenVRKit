// Run alongside MoltenVR: a panel with a click counter, a hover-highlighted button and a
// text field shows up in the VR shell. Events and grab-moves print to stdout.
import AppKit
import SwiftUI
import MoltenVRKit

struct DemoPanelView: View {
    @State private var clicks = 0
    @State private var hovered = false
    @State private var text = ""

    var body: some View {
        VStack(spacing: 22) {
            Text("MoltenVRKit Demo")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Text("clicks: \(clicks)")
                .font(.system(size: 52, weight: .heavy))
                .foregroundStyle(.cyan)
            Button {
                clicks += 1
                print("KitDemo clicks: \(clicks)")
            } label: {
                Text("Click me")
                    .font(.system(size: 26, weight: .semibold))
                    .padding(.horizontal, 26).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(hovered ? .teal : .cyan)
            .onLaserHover { hovered = $0 }
            TextField("Type with the VR keyboard…", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 22))
                .frame(width: 400)
                .onChange(of: text) { _, t in print("KitDemo typed: \(t)") }
            Text("typed: \(text)")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 26).fill(.black.opacity(0.75)))
        .padding(6)
    }
}

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

@MainActor var gSession: MVRShellSession?
@MainActor var gPanel: MVRPanel?

Task { @MainActor in
    let session = MVRShellSession(appName: "KitDemo")
    session.onEvent = { print("KitDemo event: \($0)") }
    session.start()
    let panel = session.presentPanel(
        id: "demo", title: "KitDemo",
        pointSize: CGSize(width: 620, height: 460),
        placement: MVRPanelPlacement(x: 0.7, y: 1.6, z: -1.4, yawDegrees: -18,
                                     widthMeters: 1.0)) {
        DemoPanelView()
    }
    panel.onMoved = { p in
        print(String(format: "KitDemo moved: (%.2f, %.2f, %.2f) w=%.2f",
                     p.x, p.y, p.z, p.widthMeters))
    }
    gSession = session
    gPanel = panel
    print("KitDemo: waiting for MoltenVR")
    if await !MVRScreenRecording.isGranted() {
        print("KitDemo: no Screen Recording permission, so the panel will be blank")
        MVRScreenRecording.request()
    }
}
app.run()
