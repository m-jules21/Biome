import Foundation
import Combine
import SwiftUI
import UIKit

enum Screen {
    case menu
    case playing
}

enum Tool: String, CaseIterable, Identifiable {
    case inspect
    case water
    case rock
    case plant
    case herbivore
    case carnivore
    case meteor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inspect: return "Observer"
        case .water: return "Eau"
        case .rock: return "Roche"
        case .plant: return "Semer"
        case .herbivore: return "Herbivore"
        case .carnivore: return "Carnivore"
        case .meteor: return "Météore"
        }
    }

    var icon: String {
        switch self {
        case .inspect: return "hand.point.up.left.fill"
        case .water: return "drop.fill"
        case .rock: return "mountain.2.fill"
        case .plant: return "leaf.fill"
        case .herbivore: return "hare.fill"
        case .carnivore: return "pawprint.fill"
        case .meteor: return "sparkles"
        }
    }

    var short: String {
        switch self {
        case .inspect: return "Voir"
        case .water: return "Eau"
        case .rock: return "Roche"
        case .plant: return "Semer"
        case .herbivore: return "Herb."
        case .carnivore: return "Carn."
        case .meteor: return "Météore"
        }
    }

    var cost: Float {
        switch self {
        case .inspect: return 0
        case .water: return 0.8
        case .rock: return 1.0
        case .plant: return 0.9
        case .herbivore: return Tuning.herbivoreCost
        case .carnivore: return Tuning.carnivoreCost
        case .meteor: return 90
        }
    }

    var tint: Color {
        switch self {
        case .inspect: return Color(red: 0.62, green: 0.78, blue: 0.95)
        case .water: return Color(red: 0.30, green: 0.66, blue: 0.95)
        case .rock: return Color(red: 0.65, green: 0.65, blue: 0.70)
        case .plant: return Color(red: 0.42, green: 0.82, blue: 0.45)
        case .herbivore: return Color(red: 0.55, green: 0.90, blue: 0.68)
        case .carnivore: return Color(red: 0.98, green: 0.45, blue: 0.38)
        case .meteor: return Color(red: 0.98, green: 0.78, blue: 0.35)
        }
    }
}

enum GameSpeed: Float, CaseIterable, Identifiable {
    case half = 0.5
    case normal = 1
    case fast = 2
    case ultra = 4

    var id: Float { rawValue }
    var label: String {
        switch self {
        case .half: return "×0,5"
        case .normal: return "×1"
        case .fast: return "×2"
        case .ultra: return "×4"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let icon: String
}

final class GameModel: ObservableObject {
    // Navigation
    @Published var screen: Screen = .menu
    @Published var showMissions = false
    @Published var showSettings = false
    @Published var showStats = false
    @Published var hasSave = false

    // Simulation exposée à l'interface
    @Published var stats = SimStats()
    @Published var energy: Float = 220
    @Published var history: [HistorySample] = []
    @Published var dayPhase: Float = 0.3
    @Published var weather: Weather = .clear
    @Published var worldName = ""
    @Published var isPaused = false
    @Published var speed: GameSpeed = .normal
    @Published var tool: Tool = .inspect
    @Published var selected: AnimalSnapshot?
    @Published var toast: ToastMessage?
    @Published var completedMissions: Set<Int> = []
    @Published var missionProgress: [Int: Float] = [:]

    var eco: Ecosystem
    let tracker = MissionTracker()
    weak var scene: WorldScene?

    private var accumulator: Double = 0
    private var toastGeneration = 0
    private let defaults = UserDefaults.standard
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    private let heavyFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var lastBrushRefusal = Date.distantPast

    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "biome.haptics") as? Bool ?? true
    }

    init() {
        let seed = UInt64.random(in: 1...UInt64.max)
        eco = Ecosystem(seed: seed)
        worldName = eco.name
        hasSave = SaveStore.exists()
        if let save = SaveStore.load() {
            completedMissions = Set(save.completedMissions)
            tracker.load(from: save.completedMissions)
        }
        selectionFeedback.prepare()
        impactFeedback.prepare()
        heavyFeedback.prepare()
    }

    // MARK: - Cycle de vie

