import SwiftUI

struct MissionsView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(Missions.all) { mission in
                        row(mission)
                    }

                    Text("Les missions s'évaluent en continu sur l'état réel de la simulation. Une mission maintenue quelques secondes exige que la condition tienne sans interruption.")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 6)
                }
                .padding(14)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Missions")
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

    private func row(_ mission: Mission) -> some View {
        let completed = model.completedMissions.contains(mission.id)
        let progress = completed ? 1 : (model.missionProgress[mission.id] ?? 0)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: completed ? "checkmark.seal.fill" : mission.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(completed ? Theme.accent : Theme.dim)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mission.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(completed ? Theme.dim : Theme.text)
                    Text(mission.goal)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(Int(mission.reward))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.warm)
            }

            Text(mission.detail)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.dim.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(completed ? Theme.accent : Theme.accent.opacity(0.65))
                            .frame(width: max(2, geometry.size.width * CGFloat(progress)))
                    }
                }
                .frame(height: 5)

                Text(completed ? "OK" : "\(Int(progress * 100))%")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(completed ? Theme.accent : Theme.dim)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(11)
        .background(Theme.panelBackground(corner: 14))
    }
}
