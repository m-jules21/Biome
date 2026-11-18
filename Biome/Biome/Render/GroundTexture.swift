import UIKit

struct RGB {
    var r: Float
    var g: Float
    var b: Float

    func mixed(with other: RGB, _ t: Float) -> RGB {
        let k = clampf(t, 0, 1)
        return RGB(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k)
    }

    func lightened(_ amount: Float) -> RGB {
        RGB(r: clampf(r + amount, 0, 1), g: clampf(g + amount, 0, 1), b: clampf(b + amount, 0, 1))
    }

    var color: UIColor {
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}

enum Palette {
    static let ocean = RGB(r: 0.035, g: 0.075, b: 0.145)
    static let deepWater = RGB(r: 0.045, g: 0.115, b: 0.205)
    static let shallowWater = RGB(r: 0.080, g: 0.265, b: 0.315)
    static let foam = RGB(r: 0.56, g: 0.78, b: 0.76)
    static let sand = RGB(r: 0.760, g: 0.690, b: 0.500)
    static let grass = RGB(r: 0.215, g: 0.345, b: 0.180)
    static let grassRich = RGB(r: 0.365, g: 0.590, b: 0.245)
    static let forest = RGB(r: 0.145, g: 0.300, b: 0.145)
    static let rock = RGB(r: 0.365, g: 0.365, b: 0.395)
    static let rockLight = RGB(r: 0.470, g: 0.470, b: 0.500)

    static func base(for terrain: Terrain) -> RGB {
        switch terrain {
        case .deepWater: return deepWater
        case .water: return shallowWater
        case .sand: return sand
        case .grass: return grass
        case .rock: return rock
        }
    }
}

/// Construit la texture du sol (une image par cellule) : terrain + biomasse + grain + houle.
enum GroundTexture {
    static func image(for world: World, phase: Float) -> CGImage? {
        let width = world.width
        let height = world.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var noise = SplitMix64(seed: 0x5EED_1234)
        let grain = (0..<1024).map { _ in Float(noise.unit()) - 0.5 }

        let time = phase * 6.28318

        for y in 0..<height {
            let flipped = height - 1 - y
            for x in 0..<width {
                let index = y * width + x
                let terrain = Terrain(rawValue: world.terrain[index]) ?? .rock
                var color = Palette.base(for: terrain)
                let p = world.plant[index]
                let n = grain[(index &* 31) & 1023]

                switch terrain {
                case .deepWater, .water:
                    let ripple = sinf(Float(x) * 0.32 + Float(y) * 0.19 + time) * 0.5 + 0.5
                    color = color.lightened(ripple * 0.030 + n * 0.012)
                    // Écume sur les côtes.
                    var coast = false
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx
                        let ny = y + dy
                        if nx >= 0, ny >= 0, nx < width, ny < height {
                            let neighbour = Terrain(rawValue: world.terrain[ny * width + nx]) ?? .rock
                            if neighbour.isWalkable { coast = true }
                        }
                    }
                    if coast {
                        color = color.mixed(with: Palette.foam, 0.16 + ripple * 0.06)
                    }
                case .sand:
                    color = color.lightened(n * 0.045 + (p > 0.1 ? 0.02 : 0))
                case .grass:
                    let rich = clampf(p / 1.1, 0, 1)
                    color = color.mixed(with: Palette.grassRich, rich * 0.92)
                    if p > 0.75 {
                        color = color.mixed(with: Palette.forest, (p - 0.75) * 1.8)
                    }
                    color = color.lightened(n * 0.05)
                    if world.fertility[index] < 0.3 {
                        color = color.mixed(with: Palette.sand, 0.25)
                    }
                case .rock:
                    color = color.lightened(n * 0.075 + (world.elevation[index] > 0.9 ? 0.10 : 0))
                }

                let offset = (flipped * width + x) * 4
                pixels[offset] = UInt8(clampf(color.r * 255, 0, 255))
                pixels[offset + 1] = UInt8(clampf(color.g * 255, 0, 255))
                pixels[offset + 2] = UInt8(clampf(color.b * 255, 0, 255))
                pixels[offset + 3] = 255
            }
        }

        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            return context.makeImage()
        }
    }
}
