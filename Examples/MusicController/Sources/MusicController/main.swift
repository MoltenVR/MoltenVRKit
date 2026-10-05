// Apple Music from inside the headset. Run alongside MoltenVR for a now-playing panel with
// artwork, transport controls, shuffle and a volume slider you drag with the laser.
import AppKit
import SwiftUI
import MoltenVRKit

struct MusicPanelView: View {
    @ObservedObject var music: MusicModel

    var body: some View {
        Group {
            if music.musicRunning {
                nowPlaying
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "music.note")
                        .font(.system(size: 44)).foregroundStyle(.pink)
                    Text("Music isn't running")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    LaserButton(icon: "play.circle.fill", label: "Open Music") {
                        music.openMusic()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 26).fill(.black.opacity(0.80)))
        .overlay(RoundedRectangle(cornerRadius: 26)
            .strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .padding(6)
    }

    private var nowPlaying: some View {
        HStack(spacing: 22) {
            artworkView
            VStack(alignment: .leading, spacing: 10) {
                if music.track.name.isEmpty {
                    Text("Nothing playing")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text(music.track.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white).lineLimit(2)
                    Text(music.track.artist)
                        .font(.system(size: 21)).foregroundStyle(.pink).lineLimit(1)
                    Text(music.track.album)
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                progressBar
                HStack(spacing: 18) {
                    LaserButton(icon: "backward.fill") { music.previousTrack() }
                    LaserButton(icon: music.playing ? "pause.circle.fill" : "play.circle.fill",
                                size: 54) { music.playPause() }
                    LaserButton(icon: "forward.fill") { music.nextTrack() }
                    LaserButton(icon: "shuffle", on: music.shuffle) { music.toggleShuffle() }
                }
                volumeRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var artworkView: some View {
        Group {
            if let art = music.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.pink.opacity(0.55), .purple.opacity(0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: 52)).foregroundStyle(.white.opacity(0.8)))
            }
        }
        .frame(width: 210, height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var progressBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(.pink)
                    .frame(width: music.track.duration > 0
                           ? g.size.width * min(1, music.position / music.track.duration)
                           : 0)
            }
        }
        .frame(height: 6)
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
            LaserSlider(value: music.volume, range: 0...100) { dragging, v in
                music.holdVolumeUpdates = dragging
                music.setVolume(v)
            }
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct LaserButton: View {
    let icon: String
    var label: String? = nil
    var size: CGFloat = 30
    var on = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .semibold))
                if let label {
                    Text(label).font(.system(size: 22, weight: .semibold))
                }
            }
            .foregroundStyle(on ? .pink : .white.opacity(hovered ? 1 : 0.85))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(hovered ? 0.16 : on ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onLaserHover { hovered = $0 }
    }
}

// The whole track is the hit target, so it's easy to grab with the laser.
struct LaserSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Bool, Double) -> Void

    var body: some View {
        GeometryReader { g in
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height: 8)
                Capsule().fill(.white.opacity(0.85))
                    .frame(width: max(8, g.size.width * frac), height: 8)
                Circle().fill(.white)
                    .frame(width: 22, height: 22)
                    .offset(x: max(0, g.size.width * frac - 11))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        onChange(true, fraction(drag.location.x, g.size.width))
                    }
                    .onEnded { drag in
                        onChange(false, fraction(drag.location.x, g.size.width))
                    }
            )
        }
        .frame(height: 34)
    }

    private func fraction(_ x: CGFloat, _ width: CGFloat) -> Double {
        let f = max(0, min(1, x / max(1, width)))
        return range.lowerBound + f * (range.upperBound - range.lowerBound)
    }
}

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

@MainActor var gSession: MVRShellSession?
@MainActor var gPanel: MVRPanel?
@MainActor var gMusic: MusicModel?

Task { @MainActor in
    let music = MusicModel()
    music.start()
    // a bare SwiftPM executable has no icon of its own
    let session = MVRShellSession(
        appName: "Music",
        icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app"))
    session.onEvent = { print("MusicController event: \($0)") }
    session.start()
    let panel = session.presentPanel(
        id: "music", title: "Apple Music",
        pointSize: CGSize(width: 640, height: 300),
        placement: MVRPanelPlacement(x: -0.9, y: 1.15, z: -1.35, yawDegrees: 26,
                                     pitchDegrees: -12, widthMeters: 0.62)) {
        MusicPanelView(music: music)
    }
    gSession = session
    gPanel = panel
    gMusic = music
    print("MusicController: waiting for MoltenVR")
    if await !MVRScreenRecording.isGranted() {
        print("MusicController: no Screen Recording permission, so the panel will be blank")
        MVRScreenRecording.request()
    }
}
app.run()
