import Foundation

enum Weather: UInt8, Codable {
    case clear = 0
    case rain = 1
    case drought = 2

    var label: String {
        switch self {
        case .clear: return "Ciel dégagé"
        case .rain: return "Pluie"
        case .drought: return "Sécheresse"
        }
    }

    var icon: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .rain: return "cloud.rain.fill"
        case .drought: return "sun.haze.fill"
        }
    }
}

struct SimStats {
    var herbivores = 0
    var carnivores = 0
    var plantCoverage: Float = 0
    var births = 0
    var deaths = 0
    var generation = 1
    var biodiversity: Float = 0
    var stability: Float = 1
    var time: Double = 0
    var avgSizeH: Float = 1
    var avgSizeC: Float = 1

    var total: Int { herbivores + carnivores }
}

struct HistorySample: Codable {
    var herbivores: Float
    var carnivores: Float
    var plants: Float
}

struct EffectPoint {
    var x: Float
    var y: Float
}

enum WorldNames {
    static let first = ["Vallée", "Delta", "Plateau", "Bassin", "Cratère", "Archipel", "Steppe", "Cuvette", "Hautes-Terres", "Rivage"]
    static let second = ["d'Émeraude", "des Brumes", "du Silence", "des Cendres", "de Miel", "des Orties", "du Sel", "des Lucioles", "de Verre", "des Racines"]

    static func random(_ rng: inout SplitMix64) -> String {
        let a = first[rng.int(first.count)]
        let b = second[rng.int(second.count)]
        return "\(a) \(b)"
    }
}

/// Le moteur de simulation. Tout est déterministe et s'exécute sur le thread principal,
/// à pas fixe (30 Hz), ce qui rend le vivant reproductible et la sauvegarde exacte.
final class Ecosystem {
    static let tickRate: Double = 30
    static let dt: Double = 1.0 / 30.0

    let world: World
    var animals: [Animal] = []
    var rng: SplitMix64
    let seed: UInt64
    var name: String
    var time: Double = 0
    var dayPhase: Float = 0.28
    var weather: Weather = .clear
    var weatherTimer: Float = 40
    var energy: Float = 220

    var stats = SimStats()
    var history: [HistorySample] = []
    var births = 0
    var deaths = 0
    var maxGeneration = 1
    var nextID = 1
    var tickCount = 0
    var herbCount = 0
    var carnCount = 0

    var recentBirths: [EffectPoint] = []
    var recentDeaths: [EffectPoint] = []

    // Grille spatiale (listes chaînées d'indices, zéro allocation par requête).
    var hashHeads: [Int32] = []
    var hashNext: [Int32] = []
    var hashW = 1
    var hashH = 1
    let hashCellSize: Float = 8

    init(seed: UInt64, name: String? = nil) {
        self.seed = seed
        var r = SplitMix64(seed: seed)
        self.rng = r
        self.name = name ?? WorldNames.random(&r)
        self.rng = r
        self.world = World(width: 96, height: 192, seed: seed)
    }

    init(snapshot: EcoSnapshot) {
        seed = snapshot.seed
        var r = SplitMix64(seed: snapshot.seed)
        r.state = snapshot.rngState
        rng = r
        name = snapshot.name
        time = snapshot.time
        dayPhase = snapshot.dayPhase
        weather = Weather(rawValue: snapshot.weather) ?? .clear
        weatherTimer = snapshot.weatherTimer
        energy = snapshot.energy
        world = World(snapshot: snapshot.world)
        animals = snapshot.animals
        births = snapshot.births
        deaths = snapshot.deaths
        maxGeneration = snapshot.maxGeneration
        nextID = snapshot.nextID
        history = snapshot.history
        herbCount = animals.filter { $0.species == .herbivore && $0.alive }.count
        carnCount = animals.filter { $0.species == .carnivore && $0.alive }.count
        stats.herbivores = herbCount
        stats.carnivores = carnCount
        stats.plantCoverage = world.plantCoverage
    }

    func snapshot() -> EcoSnapshot {
        EcoSnapshot(
            seed: seed,
            rngState: rng.state,
            name: name,
            time: time,
            dayPhase: dayPhase,
            weather: weather.rawValue,
            weatherTimer: weatherTimer,
            energy: energy,
            world: world.snapshot(),
            animals: animals,
            births: births,
            deaths: deaths,
            maxGeneration: maxGeneration,
            nextID: nextID,
            history: history
        )
    }

