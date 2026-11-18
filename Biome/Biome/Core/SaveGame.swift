import Foundation

// MARK: - Snapshots sérialisables

struct WorldSnapshot: Codable {
    var width: Int
    var height: Int
    var terrain: [UInt8]
    var elevation: [Float]
    var moisture: [Float]
    var fertility: [Float]
    var plant: [Float]
}

struct EcoSnapshot: Codable {
    var seed: UInt64
    var rngState: UInt64
    var name: String
    var time: Double
    var dayPhase: Float
    var weather: UInt8
    var weatherTimer: Float
    var energy: Float
    var world: WorldSnapshot
    var animals: [Animal]
    var births: Int
    var deaths: Int
    var maxGeneration: Int
    var nextID: Int
    var history: [HistorySample]
}

struct SaveFile: Codable {
    var snapshot: EcoSnapshot
    var completedMissions: [Int]
    var savedAt: Date
}

enum SaveStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("biome.save")
    }

    static func save(_ file: SaveFile) {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(file)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Biome] save failed:", error)
        }
    }

    static func load() -> SaveFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(SaveFile.self, from: data)
    }

    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
