import Foundation

/// An invertible, viewport-relative approximation of paper rounding over a
/// roller. Text layout remains flat; native drawing and hit testing share this
/// mapping. The writing line below the bend is unchanged.
public struct PaperRollProjection: Equatable, Sendable {
    public let width: Double
    public let bendHeight: Double

    public init(width: Double, viewportHeight: Double) {
        self.width = max(1, width.isFinite ? width : 1)
        self.bendHeight = max(1, min(180, (viewportHeight.isFinite ? max(1, viewportHeight) : 1) * 0.72))
    }

    public func projectY(_ y: Double) -> Double {
        guard y.isFinite else { return 0 }
        if y >= bendHeight { return y }
        let distance = y + bendHeight
        return (distance < 0 ? -1 : 1) * distance * distance / (4 * bendHeight)
    }

    public func unprojectY(_ y: Double) -> Double {
        guard y.isFinite else { return 0 }
        if y >= bendHeight { return y }
        if y < 0 { return -bendHeight - 2 * sqrt(-bendHeight * y) }
        return 2 * sqrt(bendHeight * y) - bendHeight
    }

    public func horizontalScale(at y: Double) -> Double {
        let progress = min(1, max(0, ((y.isFinite ? y : 0) + bendHeight) / (2 * bendHeight)))
        return 0.88 + 0.12 * progress
    }

    public func projectX(_ x: Double, at y: Double) -> Double {
        width / 2 + ((x.isFinite ? x : width / 2) - width / 2) * horizontalScale(at: y)
    }

    public func unprojectX(_ x: Double, at y: Double) -> Double {
        width / 2 + ((x.isFinite ? x : width / 2) - width / 2) / horizontalScale(at: y)
    }
}
