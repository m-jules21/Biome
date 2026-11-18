import SwiftUI

struct SporeField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                let width = max(1, size.width)
                let height = max(1, size.height)
                for index in 0..<48 {
                    let seed = Double(index) * 12.9898
                    let base = CGFloat((sin(seed) * 0.5 + 0.5))
                    let speed = CGFloat(4 + Double(index % 7) * 3)
                    let drift = sin(time * 0.22 + CGFloat(seed)) * 30
                    let x = (base * width + drift).truncatingRemainder(dividingBy: width)
                    let progress = (time * speed + CGFloat(seed) * 50).truncatingRemainder(dividingBy: height + 120)
                    let y = height - progress
                    let radius = CGFloat(1 + index % 3)
                    let pulse = 0.5 + 0.5 * sin(time * 0.7 + CGFloat(seed))
                    let alpha = 0.06 + 0.16 * pulse
                    let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(alpha)))
                }
            }
        }
    }
}

struct MainMenuView: View {
    @ObservedObject var model: GameModel
    @State private var reveal = false

    private var completedCount: Int { model.completedMissions.count }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            SporeField().ignoresSafeArea()
            RadialGradient(
                colors: [Theme.accentDeep.opacity(0.30), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                VStack(spacing: 10) {
                    Text("BIOME")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .tracking(12)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.text, Theme.accent, Theme.accentDeep],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Theme.accent.opacity(0.35), radius: 24, y: 0)

                    Text("écosystème évolutif")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .tracking(5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.dim)
                }
                .opacity(reveal ? 1 : 0)
                .offset(y: reveal ? 0 : -12)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    if completedCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                            Text("\(completedCount) / \(Missions.all.count) missions")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    }

                    Button {
                        model.newGame()
                    } label: {
                        Label("Nouveau monde", systemImage: "sparkles")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if model.hasSave {
                        Button {
                            model.continueGame()
                        } label: {
                            Label("Continuer", systemImage: "play.fill")
                        }
                        .buttonStyle(GhostButtonStyle())
                    }

                    HStack(spacing: 10) {
                        Button {
                            model.showMissions = true
                        } label: {
                            Label("Missions", systemImage: "list.bullet.rectangle")
                        }
                        .buttonStyle(GhostButtonStyle())

                        Button {
                            model.showSettings = true
                        } label: {
                            Label("Réglages", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                .padding(.horizontal, 28)
                .opacity(reveal ? 1 : 0)
                .offset(y: reveal ? 0 : 18)

                Spacer(minLength: 24)

                VStack(spacing: 6) {
                    Text("Simulation déterministe · pas fixe 30 Hz")
                    Text("génétique · chaîne trophique · climat")
                }
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.dim.opacity(0.65))
                .padding(.bottom, 18)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { reveal = true }
        }
        .sheet(isPresented: $model.showMissions) {
            MissionsView(model: model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
    }
}