    func newGame() {
        eco = Ecosystem(seed: UInt64.random(in: 1...UInt64.max))
        eco.seedLife(herbivores: 26, carnivores: 0)
        worldName = eco.name
        energy = eco.energy
        stats = eco.stats
        history = eco.history
        selected = nil
        isPaused = false
        speed = .normal
        tool = .inspect
        accumulator = 0
        pushUI()
        scene?.reloadWorld()
        screen = .playing
        SoundEngine.shared.play(.start)
    }

    func continueGame() {
        guard let save = SaveStore.load() else {
            newGame()
            return
        }
        eco = Ecosystem(snapshot: save.snapshot)
        completedMissions = Set(save.completedMissions)
        tracker.load(from: save.completedMissions)
        worldName = eco.name
        energy = eco.energy
        stats = eco.stats
        history = eco.history
        isPaused = false
        speed = .normal
        accumulator = 0
        pushUI()
        scene?.reloadWorld()
        screen = .playing
    }

    func backToMenu() {
        saveGame()
        screen = .menu
        SoundEngine.shared.play(.click)
    }

    func restartWorld() {
        saveGame()
        newGame()
    }

    func saveGame() {
        guard screen == .playing else { return }
        eco.energy = energy
        let file = SaveFile(
            snapshot: eco.snapshot(),
            completedMissions: Array(completedMissions),
            savedAt: Date()
        )
        SaveStore.save(file)
        hasSave = true
    }

    func deleteSave() {
        SaveStore.delete()
        hasSave = false
        completedMissions = []
        tracker.load(from: [])
    }

    // MARK: - Horloge de simulation

    func advance(dt: TimeInterval) {
        guard screen == .playing, !isPaused else { return }
        accumulator += min(dt, 0.1) * Double(speed.rawValue)
        var steps = 0
        while accumulator >= Ecosystem.dt && steps < 12 {
            eco.step()
            let finished = tracker.update(eco: eco, dt: Float(Ecosystem.dt))
            for mission in finished { complete(mission) }
            accumulator -= Ecosystem.dt
            steps += 1
        }
        if steps >= 12 { accumulator = 0 }
    }

    /// Rafraîchit l'interface à basse fréquence (4 Hz) : pas de churn SwiftUI à 60 fps.
    func pushUI() {
        stats = eco.stats
        energy = eco.energy
        history = eco.history
        dayPhase = eco.dayPhase
        weather = eco.weather
        if let current = selected {
            if let fresh = eco.animalSnapshot(id: current.id) {
                selected = fresh
            } else {
                selected = nil
            }
        }
        var progress: [Int: Float] = [:]
        for mission in Missions.all where !completedMissions.contains(mission.id) {
            let value = tracker.progress(for: mission, eco: eco)
            if mission.hold > 0 {
                progress[mission.id] = min(value, tracker.holdProgress(for: mission))
            } else {
                progress[mission.id] = value
            }
        }
        missionProgress = progress
    }

    private func complete(_ mission: Mission) {
        guard !completedMissions.contains(mission.id) else { return }
        completedMissions.insert(mission.id)
        eco.energy = min(Tuning.maxEnergy, eco.energy + mission.reward)
        energy = eco.energy
        defaults.set(Array(completedMissions), forKey: "biome.completedMissions")
        showToast("Mission accomplie : \(mission.title)  +\(Int(mission.reward)) énergie", icon: "checkmark.seal.fill")
        SoundEngine.shared.play(.success)
        if hapticsEnabled { heavyFeedback.impactOccurred() }
        saveGame()
    }

    var currentMission: Mission? {
        Missions.all.first { !completedMissions.contains($0.id) }
    }

    // MARK: - Outils

