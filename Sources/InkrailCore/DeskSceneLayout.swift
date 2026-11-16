import Foundation

/// One coordinate system for the physical lamp, its desktop pool and the
/// grazing light on the paper. Coordinates are window points, never text
/// offsets, so typing and paper feed cannot move the desk light sources.
public struct DeskSceneLayout: Hashable, Sendable {
    public let windowWidth: Double
    public let windowHeight: Double
    public let paperWidth: Double
    public let paperTop: Double
    public let linen: Bool
    public let isVisible: Bool
    public let lampScale: Double
    public let leftLampX: Double
    public let lampTop: Double

    public static let lampWidth = 160.0
    public static let lampHeight = 270.0
    // Projected from the original 3D asset camera, in its 160 × 270 canvas.
    public static let emitterX = 112.5853
    public static let emitterY = 67.0969
    public static let footX = 46.8735
    public static let footY = 225.5433
    public static let paperReach = 42.0

    public init(windowWidth: Double, windowHeight: Double, paperWidth: Double,
                paperTop: Double = 58, accent: DeskAccent = .brassLamps, enabled: Bool = true) {
        self.windowWidth = windowWidth.isFinite ? max(1, windowWidth) : 1
        self.windowHeight = windowHeight.isFinite ? max(1, windowHeight) : 1
        self.paperWidth = paperWidth.isFinite ? max(1, paperWidth) : 1
        self.paperTop = paperTop.isFinite ? max(0, paperTop) : 58
        self.linen = accent == .linenLamps
        let gutter = max(0, (self.windowWidth - self.paperWidth) / 2)
        isVisible = enabled && gutter >= 156 && self.windowHeight >= 400
        lampScale = min(1.52, max(0.1, (gutter - 44) / Self.lampWidth))
        leftLampX = max(12, gutter - 26 - Self.lampWidth * lampScale)
        lampTop = max(70, min(self.windowHeight - Self.lampHeight * lampScale - 48,
                             self.windowHeight * 0.61 - Self.footY * lampScale))
    }

    public var gutter: Double { max(0, (windowWidth - paperWidth) / 2) }
    public var rightLampX: Double { windowWidth - leftLampX - Self.lampWidth * lampScale }
    public var leftEmitterX: Double { leftLampX + (linen ? 60.0325 : Self.emitterX) * lampScale }
    public var rightEmitterX: Double { windowWidth - leftEmitterX }
    public var emitterY: Double { lampTop + (linen ? 100.1217 : Self.emitterY) * lampScale }
    public var leftFootX: Double { leftLampX + Self.footX * lampScale }
    public var footY: Double { lampTop + Self.footY * lampScale }
    public var edgeLightCenterY: Double { emitterY + 100 * lampScale }

    /// Original projected area-light approximation. The broad source grows
    /// into a soft downward pool with inverse-distance attenuation; there is
    /// no clipped triangle or circular radial halo behind the lamp.
    public static func desktopLight(x: Double, y: Double, linen: Bool = false) -> Double {
        guard x.isFinite, y.isFinite else { return 0 }
        let rise = max(0, y)
        let width = (linen ? 55.0 : 32.0) + rise * (linen ? 0.72 : 0.53)
        let axis = 8 + rise * (linen ? 0.32 : 0.22)
        let cross = (x - axis) / width
        let spread = exp(-1.9 * cross * cross)
        let falloff = 1 / (1 + pow(rise / 158, 2))
        return spread * falloff * smooth(-12, 20, y) * (1 - smooth(235, 370, y))
    }

    /// Paper catches oblique light at its curled outside edge. The field is
    /// bounded to 42pt, before even the narrow 46pt native writing inset.
    public func paperLight(distance: Double, sceneY: Double) -> Double {
        guard isVisible, distance.isFinite, sceneY.isFinite,
              distance >= 0, distance < Self.paperReach else { return 0 }
        let y = (sceneY - emitterY) / lampScale
        let atEdge = Self.desktopLight(x: (gutter - leftEmitterX) / lampScale, y: y, linen: linen)
        let grazing = exp(-distance / 13) * (1 - Self.smooth(27, Self.paperReach, distance))
        return min(1, atEdge * 2.25) * grazing
    }

    private static func smooth(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }
}
