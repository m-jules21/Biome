import Foundation

// MARK: - Deterministic random

/// SplitMix64 : PRNG déterministe, pour rejouer un monde depuis sa graine.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniforme dans [0, 1).
    mutating func unit() -> Float {
        Float(next() >> 40) * (1.0 / 16_777_216.0)
    }

    mutating func range(_ lower: Float, _ upper: Float) -> Float {
        lower + (upper - lower) * unit()
    }

    mutating func int(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    mutating func chance(_ probability: Float) -> Bool {
        unit() < probability
    }

    mutating func gaussian() -> Float {
        let u1 = max(unit(), 1e-6)
        let u2 = unit()
        return sqrt(-2 * log(u1)) * cos(2 * Float.pi * u2)
    }

    mutating func pick<T>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        return values[int(values.count)]
    }
}

// MARK: - Value noise

/// Bruit de valeur fractal, utilisé pour générer les continents.
struct ValueNoise {
    let seed: UInt64

    init(seed: UInt64) {
        self.seed = seed
    }

    private func hash(_ x: Int, _ y: Int) -> Float {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= seed &* 0x1656_67B1_9E37_79F9
        h ^= h >> 33
        h = h &* 0xFF51_AFD7_ED55_8CCD
        h ^= h >> 33
        return Float(h >> 40) * (1.0 / 16_777_216.0)
    }

    private func smooth(_ t: Float) -> Float {
        t * t * (3 - 2 * t)
    }

    func noise(_ x: Float, _ y: Float) -> Float {
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let fx = smooth(x - Float(x0))
        let fy = smooth(y - Float(y0))
        let a = hash(x0, y0)
        let b = hash(x0 + 1, y0)
        let c = hash(x0, y0 + 1)
        let d = hash(x0 + 1, y0 + 1)
        let top = a + (b - a) * fx
        let bottom = c + (d - c) * fx
        return top + (bottom - top) * fy
    }

    func fbm(_ x: Float, _ y: Float, octaves: Int, persistence: Float) -> Float {
        var amplitude: Float = 1
        var frequency: Float = 1
        var total: Float = 0
        var norm: Float = 0
        for _ in 0..<max(1, octaves) {
            total += noise(x * frequency, y * frequency) * amplitude
            norm += amplitude
            amplitude *= persistence
            frequency *= 2
        }
        return norm > 0 ? total / norm : 0
    }
}

// MARK: - Helpers

@inline(__always)
func clampf(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
    Swift.min(Swift.max(value, lower), upper)
}

@inline(__always)
func lerpf(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

@inline(__always)
func mixf(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * clampf(t, 0, 1)
}