    func applyTool(at point: CGPoint) {
        guard screen == .playing, !isPaused else { return }
        let worldX = Float(point.x)
        let worldY = Float(point.y)
        let cellX = Int(worldX / Tuning.cellSize)
        let cellY = Int(worldY / Tuning.cellSize)
        guard cellX >= 0, cellY >= 0, cellX < eco.world.width, cellY < eco.world.height else { return }

        switch tool {
        case .inspect:
            select(at: point)
        case .water:
            guard spend(tool.cost) else { return }
            eco.world.paint(.water, centerX: cellX, centerY: cellY, radius: 3)
            SoundEngine.shared.play(.water)
        case .rock:
            guard spend(tool.cost) else { return }
            eco.world.paint(.rock, centerX: cellX, centerY: cellY, radius: 3)
            SoundEngine.shared.play(.rock)
        case .plant:
            guard spend(tool.cost) else { return }
            eco.world.sow(centerX: cellX, centerY: cellY, radius: 4)
            SoundEngine.shared.play(.plant)
        case .herbivore:
            spawn(.herbivore, at: point)
        case .carnivore:
            spawn(.carnivore, at: point)
        case .meteor:
            guard spend(tool.cost) else { return }
            eco.meteor(atX: cellX, atY: cellY, radius: 9)
            if hapticsEnabled { heavyFeedback.impactOccurred() }
            SoundEngine.shared.play(.meteor)
            showToast("Impact dans le secteur \(cellX)-\(cellY)", icon: "sparkles")
        }
    }

    private func spawn(_ species: Species, at point: CGPoint) {
        guard spend(tool.cost) else { return }
        let x = Float(point.x)
        let y = Float(point.y)
        if eco.spawn(species, x: x, y: y) {
            selected = eco.closestAnimal(toX: x, toY: y, maxDistance: 10)
            if hapticsEnabled { impactFeedback.impactOccurred() }
            SoundEngine.shared.play(.spawn)
        } else {
            eco.energy += tool.cost
            energy = eco.energy
            showToast("Impossible d'introduire l'espèce ici", icon: "exclamationmark.triangle.fill")
        }
    }

    func select(at point: CGPoint) {
        if let found = eco.closestAnimal(toX: Float(point.x), toY: Float(point.y), maxDistance: 14) {
            selected = found
            if hapticsEnabled { selectionFeedback.selectionChanged() }
            SoundEngine.shared.play(.click)
        } else {
            selected = nil
        }
    }

    func clearSelection() {
        selected = nil
    }

    private func spend(_ amount: Float) -> Bool {
        if eco.energy >= amount {
            eco.energy -= amount
            energy = eco.energy
            return true
        }
        if Date().timeIntervalSince(lastBrushRefusal) > 1.2 {
            lastBrushRefusal = Date()
            showToast("Énergie de biosphère insuffisante", icon: "bolt.slash.fill")
        }
        return false
    }

    func makeRain() {
        guard spend(30) else { return }
        eco.makeRain()
        showToast("Pluie déclenchée", icon: "cloud.rain.fill")
        SoundEngine.shared.play(.rain)
    }

    func makeDrought() {
        guard spend(10) else { return }
        eco.makeDrought()
        showToast("Sécheresse déclenchée", icon: "sun.haze.fill")
        SoundEngine.shared.play(.drought)
    }

    // MARK: - Divers

    func setTool(_ newTool: Tool) {
        tool = newTool
        if hapticsEnabled { selectionFeedback.selectionChanged() }
        SoundEngine.shared.play(.click)
    }

    func togglePause() {
        isPaused.toggle()
        SoundEngine.shared.play(.click)
    }

    func cycleSpeed() {
        let all = GameSpeed.allCases
        if let index = all.firstIndex(of: speed) {
            speed = all[(index + 1) % all.count]
        } else {
            speed = .normal
        }
        SoundEngine.shared.play(.click)
    }

    func showToast(_ text: String, icon: String = "sparkles") {
        let message = ToastMessage(text: text, icon: icon)
        toast = message
        toastGeneration += 1
        let generation = toastGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.toastGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toast = nil
            }
        }
    }

    // MARK: - Formatage

    var formattedTime: String {
        let seconds = Int(stats.time)
        let minutes = seconds / 60
        let rest = seconds % 60
        return String(format: "%02d:%02d", minutes, rest)
    }

    var biomeLabel: String {
        if stats.biodiversity > 0.8 { return "Florissant" }
        if stats.biodiversity > 0.55 { return "Stable" }
        if stats.biodiversity > 0.3 { return "Fragile" }
        return "Critique"
    }
}
