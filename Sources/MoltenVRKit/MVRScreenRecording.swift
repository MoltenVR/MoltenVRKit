import AppKit
import ScreenCaptureKit

/// SwiftUI panels are rendered through ScreenCaptureKit. On macOS 14.4+ that only captures
/// your app's own windows and needs no permission. Before 14.4 your app needs Screen
/// Recording. The SDK never shows alerts of its own, so check and request here. macOS shows
/// the system prompt once per app; after a denial the user has to flip the switch in
/// System Settings, which `openSystemSettings()` opens.
public enum MVRScreenRecording {
    /// True if panels can render: always on macOS 14.4+, where they capture only this app's
    /// own windows. Before 14.4 it probes ScreenCaptureKit rather than trusting the
    /// preflight, which can go stale after rebuilds.
    public static func isGranted() async -> Bool {
        do {
            if #available(macOS 14.4, *) { _ = try await SCShareableContent.currentProcess }
            else { _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
            return true
        } catch {
            return false
        }
    }

    /// Trigger the one-shot system permission prompt (no-op if already decided).
    public static func request() {
        CGRequestScreenCaptureAccess()
    }

    /// Open System Settings at Privacy & Security → Screen Recording.
    public static func openSystemSettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