    // MARK: - Cycle d'atmosphère

    var lightLevel: Float {
        let wave = 0.5 + 0.5 * sinf(dayPhase * 2 * Float.pi)
        return clampf(0.26 + 0.74 * wave, 0.22, 1)
    }

    var isNight: Bool { lightLevel < 0.45 }

    var dayLabel: String {
        if lightLevel > 0.75 { return "Jour" }
        if lightLevel > 0.5 { return "Aube" }
        if lightLevel > 0.35 { return "Crépuscule" }
        return "Nuit"
    }

    private func updateWeather(dt: Float) {
        weatherTimer -= dt
        guard weatherTimer <= 0 else { return }
        weatherTimer = rng.range(55, 120)
        let roll = rng.unit()
        if roll < 0.16 {
            weather = .rain
        } else if roll < 0.24 {
            weather = .drought
        } else {
            weather = .clear
        }
    }

    // MARK: - Boucle

    func step() {
        let dt = Float(Ecosystem.dt)
        time += Ecosystem.dt
        tickCount &+= 1
        dayPhase += dt / 150
        if dayPhase >= 1 { dayPhase -= 1 }

        updateWeather(dt: dt)

        let weatherLight: Float = weather == .rain ? 1.22 : (weather == .drought ? 0.38 : 1)
        world.grow(dt: dt, light: lightLevel * weatherLight, chunk: tickCount % 8, chunks: 8)

        if !animals.isEmpty {
            rebuildHash()
            simulate(dt: dt)
        }

        if tickCount % 30 == 0 {
            if weather == .drought {
                world.droughtStress(amount: 0.008)
            } else if weather == .rain {
                // La pluie compense la sécheresse lentement.
            }
            refreshStats()
        }
    }

    // MARK: - Création de vie

    @discardableResult
    func spawn(_ species: Species, x: Float, y: Float, generation: Int = 1, genome: Genome? = nil) -> Bool {
        let cap = species == .herbivore ? Tuning.herbivoreCap : Tuning.carnivoreCap
        let count = species == .herbivore ? herbCount : carnCount
        guard count < cap else { return false }
        let cellX = Int(x / Tuning.cellSize)
        let cellY = Int(y / Tuning.cellSize)
        guard let terrain = Terrain(rawValue: world.terrain[world.index(cellX, cellY)]), terrain.isWalkable else {
            return false
        }
        let g = genome ?? Genome.random(species: species, rng: &rng)
        var animal = Animal.make(
            id: nextID,
            species: species,
            genome: g,
            x: x,
            y: y,
            energy: 1,
            generation: generation,
            rng: &rng
        )
        animal.energy = animal.maxEnergy * 0.82
        animals.append(animal)
        nextID += 1
        if species == .herbivore { herbCount += 1 } else { carnCount += 1 }
        recentBirths.append(EffectPoint(x: x, y: y))
        return true
    }

    /// Point d'apparition valide, tiré au hasard sur une terre émergée.
    func randomLandPoint(attempts: Int = 60) -> EffectPoint? {
        var tries = 0
        while tries < attempts {
            let x = rng.range(8, world.worldWidth - 8)
            let y = rng.range(8, world.worldHeight - 8)
            if world.isWalkable(x: x, y: y) {
                return EffectPoint(x: x, y: y)
            }
            tries += 1
        }
        // Repli : première cellule marchable trouvée.
        for i in stride(from: 0, to: world.terrain.count, by: 7) {
            if let t = Terrain(rawValue: world.terrain[i]), t.isWalkable {
                let x = Float(i % world.width) * Tuning.cellSize + Tuning.cellSize * 0.5
                let y = Float(i / world.width) * Tuning.cellSize + Tuning.cellSize * 0.5
                return EffectPoint(x: x, y: y)
            }
        }
        return nil
    }

