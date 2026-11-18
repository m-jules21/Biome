import Foundation

enum Terrain: UInt8, Codable, CaseIterable {
    case deepWater = 0
    case water = 1
    case sand = 2
    case grass = 3
    case rock = 4

    var isWalkable: Bool { self == .sand || self == .grass }
    var isWater: Bool { self == .deepWater || self == .water }
}

/// Le monde : une grille de cellules (terrain, altitude, humidité, fertilité, biomasse végétale).
final class World {
    let width: Int
    let height: Int
    var terrain: [UInt8]
    var elevation: [Float]
    var moisture: [Float]
    var fertility: [Float]
    var plant: [Float]
    private(set) var plantCoverage: Float = 0
    private(set) var landFraction: Float = 0

    init(width: Int, height: Int, seed: UInt64) {
        self.width = width
        self.height = height
        let count = width * height
        terrain = [UInt8](repeating: Terrain.water.rawValue, count: count)
        elevation = [Float](repeating: 0.4, count: count)
        moisture = [Float](repeating: 0.6, count: count)
        fertility = [Float](repeating: 0.6, count: count)
        plant = [Float](repeating: 0, count: count)
        generate(seed: seed)
    }

    init(snapshot: WorldSnapshot) {
        width = snapshot.width
        height = snapshot.height
        terrain = snapshot.terrain
        elevation = snapshot.elevation
        moisture = snapshot.moisture
        fertility = snapshot.fertility
        plant = snapshot.plant
        recomputeCoverage()
    }

    func snapshot() -> WorldSnapshot {
        WorldSnapshot(
            width: width,
            height: height,
            terrain: terrain,
            elevation: elevation,
            moisture: moisture,
            fertility: fertility,
            plant: plant
        )
    }

    @inline(__always)
    func index(_ x: Int, _ y: Int) -> Int {
        let cx = min(max(x, 0), width - 1)
        let cy = min(max(y, 0), height - 1)
        return cy * width + cx
    }

    @inline(__always)
    func terrainAt(x: Float, y: Float) -> Terrain {
        let cx = Int(x / Tuning.cellSize)
        let cy = Int(y / Tuning.cellSize)
        return Terrain(rawValue: terrain[index(cx, cy)]) ?? .rock
    }

    @inline(__always)
    func isWalkable(x: Float, y: Float) -> Bool {
        terrainAt(x: x, y: y).isWalkable
    }

    var worldWidth: Float { Float(width) * Tuning.cellSize }
    var worldHeight: Float { Float(height) * Tuning.cellSize }

    // MARK: - Génération

    private func generate(seed: UInt64) {
        let noise = ValueNoise(seed: seed)
        let warp = ValueNoise(seed: seed &* 31 &+ 7)

        for y in 0..<height {
            for x in 0..<width {
                let fx = Float(x) / Float(width)
                let fy = Float(y) / Float(height)
                let wx = warp.fbm(fx * 3 + 11, fy * 3, octaves: 2, persistence: 0.5) - 0.5
                let wy = warp.fbm(fx * 3 - 7, fy * 3 + 5, octaves: 2, persistence: 0.5) - 0.5
                let continents = noise.fbm(fx * 3.4 + wx * 0.8, fy * 3.4 + wy * 0.8, octaves: 5, persistence: 0.52)
                let ridges = noise.fbm(fx * 9 + 40, fy * 9 + 11, octaves: 3, persistence: 0.5)
                var e = continents * 0.78 + ridges * 0.22

                // Atténuation vers les bords : le monde est une île.
                let dx = (fx - 0.5) * 2
                let dy = (fy - 0.5) * 2
                let distance = sqrt(dx * dx + dy * dy) * 0.78
                e -= max(0, distance - 0.58) * 0.60

                let i = y * width + x
                elevation[i] = clampf(e, 0, 1)
                moisture[i] = clampf(noise.fbm(fx * 5 + 80, fy * 5 + 20, octaves: 4, persistence: 0.5) * 0.9 + 0.28, 0, 1)
                fertility[i] = clampf(noise.fbm(fx * 6 + 200, fy * 6 + 60, octaves: 3, persistence: 0.55) * 0.7 + 0.35, 0.05, 1)
            }
        }

        for i in 0..<(width * height) {
            let e = elevation[i]
            let t: Terrain
            if e < 0.335 {
                t = .deepWater
            } else if e < 0.435 {
                t = .water
            } else if e < 0.475 {
                t = .sand
            } else if e > 0.815 {
                t = .rock
            } else {
                t = .grass
            }
            terrain[i] = t.rawValue
            if t == .grass {
                plant[i] = (0.18 + moisture[i] * 0.45) * (0.4 + fertility[i])
            } else if t == .sand {
                plant[i] = 0.03
            } else {
                plant[i] = 0
            }
        }
        recomputeCoverage()
    }

    // MARK: - Végétation

