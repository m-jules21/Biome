import SwiftUI
import SpriteKit

struct GameView: View {
    @ObservedObject var model: GameModel
    @State private var scene = WorldScene()
    @AppStorage("biome.onboarded") private var onboarded = false

    var body: some View {
        ZStack {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            nightTint
                .ignoresSafeArea()
                .allowsHitTesting(false)

            RadialGradient(
                colors: [.clear, .black.opacity(0.42)],
                center: .center,
                startRadius: 160,
                endRadius: 560
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 7) {
                topBar
                missionBar
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, 11)
            .padding(.top, 6)
            .padding(.bottom, 4)

            if let toast = model.toast {
                toastView(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.isPaused {
                pauseOverlay
            }

            if !onboarded {
                onboarding
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toast)
        .animation(.easeInOut(duration: 0.2), value: model.isPaused)
        .onAppear {
            scene.model = model
            model.scene = scene
            SoundEngine.shared.start()
        }
        .sheet(isPresented: $model.showMissions) { MissionsView(model: model) }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .sheet(isPresented: $model.showStats) { StatsView(model: model) }
    }

    // MARK: - Ambiance

    private var nightTint: some View {
        let light = 0.26 + 0.74 * (0.5 + 0.5 * sin(model.dayPhase * 2 * Float.pi))
        let darkness = max(0, 0.62 - light) * 0.7
        return Color(red: 0.02, green: 0.05, blue: 0.15).opacity(Double(darkness))
    }

    // MARK: - Barre haute

    private var topBar: some View {
        HStack(spacing: 5) {
            StatChip(icon: "hare.fill", value: "\(model.stats.herbivores)", tint: Color(red: 0.55, green: 0.90, blue: 0.68))
            StatChip(icon: "pawprint.fill", value: "\(model.stats.carnivores)", tint: Theme.danger)
            StatChip(icon: "leaf.fill", value: "\(Int(model.stats.plantCoverage * 100))%", tint: Theme.accent)

            Spacer(minLength: 2)

            EnergyGauge(energy: model.energy, maxEnergy: Tuning.maxEnergy)

            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.36)))
            }
        }
    }

    private var missionBar: some View {
        HStack(spacing: 8) {
            if let mission = model.currentMission {
                let progress = model.missionProgress[mission.id] ?? 0
                HStack(spacing: 8) {
                    Image(systemName: mission.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mission.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(mission.goal)
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 4)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(progress >= 0.999 ? Theme.accent : Theme.dim)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.34))
                        .overlay(alignment: .bottomLeading) {
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(Theme.accent.opacity(0.75))
                                    .frame(width: geometry.size.width * CGFloat(progress), height: 2)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                )
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.accent)
                    Text("Toutes les missions sont accomplies")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.34)))
            }

            VStack(spacing: 3) {
                Text(model.formattedTime)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                Button {
                    model.cycleSpeed()
                } label: {
                    Text(model.speed.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.warm)
                        .frame(width: 36, height: 20)
                        .background(Capsule().fill(Color.black.opacity(0.36)))
                }
            }
        }
    }

    // MARK: - Barre basse

    private var bottomBar: some View {
        VStack(spacing: 7) {
            if let selected = model.selected {
                inspector(selected)
            }

            HStack(spacing: 5) {
                ForEach(Tool.allCases) { item in
                    toolButton(item)
                }
            }

            HStack(spacing: 6) {
                actionButton(title: "Pluie", icon: "cloud.rain.fill", cost: 30, tint: Color(red: 0.42, green: 0.72, blue: 0.95)) {
                    model.makeRain()
                }
                actionButton(title: "Sécheresse", icon: "sun.haze.fill", cost: 10, tint: Theme.warm) {
                    model.makeDrought()
                }
                Spacer(minLength: 2)
                Button {
                    model.showStats = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 11, weight: .bold))
                        Text("Stats")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.36)))
                }
            }
        }
    }

    private func toolButton(_ item: Tool) -> some View {
        let selected = model.tool == item
        return Button {
            model.setTool(item)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(item.short)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Color(red: 0.03, green: 0.07, blue: 0.06) : Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? item.tint : Color.black.opacity(0.36))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(selected ? Color.clear : Theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func actionButton(title: String, icon: String, cost: Float, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("\(Int(cost))")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.36)))
        }
        .buttonStyle(.plain)
    }

    private func inspector(_ selected: AnimalSnapshot) -> some View {
        let tint = selected.species == .carnivore ? Theme.danger : Theme.accent
        return HStack(spacing: 10) {
            GenomeRadar(values: selected.genome.normalized, tint: tint)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: selected.species.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                    Text(selected.species.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("G\(selected.generation)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    Button {
                        model.clearSelection()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .padding(4)
                    }
                }

                HStack(spacing: 5) {
                    Text("Énergie")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.dim)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(tint)
                                .frame(width: max(2, geometry.size.width * CGFloat(selected.energyRatio)))
                        }
                    }
                    .frame(height: 4)
                }

                Text("âge \(Int(selected.age)) s · \(selected.children) enfants · taille \(String(format: "%.2f", selected.genome.size)) · vitesse \(String(format: "%.2f", selected.genome.speed))")
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Superpositions

    private func toastView(_ toast: ToastMessage) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: toast.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(toast.text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            )
            .padding(.top, 112)
            Spacer()
        }
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { model.togglePause() }

            VStack(spacing: 12) {
                Text("PAUSE")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 2)

                Text(model.worldName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)

                HStack(spacing: 18) {
                    miniStat("\(model.stats.herbivores)", "herb.")
                    miniStat("\(model.stats.carnivores)", "carn.")
                    miniStat("\(Int(model.stats.plantCoverage * 100))%", "plantes")
                    miniStat(model.biomeLabel, "biome")
                }
                .padding(.vertical, 6)

                Button {
                    model.togglePause()
                } label: {
                    Label("Reprendre", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                HStack(spacing: 8) {
                    Button("Missions") { model.showMissions = true }
                        .buttonStyle(GhostButtonStyle())
                    Button("Statistiques") { model.showStats = true }
                        .buttonStyle(GhostButtonStyle())
                }
                HStack(spacing: 8) {
                    Button("Réglages") { model.showSettings = true }
                        .buttonStyle(GhostButtonStyle())
                    Button("Menu") { model.backToMenu() }
                        .buttonStyle(GhostButtonStyle())
                }

                Button("Nouveau monde") { model.restartWorld() }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 2)
            }
            .padding(18)
            .background(Theme.panelBackground(corner: 22))
            .padding(.horizontal, 30)
        }
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.dim)
        }
    }

    private var onboarding: some View {
        ZStack {
            Color.black.opacity(0.35)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Bienvenue dans ton biome")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)

                hintRow(icon: "hand.point.up.left.fill", title: "Observe", text: "Touche une créature pour lire son génome et son énergie.")
                hintRow(icon: "leaf.fill", title: "Sculpte", text: "Eau, roche, semis : la carte du vivant se dessine sous ton doigt.")
                hintRow(icon: "hare.fill", title: "Équilibre", text: "Plantes → herbivores → carnivores. La sélection naturelle fait le reste.")

                Text("Deux doigts : déplacer et zoomer la caméra.")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.dim)

                Button {
                    withAnimation { onboarded = true }
                } label: {
                    Label("Commencer", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(18)
            .background(Theme.panelBackground(corner: 22))
            .padding(.horizontal, 26)
        }
    }

    private func hintRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(text)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
