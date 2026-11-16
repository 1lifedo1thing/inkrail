import CoreGraphics
import Foundation
import SwiftUI

/// An original, seamless leather micro-surface. The cached height field uses
/// irregular cellular creases, not a photograph or a repeated drawn motif.
/// Place it over the desk's colour/light layers so lit areas reveal its grain.
@MainActor
struct DeskLeatherSurface: View {
    var strength: Double = 1

    var body: some View {
        Group {
            if let grain = LeatherGrain.image {
                Image(decorative: grain, scale: 2)
                    .resizable(resizingMode: .tile)
                    .interpolation(.high)
                    .blendMode(.softLight)
                    .opacity(0.66 * min(1, max(0, strength)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum LeatherGrain {
    static let side = 512
    static let image: CGImage? = makeImage()

    /// Stable hash values wrap at each lattice's period. The generated image
    /// therefore tiles without a seam, including its finite-difference normals.
    private static func random(_ x: Int, _ y: Int, period: Int, seed: UInt64) -> Double {
        let column = (x % period + period) % period
        let row = (y % period + period) % period
        var value = UInt64(column + row * 4099) &* 0x9E3779B185EBCA87 &+ seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Double((value ^ (value >> 31)) & 0xFFFF) / 65535
    }

    private static func noise(_ x: Double, _ y: Double, period: Int, seed: UInt64) -> Double {
        let column = Int(floor(x)), row = Int(floor(y))
        let dx = x - floor(x), dy = y - floor(y)
        let u = dx * dx * (3 - 2 * dx), v = dy * dy * (3 - 2 * dy)
        let a = random(column, row, period: period, seed: seed)
        let b = random(column + 1, row, period: period, seed: seed)
        let c = random(column, row + 1, period: period, seed: seed)
        let d = random(column + 1, row + 1, period: period, seed: seed)
        return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
    }

    /// Distance between the closest two irregular cell sites forms narrow,
    /// branching valleys. Warping the sample positions softens polygon edges.
    private static func creaseDistance(_ x: Double, _ y: Double, period: Int, seed: UInt64) -> Double {
        let column = Int(floor(x)), row = Int(floor(y))
        var nearest = Double.infinity
        var next = Double.infinity
        for j in -1...1 {
            for i in -1...1 {
                let cx = column + i, cy = row + j
                let dx = Double(cx) + 0.04 + random(cx, cy, period: period, seed: seed) * 0.92 - x
                let dy = Double(cy) + 0.04 + random(cx, cy, period: period, seed: seed + 37) * 0.92 - y
                let distance = dx * dx + dy * dy
                if distance < nearest { next = nearest; nearest = distance }
                else if distance < next { next = distance }
            }
        }
        return sqrt(next) - sqrt(nearest)
    }

    private static func height(x: Double, y: Double) -> Double {
        let warpX = (noise(x / 32, y / 32, period: 16, seed: 13) - 0.5) * 10
            + (noise(x / 16, y / 16, period: 32, seed: 23) - 0.5) * 2.5
        let warpY = (noise(x / 32, y / 32, period: 16, seed: 41) - 0.5) * 10
            + (noise(x / 16, y / 16, period: 32, seed: 53) - 0.5) * 2.5
        let fine = creaseDistance((x + warpX) / 8, (y + warpY) / 8, period: 64, seed: 71)
        let broad = creaseDistance((x + warpY * 2) / 32, (y + warpX * 2) / 32, period: 16, seed: 113)
        let pebble = (1 - exp(-fine * 3.4)) * 0.66
        let fold = exp(-broad * 24) * 0.09
        let pores = noise(x / 2, y / 2, period: 256, seed: 149) * 0.028
        return pebble - fold + pores
    }

    private static func makeImage() -> CGImage? {
        var heights = [Double](repeating: 0, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                heights[y * side + x] = height(x: Double(x), y: Double(y))
            }
        }
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let left = heights[y * side + (x + side - 1) % side]
                let right = heights[y * side + (x + 1) % side]
                let above = heights[((y + side - 1) % side) * side + x]
                let below = heights[((y + 1) % side) * side + x]
                let nx = (left - right) * 1.5
                let ny = (above - below) * 1.5
                let nz = 1 / sqrt(nx * nx + ny * ny + 1)
                // Low-angle room light brings out rounded peaks and valleys;
                // a tiny occlusion term darkens creases without outlining them.
                let slope = (nx * -0.56 + ny * -0.73 + 0.39) * nz - 0.39
                let h = heights[y * side + x]
                let occlusion = min(0, h - 0.19) * 0.21
                let mottling = (noise(Double(x) / 64, Double(y) / 64, period: 8, seed: 181) - 0.5) * 0.025
                let value = min(0.76, max(0.25, 0.505 + slope * 0.57 + occlusion + mottling))
                let grey = UInt8((value * 255).rounded())
                let offset = (y * side + x) * 4
                bytes[offset] = grey
                bytes[offset + 1] = grey
                bytes[offset + 2] = grey
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