    @discardableResult
    func seedLife(herbivores: Int, carnivores: Int) -> Int {
        var placed = 0
        for _ in 0..<herbivores {
            if let p = randomLandPoint(), spawn(.herbivore, x: p.x, y: p.y) { placed += 1 }
        }
        for _ in 0..<carnivores {
            if let p = randomLandPoint(), spawn(.carnivore, x: p.x, y: p.y) { placed += 1 }
        }
        refreshStats()
        return placed
    }

    // MARK: - Interventions du joueur

    func makeRain() {
        weather = .rain
        weatherTimer = 45
        world.rainBoost(amount: 0.05)
    }

    func makeDrought() {
        weather = .drought
        weatherTimer = 40
    }

    func meteor(atX x: Int, atY y: Int, radius: Int) {
        world.crater(centerX: x, centerY: y, radius: radius)
        let cx = Float(x) * Tuning.cellSize
        let cy = Float(y) * Tuning.cellSize
        let r2 = Float(radius * radius) * Tuning.cellSize * Tuning.cellSize
        for i in animals.indices {
            let dx = animals[i].x - cx
            let dy = animals[i].y - cy
            if dx * dx + dy * dy < r2 {
                kill(index: i, detritus: false)
            }
        }
        animals.removeAll { !$0.alive }
    }

    // MARK: - Effets visuels

    func pullEffects() -> (births: [EffectPoint], deaths: [EffectPoint]) {
        let b = recentBirths
        let d = recentDeaths
        recentBirths.removeAll(keepingCapacity: true)
        recentDeaths.removeAll(keepingCapacity: true)
        return (b, d)
    }

    func animalSnapshot(id: Int) -> AnimalSnapshot? {
        guard let a = animals.first(where: { $0.id == id && $0.alive }) else { return nil }
        return AnimalSnapshot(animal: a)
    }

    func closestAnimal(toX x: Float, toY y: Float, maxDistance: Float) -> AnimalSnapshot? {
        var best: Animal?
        var bestD = maxDistance * maxDistance
        for a in animals where a.alive {
            let dx = a.x - x
            let dy = a.y - y
            let d = dx * dx + dy * dy
            if d < bestD {
                bestD = d
                best = a
            }
        }
        guard let found = best else { return nil }
        return AnimalSnapshot(animal: found)
    }

    // MARK: - Statistiques

    func refreshStats() {
        world.recomputeCoverage()
        var h = 0
        var c = 0
        var sizeH: Float = 0
        var sizeC: Float = 0
        var genSum: Int = 0
        var genCount = 0
        var genMax = 1
        for a in animals where a.alive {
            if a.species == .herbivore {
                h += 1
                sizeH += a.genome.size
            } else {
                c += 1
                sizeC += a.genome.size
            }
            genSum += a.generation
            genCount += 1
            genMax = max(genMax, a.generation)
        }
        herbCount = h
        carnCount = c
        maxGeneration = max(maxGeneration, genMax)

        let hN = min(1, Float(h) / 140)
        let cN = min(1, Float(c) / 18)
        let pN = min(1, world.plantCoverage / 0.45)
        let bio = min(1, hN * 0.45 + cN * 0.30 + pN * 0.45)

        let generation = genCount > 0 ? max(1, genSum / genCount) : 1

        stats = SimStats(
            herbivores: h,
            carnivores: c,
            plantCoverage: world.plantCoverage,
            births: births,
            deaths: deaths,
            generation: generation,
            biodiversity: bio,
            stability: stabilityValue(),
            time: time,
            avgSizeH: h > 0 ? sizeH / Float(h) : 1,
            avgSizeC: c > 0 ? sizeC / Float(c) : 1
        )

        energy = min(Tuning.maxEnergy, energy + Tuning.energyBase + bio * Tuning.energyBio)

        history.append(HistorySample(herbivores: Float(h), carnivores: Float(c), plants: world.plantCoverage))
        if history.count > 240 {
            history.removeFirst(history.count - 240)
        }
    }

    private func stabilityValue() -> Float {
        let window = history.suffix(30)
        guard window.count >= 5 else { return 1 }
        let values = window.map { $0.herbivores }
        let mean = values.reduce(0, +) / Float(values.count)
        guard mean > 1 else { return 0 }
        let variance = values.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
        let cv = sqrt(variance) / mean
        return clampf(1 - cv, 0, 1)
    }
}
