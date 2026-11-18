import SwiftUI
import UIKit

struct StatsView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss

    private var stats: SimStats { model.stats }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    chartCard
                    grid
                    balanceCard
                    worldCard
                }
                .padding(14)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Écosystème")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Populations")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
                legend(color: Theme.accent, label: "herbivores")
                legend(color: Theme.danger, label: "carnivores")
                legend(color: Theme.accentDeep, label: "plantes")
            }

            PopulationChart(history: model.history)
                .frame(height: 130)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.20))
                )

            Text("Les cycles proies-prédateurs apparaissent d'eux-mêmes : personne ne les script.")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.dim)
        }
        .padding(12)
        .background(Theme.panelBackground(corner: 16))
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.dim)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile("Herbivores", "\(stats.herbivores)", "hare.fill", Theme.accent)
            tile("Carnivores", "\(stats.carnivores)", "pawprint.fill", Theme.danger)
            tile("Plantes", "\(Int(stats.plantCoverage * 100)) %", "leaf.fill", Theme.accent)
            tile("Génération", "\(stats.generation)", "dna", Theme.warm)
            tile("Naissances", "\(stats.births)", "plus.circle.fill", Theme.accent)
            tile("Morts", "\(stats.deaths)", "minus.circle.fill", Theme.dim)
            tile("Taille moy. herb.", String(format: "%.2f", stats.avgSizeH), "ruler.fill", Theme.accent)
            tile("Taille moy. carn.", String(format: "%.2f", stats.avgSizeC), "ruler.fill", Theme.danger)
        }
    }

    private func tile(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Theme.panelBackground(corner: 12))
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("État du biome")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(model.biomeLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }

            bar(label: "Biodiversité", value: stats.biodiversity, tint: Theme.accent)
            bar(label: "Stabilité", value: stats.stability, tint: Theme.warm)
            bar(label: "Couverture végétale", value: stats.plantCoverage, tint: Theme.accentDeep)

            HStack(spacing: 12) {
                Label(model.weather.label, systemImage: model.weather.icon)
                Label("\(Int(model.dayPhase * 24)) h", systemImage: "moon.stars.fill")
                Label(model.formattedTime, systemImage: "clock.fill")
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.dim)
            .padding(.top, 2)
        }
        .padding(12)
        .background(Theme.panelBackground(corner: 16))
    }

    private func bar(label: String, value: Float, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.dim)
                Spacer()
                Text("\(Int(value * 100)) %")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geometry.size.width * CGFloat(clampf(value, 0, 1))))
                }
            }
            .frame(height: 5)
        }
    }

    private var worldCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monde")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            HStack {
                Text(model.worldName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("graine \(String(model.eco.seed))")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.dim)
            }
            Text("La simulation est déterministe : une même graine et les mêmes interventions reproduisent exactement la même histoire.")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.dim)
        }
        .padding(12)
        .background(Theme.panelBackground(corner: 16))
    }
}
