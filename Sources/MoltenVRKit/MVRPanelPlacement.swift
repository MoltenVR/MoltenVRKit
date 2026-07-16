import Foundation

/// Where and how a panel sits in the VR shell. Meters, OpenXR convention: +y up,
/// -z forward from the user's start pose.
public struct MVRPanelPlacement: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var yawDegrees: Float
    public var pitchDegrees: Float
    public var rollDegrees: Float
    /// Panel width in meters; height derives from the panel's point-size aspect.
    public var widthMeters: Float
    /// Cylinder radius in meters that the panel wraps onto; 0 = flat.
    public var curvature: Float
    public var opacity: Float
    public var zOrder: Int32

    public init(x: Float = 0, y: Float = 1.5, z: Float = -1.5,
                yawDegrees: Float = 0, pitchDegrees: Float = 0, rollDegrees: Float = 0,
                widthMeters: Float = 1.0, curvature: Float = 0,
                opacity: Float = 1, zOrder: Int32 = 0) {
        self.x = x; self.y = y; self.z = z
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
        self.rollDegrees = rollDegrees
        self.widthMeters = widthMeters
        self.curvature = curvature
        self.opacity = opacity
        self.zOrder = zOrder
    }

    /// Yaw about world Y, then pitch about local X, then roll about local Z, as the shell does.
    var quat: (Float, Float, Float, Float) {
        let yaw = yawDegrees * .pi / 180, pitch = pitchDegrees * .pi / 180
        let roll = rollDegrees * .pi / 180
        let (sy, cy) = (sin(yaw / 2), cos(yaw / 2))
        let (sp, cp) = (sin(pitch / 2), cos(pitch / 2))
        let (sr, cr) = (sin(roll / 2), cos(roll / 2))
        return (cy * sp * cr + sy * cp * sr,
                sy * cp * cr - cy * sp * sr,
                cy * cp * sr - sy * sp * cr,
                cy * cp * cr + sy * sp * sr)
    }

    /// Inverse of `quat` (Y-X-Z euler, degrees), for adopting grab-moves from VR.
    static func angles(from q: (Float, Float, Float, Float)) -> (yaw: Float, pitch: Float, roll: Float) {
        let (x, y, z, w) = q
        let pitch = asin(max(-1, min(1, -(2 * (y * z - w * x)))))
        let yaw = atan2(2 * (x * z + w * y), 1 - 2 * (x * x + y * y))
        let roll = atan2(2 * (x * y + w * z), 1 - 2 * (x * x + z * z))
        return (yaw * 180 / .pi, pitch * 180 / .pi, roll * 180 / .pi)
    }
}

/// A laser pointer sample on a panel, for `presentSurfacePanel` consumers that do their
/// own input handling. SwiftUI panels get events injected automatically instead.
public struct MVRPointerEvent: Sendable {
    /// 0 = left hand, 1 = right hand.
    public let hand: Int
    /// Normalized panel coordinates; (0,0) is the top-left of the panel's content.
    /// u = v = -1 (with buttons == 0) means the laser left the panel: clear hover and
    /// release anything pressed.
    public let u: Float
    public let v: Float
    public let buttons: UInt32
    public let scrollX: Float
    public let scrollY: Float

    public static let trigger: UInt32 = 1 << 0
    public static let squeeze: UInt32 = 1 << 1
    public static let a: UInt32 = 1 << 2
    public static let b: UInt32 = 1 << 3
    public static let stick: UInt32 = 1 << 4
}

/// Session lifecycle notifications.
public enum MVRShellEvent: Sendable {
    /// Connected to MoltenVR; the shell may or may not be open yet.
    case connected
    case disconnected
    /// The user opened/closed the shell overlay in the headset.
    case shellOpened
    case shellClosed
    /// MoltenVR refused a panel (over budget, bad surface).
    case panelRejected(id: String, reason: MVRRejectReason)
    /// A SwiftUI panel can't render because Screen Recording permission is missing.
    /// Present `MVRScreenRecording` guidance to the user.
    case panelBlocked(id: String)
}

public enum MVRRejectReason: UInt32, Sendable {
    case panelBudget = 1
    case badSurface = 2
    case protocolError = 3
    case unknown = 0
}

public enum MVRSessionState: Sendable {
    case connecting
    case connected
    case disconnected
}
