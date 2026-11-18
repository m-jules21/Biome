import Foundation

/// Comportements individuels : recherche de nourriture, fuite, chasse, reproduction, mort.
/// Rien n'est scripté au niveau de la population : les cycles émergent des règles locales.
extension Ecosystem {

    // MARK: - Grille spatiale

    func rebuildHash() {
        let w = max(1, Int(ceil(world.worldWidth / hashCellSize)))
        let h = max(1, Int(ceil(world.worldHeight / hashCellSize)))
        if hashW != w || hashH != h || hashHeads.count != w * h {
            hashW = w
            hashH = h
            hashHeads = [Int32](repeating: -1, count: w * h)
        } else {
            for i in 0..<hashHeads.count { hashHeads[i] = -1 }
        }
        if hashNext.count < animals.count {
            hashNext = [Int32](repeating: -1, count: animals.count)
        } else {
            for i in 0..<animals.count { hashNext[i] = -1 }
        }
        for i in 0..<animals.count {
            let a = animals[i]
            guard a.alive else { continue }
            let bx = min(hashW - 1, max(0, Int(a.x / hashCellSize)))
            let by = min(hashH - 1, max(0, Int(a.y / hashCellSize)))
            let bucket = by * hashW + bx
            hashNext[i] = hashHeads[bucket]
            hashHeads[bucket] = Int32(i)
        }
    }

    func nearestPrey(of species: Species, to a: Animal, radius: Float) -> Int? {
        var best = -1
        var bestDistance = radius * radius
        let minBX = max(0, Int((a.x - radius) / hashCellSize))
        let maxBX = min(hashW - 1, Int((a.x + radius) / hashCellSize))
        let minBY = max(0, Int((a.y - radius) / hashCellSize))
        let maxBY = min(hashH - 1, Int((a.y + radius) / hashCellSize))
        guard minBX <= maxBX, minBY <= maxBY else { return nil }
        for by in minBY...maxBY {
            let row = by * hashW
            for bx in minBX...maxBX {
                var index = hashHeads[row + bx]
                while index >= 0 {
                    let j = Int(index)
                    guard j < animals.count, j < hashNext.count else { break }
                    index = hashNext[j]
                    let other = animals[j]
                    guard other.alive, other.species == species, other.id != a.id else { continue }
                    let dx = other.x - a.x
                    let dy = other.y - a.y
                    let d = dx * dx + dy * dy
                    if d < bestDistance {
                        bestDistance = d
                        best = j
                    }
                }
            }
        }
        return best >= 0 ? best : nil
    }

    // MARK: - Boucle des agents

    func simulate(dt: Float) {
        let count = animals.count
        var i = 0
        while i < count {
            if animals[i].alive {
                if animals[i].species == .herbivore {
                    updateHerbivore(i, dt: dt)
                } else {
                    updateCarnivore(i, dt: dt)
                }
            }
            i += 1
        }
        pruneDead()
    }

    func pruneDead() {
        guard animals.contains(where: { !$0.alive }) else { return }
        animals.removeAll { !$0.alive }
    }

    // MARK: - Herbivores

    func updateHerbivore(_ i: Int, dt: Float) {
        guard i < animals.count else { return }
        var a = animals[i]
        a.age += dt
        a.cooldown = max(0, a.cooldown - dt)
        a.searchTimer -= dt
        a.wander += dt * 2.2

        let drain = Tuning.baseDrain * powf(a.genome.size, 0.8) * (1.9 - a.genome.efficiency)
        a.energy -= drain * dt

        let sense = Tuning.baseSense * a.genome.sense
        var desireX: Float = 0
        var desireY: Float = 0
        var fleeing = false

        if carnCount > 0, let predatorIndex = nearestPrey(of: .carnivore, to: a, radius: sense * 1.25) {
            let p = animals[predatorIndex]
            let dx = a.x - p.x
            let dy = a.y - p.y
            let d = max(1, sqrtf(dx * dx + dy * dy))
            desireX = dx / d
            desireY = dy / d
            fleeing = true
            a.hasTarget = false
        } else {
            let cell = world.index(Int(a.x / Tuning.cellSize), Int(a.y / Tuning.cellSize))
            if world.plant[cell] > 0.02 {
                let bite = min(world.plant[cell], Tuning.eatRate * dt)
                world.plant[cell] -= bite
                a.energy += bite * Tuning.plantEnergy
                a.hasTarget = false
            } else if a.searchTimer <= 0 || !a.hasTarget {
                if let target = bestPlantCell(from: a, radius: sense) {
                    a.targetX = target.x
                    a.targetY = target.y
                    a.hasTarget = true
                } else {
                    a.hasTarget = false
                }
                a.searchTimer = rng.range(0.45, 0.9)
            }
            if a.hasTarget {
                let dx = a.targetX - a.x
                let dy = a.targetY - a.y
                let d = max(1, sqrtf(dx * dx + dy * dy))
                if d < Tuning.cellSize { a.hasTarget = false }
                desireX = dx / d
                desireY = dy / d
            }
        }

        if desireX == 0 && desireY == 0 {
            a.wander += dt * 3
            let wiggle = a.heading + sinf(a.wander) * 1.1
            desireX = cosf(wiggle)
            desireY = sinf(wiggle)
        }

        let speed = Tuning.herbivoreSpeed * a.genome.speed / powf(a.genome.size, 0.32) * (fleeing ? 1.45 : 1)
        move(&a, dx: desireX, dy: desireY, speed: speed, dt: dt)
        a.energy = min(a.energy, a.maxEnergy)

        animals[i] = a
        if a.energy <= 0 || a.age > a.lifespan {
            kill(index: i, detritus: true)
            return
        }
        tryReproduce(i)
    }

