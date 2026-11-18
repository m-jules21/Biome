import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("biome.sound") private var soundEnabled = true
    @AppStorage("biome.haptics") private var hapticsEnabled = true
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    group {
                        toggleRow(
                            icon: "speaker.wave.2.fill",
                            title: "Sons",
                            detail: "Bruitages et ambiance synthétisés en direct",
                            isOn: Binding(
                                get: { soundEnabled },
                                set: { value in
                                    soundEnabled = value
                                    SoundEngine.shared.setEnabled(value)
                                }
                            )
                        )
                        Divider().overlay(Theme.stroke)
                        toggleRow(
                            icon: "iphone.radiowaves.left.and.right",
                            title: "Retour haptique",
                            detail: "Vibrations sur les actions et les missions",
                            isOn: $hapticsEnabled
                        )
                    }

                    group {
                        HStack {
                            Image(systemName: "internaldrive.fill")
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sauvegarde")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                Text(model.hasSave ? "Une sauvegarde locale existe" : "Aucune sauvegarde")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Button("Effacer") { confirmReset = true }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.danger)
                        }
                    }

                    group {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BIOME")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .tracking(4)
                                .foregroundStyle(Theme.text)
                            Text("Simulation d'écosystème évolutif. Chaque individu possède un génome hérité avec mutation : taille, vitesse, vision, métabolisme, fécondité, agressivité. Les populations, les cycles proies-prédateurs et les spéciations ne sont jamais scriptés — ils émergent.")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Version 1.0 · moteur déterministe 30 Hz · SwiftUI + SpriteKit")
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.dim.opacity(0.7))
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(14)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .confirmationDialog("Effacer la sauvegarde et les missions ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) {
                    model.deleteSave()
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action est définitive.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            content()
        }
        .padding(12)
        .background(Theme.panelBackground(corner: 16))
    }

    private func toggleRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }
}
