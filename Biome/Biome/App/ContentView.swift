import SwiftUI

struct ContentView: View {
    @StateObject private var model = GameModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch model.screen {
            case .menu:
                MainMenuView(model: model)
            case .playing:
                GameView(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                model.saveGame()
            }
        }
    }
}
