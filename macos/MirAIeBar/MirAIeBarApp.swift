import MirAIeKit
import SwiftUI

@main
struct MirAIeBarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("Sign in to MirAIe", id: "onboarding") {
            SignInView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("MirAIe Bar Settings", id: "settings") {
            SettingsView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.menuBarIcon)
            .task {
                await model.start()
                if model.phase == .signedOut {
                    openWindow(id: "onboarding")
                }
            }
            .onChange(of: model.phase) { _, phase in
                if phase == .signedOut {
                    openWindow(id: "onboarding")
                }
            }
    }
}