    // MARK: - Carnivores

    func updateCarnivore(_ i: Int, dt: Float) {
        guard i < animals.count else { return }
        var a = animals[i]
        a.age += dt
        a.cooldown = max(0, a.cooldown - dt)
        a.searchTimer -= dt
        a.wander += dt * 1.9

        let drain = Tuning.baseDrain * 1.55 * powf(a.genome.size, 0.85) * (1.9 - a.genome.efficiency)
        a.energy -= drain * dt

        let sense = Tuning.baseSense * a.genome.sense * 1.55 * (isNight ? 1.3 : 1)
        var desireX: Float = 0
        var desireY: Float = 0

        if let preyIndex = nearestPrey(of: .herbivore, to: a, radius: sense) {
            let prey = animals[preyIndex]
            let dx = prey.x - a.x
            let dy = prey.y - a.y
            let d = max(0.001, sqrtf(dx * dx + dy * dy))
            desireX = dx / d
            desireY = dy / d
            a.hasTarget = true
            a.targetX = prey.x
            a.targetY = prey.y
            let reach = Tuning.cellSize * (0.9 + 0.45 * a.genome.size)
            if d < reach {
                attack(index: i, prey: preyIndex)
                // L'attaque peut avoir tué l'un des deux : on relit l'individu.
                if i < animals.count, animals[i].alive {
                    a = animals[i]
                }
            }
        } else if a.hasTarget {
            let dx = a.targetX - a.x
            let dy = a.targetY - a.y
            let d = max(1, sqrtf(dx * dx + dy * dy))
            desireX = dx / d
            desireY = dy / d
            if d < Tuning.cellSize { a.hasTarget = false }
        } else {
            let wiggle = a.heading + sinf(a.wander) * 1.2
            desireX = cosf(wiggle)
            desireY = sinf(wiggle)
        }

        let speed = Tuning.carnivoreSpeed * a.genome.speed / powf(a.genome.size, 0.28)
        move(&a, dx: desireX, dy: desireY, speed: speed, dt: dt)
        a.energy = min(a.energy, a.maxEnergy)

        guard i < animals.count else { return }
        animals[i] = a
        if a.energy <= 0 || a.age > a.lifespan {
            kill(index: i, detritus: true)
            return
        }
        tryReproduce(i)
    }

    // MARK: - Combat

    func attack(index: Int, prey preyIndex: Int) {
        guard index < animals.count, preyIndex < animals.count else { return }
        guard animals[index].alive, animals[preyIndex].alive else { return }
        var hunter = animals[index]
        var victim = animals[preyIndex]

        let damage = 32 + 46 * hunter.genome.size * (0.65 + 0.35 * hunter.genome.aggression)
        victim.energy -= damage

        if victim.energy <= 0 {
            hunter.energy = min(hunter.maxEnergy, hunter.energy + victim.maxEnergy * 0.62)
            kill(index: preyIndex, detritus: true)
        } else {
            victim.heading += Float.pi
            victim.hasTarget = false
            animals[preyIndex] = victim
        }
        animals[index] = hunter
    }

    // MARK: - Déplacement

    func move(_ a: inout Animal, dx: Float, dy: Float, speed: Float, dt: Float) {
        var hx = dx
        var hy = dy
        let length = sqrtf(hx * hx + hy * hy)
        if length > 0.0001 {
            hx /= length
            hy /= length
        } else {
            hx = cosf(a.heading)
            hy = sinf(a.heading)
        }

        // L'animal est-il sur une terre ferme ? Sinon, il rejoint la rive la plus proche.
        if !world.isWalkable(x: a.x, y: a.y), let escape = escapeVector(from: a) {
            hx = escape.0
            hy = escape.1
        }

        let target = atan2f(hy, hx)
        var diff = target - a.heading
        while diff > Float.pi { diff -= 2 * Float.pi }
        while diff < -Float.pi { diff += 2 * Float.pi }
        let turn = min(1, dt * (a.species == .carnivore ? 9 : 6))
        a.heading += diff * turn

        let step = speed * dt
        let nx = a.x + cosf(a.heading) * step
        let ny = a.y + sinf(a.heading) * step
        let maxX = world.worldWidth - 2
        let maxY = world.worldHeight - 2
        let clampedX = clampf(nx, 2, maxX)
        let clampedY = clampf(ny, 2, maxY)

        if world.isWalkable(x: clampedX, y: clampedY) {
            a.x = clampedX
            a.y = clampedY
        } else if world.isWalkable(x: clampedX, y: a.y) {
            a.x = clampedX
        } else if world.isWalkable(x: a.x, y: clampedY) {
            a.y = clampedY
        } else {
            a.heading += Float.pi * 0.7
            a.hasTarget = false
        }
    }

