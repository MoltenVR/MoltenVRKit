import AppKit

/// Apple Music through osascript, so it works as a template for any scriptable app. The
/// first command brings up the macOS Automation prompt.
@MainActor
final class MusicModel: ObservableObject {
    struct Track: Equatable {
        var name = ""
        var artist = ""
        var album = ""
        var duration: Double = 0
        var id = ""
    }

    @Published private(set) var musicRunning = false
    @Published private(set) var playing = false
    @Published private(set) var track = Track()
    @Published private(set) var position: Double = 0
    @Published private(set) var volume: Double = 50
    @Published private(set) var shuffle = false
    @Published private(set) var artwork: NSImage?

    private var pollTask: Task<Void, Never>?
    private var artworkTrackId = ""
    var holdVolumeUpdates = false

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - commands

    func playPause() { fire("playpause") }
    func nextTrack() { fire("next track") }
    func previousTrack() { fire("back track") }

    func toggleShuffle() {
        let target = !shuffle
        shuffle = target
        fire("set shuffle enabled to \(target)")
    }

    func setVolume(_ v: Double) {
        volume = v
        fire("set sound volume to \(Int(v.rounded()))")
    }

    func openMusic() {
        Task.detached { _ = await Self.osascript("tell application \"Music\" to activate") }
    }

    private func fire(_ command: String) {
        Task { [weak self] in
            _ = await Self.osascript("tell application \"Music\" to \(command)")
            try? await Task.sleep(for: .milliseconds(250))
            await self?.poll()
        }
    }

    // MARK: - polling

    private func poll() async {
        // one round trip, split on 0x1f so commas in track names are safe
        let sep = "\u{1f}"
        // short names like `st` clash with Music's scripting dictionary, hence the `the`s
        let script = """
        if application "Music" is not running then return "off"
        tell application "Music"
            set theSep to (ASCII character 31)
            set theState to (player state as text)
            set theVol to sound volume
            set theShuf to (shuffle enabled as text)
            try
                set theTrack to current track
                set thePos to player position as text
                return theState & theSep & theVol & theSep & theShuf & theSep & ¬
                    (name of theTrack) & theSep & (artist of theTrack) & theSep & ¬
                    (album of theTrack) & theSep & (duration of theTrack as text) & ¬
                    theSep & thePos & theSep & (persistent ID of theTrack)
            on error
                return theState & theSep & theVol & theSep & theShuf
            end try
        end tell
        """
        guard let out = await Self.osascript(script) else {
            musicRunning = false
            return
        }
        if out == "off" {
            musicRunning = false
            playing = false
            track = Track()
            artwork = nil
            return
        }
        musicRunning = true
        let f = out.components(separatedBy: sep)
        guard f.count >= 3 else { return }
        playing = f[0] == "playing"
        if !holdVolumeUpdates { volume = Double(f[1]) ?? volume }
        shuffle = f[2] == "true"
        if f.count >= 9 {
            track = Track(name: f[3], artist: f[4], album: f[5],
                          duration: Double(f[6].replacingOccurrences(of: ",", with: ".")) ?? 0,
                          id: f[8])
            position = Double(f[7].replacingOccurrences(of: ",", with: ".")) ?? 0
            if track.id != artworkTrackId {
                artworkTrackId = track.id
                await fetchArtwork()
            }
        } else {
            track = Track()
            position = 0
            artwork = nil
            artworkTrackId = ""
        }
    }

    private func fetchArtwork() async {
        let script = """
        tell application "Music"
            try
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
        guard let out = await Self.osascript(script),
              let start = out.range(of: "«data "),
              out.hasSuffix("»") else {
            artwork = nil
            return
        }
        // «data tdta89504E…»: drop the wrapper and the 4-char type code
        var hex = String(out[start.upperBound...].dropLast())
        hex = String(hex.dropFirst(4))
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex, let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) {
            guard let b = UInt8(hex[i..<j], radix: 16) else { break }
            bytes.append(b)
            i = j
        }
        artwork = bytes.isEmpty ? nil : NSImage(data: Data(bytes))
    }

    // MARK: - osascript

    nonisolated static func osascript(_ script: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = Pipe()
                do {
                    try p.run()
                    // read before waiting: artwork is hundreds of KB and would fill the pipe
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    guard p.terminationStatus == 0 else { return cont.resume(returning: nil) }
                    cont.resume(returning: String(decoding: data, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