    /// La croissance est calculée par tranches : chaque cellule est visitée
    /// quelques fois par seconde au lieu de 30, ce qui laisse le budget CPU aux agents.
    func grow(dt: Float, light: Float, chunk: Int, chunks: Int) {
        let total = width * height
        guard total > 0, chunks > 0 else { return }
        let start = total * chunk / chunks
        let end = total * (chunk + 1) / chunks
        let localDT = dt * Float(chunks)
        var i = start
        while i < end {
            if terrain[i] == Terrain.grass.rawValue {
                let cap = 0.30 + fertility[i] * 0.90
                let p = plant[i]
                if p < cap {
                    let rate = 0.006 * fertility[i] * (0.35 + moisture[i] * 0.9) * light
                    plant[i] = min(cap, p + rate * localDT * (0.45 + p * 0.9))
                }
            }
            i += 1
        }
    }

    func recomputeCoverage() {
        var land: Int = 0
        var covered: Int = 0
        var sum: Float = 0
        for i in 0..<(width * height) {
            let t = Terrain(rawValue: terrain[i]) ?? .rock
            guard t.isWalkable else { continue }
            land += 1
            let p = plant[i]
            sum += min(p, 1)
            if p > 0.06 { covered += 1 }
        }
        landFraction = Float(land) / Float(max(1, width * height))
        plantCoverage = land > 0 ? Float(covered) / Float(land) : 0
        _ = sum
    }

    // MARK: - Terraformation

    /// Applique un pinceau. Renvoie le nombre de cellules réellement modifiées.
    @discardableResult
    func paint(_ target: Terrain, centerX: Int, centerY: Int, radius: Int) -> Int {
        var changed = 0
        let cx = min(max(centerX, 0), width - 1)
        let cy = min(max(centerY, 0), height - 1)
        let r2 = radius * radius
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                let dx = x - cx
                let dy = y - cy
                guard dx * dx + dy * dy <= r2 else { continue }
                let i = y * width + x
                let current = Terrain(rawValue: self.terrain[i]) ?? .rock
                guard current != target || target == .grass || target == .sand else { continue }
                self.terrain[i] = target.rawValue
                switch target {
                case .deepWater, .water:
                    elevation[i] = 0.30
                    plant[i] = 0
                    fertility[i] = max(0.05, fertility[i] * 0.6)
                case .sand:
                    elevation[i] = 0.46
                    plant[i] = min(plant[i], 0.05)
                    moisture[i] = max(moisture[i], 0.35)
                case .grass:
                    elevation[i] = max(elevation[i], 0.50)
                    fertility[i] = max(fertility[i], 0.65)
                    moisture[i] = max(moisture[i], 0.55)
                    if plant[i] < 0.05 { plant[i] = 0.12 }
                case .rock:
                    elevation[i] = 0.86
                    plant[i] = 0
                }
                changed += 1
            }
        }
        if changed > 0 { recomputeCoverage() }
        return changed
    }

    /// Plante un bosquet : la biomasse monte d'un coup sur les cellules herbeuses.
    @discardableResult
    func sow(centerX: Int, centerY: Int, radius: Int) -> Int {
        var changed = 0
        let cx = min(max(centerX, 0), width - 1)
        let cy = min(max(centerY, 0), height - 1)
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                let dx = x - cx
                let dy = y - cy
                guard dx * dx + dy * dy <= radius * radius else { continue }
                let i = y * width + x
                guard terrain[i] == Terrain.grass.rawValue else { continue }
                plant[i] = min(1.4, plant[i] + 0.55)
                fertility[i] = min(1, fertility[i] + 0.10)
                changed += 1
            }
        }
        if changed > 0 { recomputeCoverage() }
        return changed
    }

    /// Creuse un cratère (météore) : tout redevient roche ou eau stérile.
    @discardableResult
    func crater(centerX: Int, centerY: Int, radius: Int) -> Int {
        var changed = 0
        let cx = min(max(centerX, 0), width - 1)
        let cy = min(max(centerY, 0), height - 1)
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                let dx = x - cx
                let dy = y - cy
                let dist = sqrt(Float(dx * dx + dy * dy))
                guard dist <= Float(radius) else { continue }
                let i = y * width + x
                if dist < Float(radius) * 0.45 {
                    terrain[i] = Terrain.water.rawValue
                    elevation[i] = 0.30
                } else if dist > Float(radius) * 0.75 {
                    terrain[i] = Terrain.rock.rawValue
                    elevation[i] = 0.84
                }
                plant[i] = 0
                fertility[i] = max(0.05, fertility[i] * 0.5)
                changed += 1
            }
        }
        if changed > 0 { recomputeCoverage() }
        return changed
    }

    func droughtStress(amount: Float) {
        for i in 0..<(width * height) {
            plant[i] = max(0, plant[i] - amount)
        }
        recomputeCoverage()
    }

    func rainBoost(amount: Float) {
        for i in 0..<(width * height) {
            guard terrain[i] == Terrain.grass.rawValue else { continue }
            moisture[i] = min(1, moisture[i] + amount)
            plant[i] = min(1.4, plant[i] + amount * 0.35)
        }
        recomputeCoverage()
    }
}