    func escapeVector(from a: Animal) -> (Float, Float)? {
        let cx = Int(a.x / Tuning.cellSize)
        let cy = Int(a.y / Tuning.cellSize)
        for radius in 1...8 {
            for step in 0..<12 {
                let angle = Float(step) * Float.pi / 6
                let x = cx + Int(cosf(angle) * Float(radius))
                let y = cy + Int(sinf(angle) * Float(radius))
                let px = Float(x) * Tuning.cellSize + Tuning.cellSize * 0.5
                let py = Float(y) * Tuning.cellSize + Tuning.cellSize * 0.5
                if world.isWalkable(x: px, y: py) {
                    return (Float(x - cx), Float(y - cy))
                }
            }
        }
        return nil
    }

    // MARK: - Nourriture

    func bestPlantCell(from a: Animal, radius: Float) -> EffectPoint? {
        let cellRadius = max(1, Int(radius / Tuning.cellSize))
        let cx = Int(a.x / Tuning.cellSize)
        let cy = Int(a.y / Tuning.cellSize)
        var best: Float = 0.06
        var bestX = -1
        var bestY = -1
        var tries = 0
        while tries < 12 {
            let ox = rng.int(cellRadius * 2 + 1) - cellRadius
            let oy = rng.int(cellRadius * 2 + 1) - cellRadius
            let x = cx + ox
            let y = cy + oy
            if x >= 0, y >= 0, x < world.width, y < world.height {
                let index = y * world.width + x
                if world.terrain[index] == Terrain.grass.rawValue {
                    let p = world.plant[index]
                    if p > best {
                        best = p
                        bestX = x
                        bestY = y
                    }
                }
            }
            tries += 1
        }
        guard bestX >= 0 else { return nil }
        return EffectPoint(
            x: (Float(bestX) + 0.5) * Tuning.cellSize,
            y: (Float(bestY) + 0.5) * Tuning.cellSize
        )
    }

    // MARK: - Reproduction

    func tryReproduce(_ i: Int) {
        guard i < animals.count else { return }
        var a = animals[i]
        guard a.alive, a.isAdult, a.cooldown <= 0 else { return }
        let cap = a.species == .herbivore ? Tuning.herbivoreCap : Tuning.carnivoreCap
        let population = a.species == .herbivore ? herbCount : carnCount
        guard population < cap, a.energy > a.maxEnergy * 0.68 else { return }

        let genome = a.genome.mutated(&rng, species: a.species)
        let offsetX = rng.range(-8, 8)
        let offsetY = rng.range(-8, 8)
        var child = Animal.make(
            id: nextID,
            species: a.species,
            genome: genome,
            x: a.x + offsetX,
            y: a.y + offsetY,
            energy: 1,
            generation: a.generation + 1,
            rng: &rng
        )
        child.x = clampf(child.x, 3, world.worldWidth - 3)
        child.y = clampf(child.y, 3, world.worldHeight - 3)
        if !world.isWalkable(x: child.x, y: child.y) {
            child.x = a.x
            child.y = a.y
        }
        child.energy = child.maxEnergy * 0.46
        child.cooldown = rng.range(9, 15)

        a.energy *= 0.52
        a.cooldown = max(4, 16 * (1.5 - a.genome.fertility))
        a.children += 1

        animals[i] = a
        animals.append(child)
        nextID += 1
        births += 1
        if child.species == .herbivore { herbCount += 1 } else { carnCount += 1 }
        maxGeneration = max(maxGeneration, child.generation)

        recentBirths.append(EffectPoint(x: child.x, y: child.y))
        if recentBirths.count > 60 {
            recentBirths.removeFirst(recentBirths.count - 60)
        }
    }

    // MARK: - Mort

    func kill(index: Int, detritus: Bool) {
        guard index >= 0, index < animals.count, animals[index].alive else { return }
        let victim = animals[index]
        animals[index].alive = false
        animals[index].energy = 0
        if victim.species == .herbivore {
            herbCount = max(0, herbCount - 1)
        } else {
            carnCount = max(0, carnCount - 1)
        }
        deaths += 1
        recentDeaths.append(EffectPoint(x: victim.x, y: victim.y))
        if recentDeaths.count > 60 {
            recentDeaths.removeFirst(recentDeaths.count - 60)
        }
        if detritus {
            let cell = world.index(Int(victim.x / Tuning.cellSize), Int(victim.y / Tuning.cellSize))
            world.fertility[cell] = min(1, world.fertility[cell] + 0.22)
            world.plant[cell] = min(1.4, world.plant[cell] + 0.16)
        }
    }
}
