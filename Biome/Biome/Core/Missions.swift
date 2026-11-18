import Foundation

/// Une mission de campagne. Elle s'évalue en continu sur l'état réel de l'écosystème.
struct Mission: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let goal: String
    let icon: String
    let reward: Float
    /// Durée pendant laquelle la condition doit tenir (0 = instantané).
    let hold: Float
    let progress: (Ecosystem) -> Float
}

enum Missions {
    static let all: [Mission] = [
        Mission(
            id: 1,
            title: "Premier souffle",
            detail: "La vie tient à un fil. Amène le premier troupeau à 40 individus.",
            goal: "40 herbivores",
            icon: "hare.fill",
            reward: 60,
            hold: 0
        ) { eco in
            Float(eco.stats.herbivores) / 40
        },
        Mission(
            id: 2,
            title: "Herbiers",
            detail: "Sans couvert végétal, rien ne broute. Fais verdir le sol.",
            goal: "35 % de couverture végétale",
            icon: "leaf.fill",
            reward: 70,
            hold: 0
        ) { eco in
            eco.stats.plantCoverage / 0.35
        },
        Mission(
            id: 3,
            title: "Premier prédateur",
            detail: "Introduis trois carnivores et maintiens-les en vie.",
            goal: "3 carnivores",
            icon: "pawprint.fill",
            reward: 100,
            hold: 0
        ) { eco in
            Float(eco.stats.carnivores) / 3
        },
        Mission(
            id: 4,
            title: "Sélection naturelle",
            detail: "Laisse les générations se succéder : l'évolution travaille pour toi.",
            goal: "Génération 12",
            icon: "dna",
            reward: 90,
            hold: 0
        ) { eco in
            Float(eco.maxGeneration) / 12
        },
        Mission(
            id: 5,
            title: "Équilibre",
            detail: "Un troupeau nombreux, un sol vert, et de la patience.",
            goal: "120 herbivores + 20 % de plantes, 15 s",
            icon: "arrow.triangle.2.circlepath",
            reward: 140,
            hold: 15
        ) { eco in
            min(Float(eco.stats.herbivores) / 120, eco.stats.plantCoverage / 0.20)
        },
        Mission(
            id: 6,
            title: "Chaîne trophique",
            detail: "Les herbivores mangent les plantes, les carnivores mangent les herbivores.",
            goal: "180 herbivores + 6 carnivores, 15 s",
            icon: "link",
            reward: 160,
            hold: 15
        ) { eco in
            min(Float(eco.stats.herbivores) / 180, Float(eco.stats.carnivores) / 6)
        },
        Mission(
            id: 7,
            title: "Éden",
            detail: "Un biome dense, vert, avec de grands prédateurs.",
            goal: "300 herb. + 12 carn. + 50 % plantes",
            icon: "crown.fill",
            reward: 220,
            hold: 0
        ) { eco in
            min(Float(eco.stats.herbivores) / 300, Float(eco.stats.carnivores) / 12, eco.stats.plantCoverage / 0.50)
        },
        Mission(
            id: 8,
            title: "Symbiose",
            detail: "Prouve que ton écosystème peut tenir une minute sans s'effondrer.",
            goal: "200 herb. + 10 carn. stables, 60 s",
            icon: "infinity",
            reward: 300,
            hold: 60
        ) { eco in
            min(Float(eco.stats.herbivores) / 200, Float(eco.stats.carnivores) / 10)
        }
    ]

    static func mission(id: Int) -> Mission? {
        all.first { $0.id == id }
    }
}

/// Suit la progression et les temps de maintien, et rend les missions accomplies.
final class MissionTracker {
    var completed: Set<Int> = []
    private var held: [Int: Float] = [:]

    func load(from ids: [Int]) {
        completed = Set(ids)
    }

    func progress(for mission: Mission, eco: Ecosystem) -> Float {
        clampf(mission.progress(eco), 0, 1)
    }

    func holdProgress(for mission: Mission) -> Float {
        guard mission.hold > 0 else { return 1 }
        return clampf((held[mission.id] ?? 0) / mission.hold, 0, 1)
    }

    /// Avance d'un pas de simulation. Renvoie les missions terminées à cet instant.
    func update(eco: Ecosystem, dt: Float) -> [Mission] {
        var finished: [Mission] = []
        for mission in Missions.all where !completed.contains(mission.id) {
            let value = clampf(mission.progress(eco), 0, 1)
            if value >= 0.999 {
                let total = (held[mission.id] ?? 0) + dt
                held[mission.id] = total
                if total >= mission.hold {
                    completed.insert(mission.id)
                    held[mission.id] = 0
                    finished.append(mission)
                }
            } else {
                held[mission.id] = 0
            }
        }
        return finished
    }

    var next: Mission? {
        Missions.all.first { !completed.contains($0.id) }
    }
}
