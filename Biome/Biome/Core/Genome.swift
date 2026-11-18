import Foundation

/// Le patrimoine génétique d'un organisme.
/// Six traits héréditaires, chacun borné, qui déterminent physiologie et comportement.
struct Genome: Codable, Equatable {
    var size: Float
    var speed: Float
    var sense: Float
    var efficiency: Float
    var fertility: Float
    var aggression: Float
    /// Teinte visuelle (héritée, dérive lentement : on lit l'évolution à l'écran).
    var hue: Float

    static let sizeRange: ClosedRange<Float> = 0.55...1.90
    static let speedRange: ClosedRange<Float> = 0.55...1.75
    static let senseRange: ClosedRange<Float> = 0.50...2.00
    static let efficiencyRange: ClosedRange<Float> = 0.60...1.60
    static let fertilityRange: ClosedRange<Float> = 0.60...1.60
    static let aggressionRange: ClosedRange<Float> = 0.00...1.00

    static func random(species: Species, rng: inout SplitMix64) -> Genome {
        Genome(
            size: rng.range(0.82, 1.22),
            speed: rng.range(0.82, 1.22),
            sense: rng.range(0.85, 1.30),
            efficiency: rng.range(0.90, 1.15),
            fertility: rng.range(0.85, 1.20),
            aggression: species == .carnivore ? rng.range(0.45, 0.90) : rng.range(0.05, 0.30),
            hue: species == .carnivore ? rng.range(0.96, 1.00) : rng.range(0.22, 0.40)
        )
    }

    /// Descendance : chaque trait dérive d'un pas gaussien, puis reste dans son couloir.
    func mutated(_ rng: inout SplitMix64, species: Species, strength: Float = 0.07) -> Genome {
        var g = self
        g.size = clampf(g.size + rng.gaussian() * strength, Genome.sizeRange.lowerBound, Genome.sizeRange.upperBound)
        g.speed = clampf(g.speed + rng.gaussian() * strength, Genome.speedRange.lowerBound, Genome.speedRange.upperBound)
        g.sense = clampf(g.sense + rng.gaussian() * strength, Genome.senseRange.lowerBound, Genome.senseRange.upperBound)
        g.efficiency = clampf(g.efficiency + rng.gaussian() * strength, Genome.efficiencyRange.lowerBound, Genome.efficiencyRange.upperBound)
        g.fertility = clampf(g.fertility + rng.gaussian() * strength, Genome.fertilityRange.lowerBound, Genome.fertilityRange.upperBound)
        g.aggression = clampf(g.aggression + rng.gaussian() * strength, Genome.aggressionRange.lowerBound, Genome.aggressionRange.upperBound)
        // La teinte reste dans le couloir de l'espèce : impossible de devenir bleu.
        let band: ClosedRange<Float> = species == .carnivore ? 0.94...1.00 : 0.18...0.44
        g.hue = clampf(g.hue + rng.gaussian() * 0.02, band.lowerBound, band.upperBound)
        return g
    }

    /// Traits normalisés 0...1, pour le radar de l'inspecteur.
    var normalized: [Float] {
        [
            (size - Genome.sizeRange.lowerBound) / (Genome.sizeRange.upperBound - Genome.sizeRange.lowerBound),
            (speed - Genome.speedRange.lowerBound) / (Genome.speedRange.upperBound - Genome.speedRange.lowerBound),
            (sense - Genome.senseRange.lowerBound) / (Genome.senseRange.upperBound - Genome.senseRange.lowerBound),
            (efficiency - Genome.efficiencyRange.lowerBound) / (Genome.efficiencyRange.upperBound - Genome.efficiencyRange.lowerBound),
            (fertility - Genome.fertilityRange.lowerBound) / (Genome.fertilityRange.upperBound - Genome.fertilityRange.lowerBound),
            aggression
        ]
    }

    static let traitNames = ["Taille", "Vitesse", "Vision", "Métab.", "Fécond.", "Agress."]
}

/// Constantes de simulation. C'est ici qu'on règle l'équilibre de l'écosystème.
enum Tuning {
    /// Taille d'une cellule de terrain, en points SpriteKit.
    static let cellSize: Float = 4

    static let herbivoreSpeed: Float = 17
    static let carnivoreSpeed: Float = 21
    static let baseSense: Float = 16
    static let baseDrain: Float = 0.86
    static let eatRate: Float = 0.42
    static let plantEnergy: Float = 22
    static let herbivoreCap = 600
    static let carnivoreCap = 140
    static let herbivoreCost: Float = 35
    static let carnivoreCost: Float = 100
    static let energyBase: Float = 1.25
    static let energyBio: Float = 2.20
    static let maxEnergy: Float = 999
}
