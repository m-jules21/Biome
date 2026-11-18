import Foundation

enum Species: UInt8, Codable, CaseIterable {
    case herbivore = 0
    case carnivore = 1

    var label: String { self == .herbivore ? "Herbivore" : "Carnivore" }
    var icon: String { self == .herbivore ? "hare.fill" : "pawprint.fill" }
    var plural: String { self == .herbivore ? "Herbivores" : "Carnivores" }
}

/// Un individu vivant. Structure compacte : des centaines d'entre eux sont simulés.
struct Animal: Codable {
    var id: Int
    var species: Species
    var genome: Genome
    var x: Float
    var y: Float
    var heading: Float
    var energy: Float
    var age: Float
    var generation: Int
    var cooldown: Float
    var alive: Bool
    var targetX: Float
    var targetY: Float
    var hasTarget: Bool
    var wander: Float
    var children: Int
    var searchTimer: Float

    var maxEnergy: Float {
        let base: Float = species == .herbivore ? 78 : 132
        return base * powf(genome.size, 1.35)
    }

    var lifespan: Float {
        let base: Float = species == .herbivore ? 72 : 96
        return base * (0.72 + 0.55 * genome.efficiency)
    }

    var isAdult: Bool {
        age > (species == .herbivore ? 6 : 12)
    }

    static func make(
        id: Int,
        species: Species,
        genome: Genome,
        x: Float,
        y: Float,
        energy: Float,
        generation: Int,
        rng: inout SplitMix64
    ) -> Animal {
        Animal(
            id: id,
            species: species,
            genome: genome,
            x: x,
            y: y,
            heading: rng.range(0, 2 * .pi),
            energy: energy,
            age: 0,
            generation: generation,
            cooldown: rng.range(4, 9),
            alive: true,
            targetX: x,
            targetY: y,
            hasTarget: false,
            wander: rng.range(0, 10),
            children: 0,
            searchTimer: 0
        )
    }
}

/// Photographie d'un individu pour l'interface (l'inspecteur ne touche jamais la sim).
struct AnimalSnapshot: Identifiable, Equatable {
    let id: Int
    let species: Species
    let generation: Int
    let age: Float
    let energy: Float
    let maxEnergy: Float
    let genome: Genome
    let children: Int
    let x: Float
    let y: Float

    var energyRatio: Float { maxEnergy > 0 ? clampf(energy / maxEnergy, 0, 1) : 0 }
    var ageRatio: Float { clampf(age / 120, 0, 1) }

    init(animal: Animal) {
        id = animal.id
        species = animal.species
        generation = animal.generation
        age = animal.age
        energy = animal.energy
        maxEnergy = animal.maxEnergy
        genome = animal.genome
        children = animal.children
        x = animal.x
        y = animal.y
    }
}
