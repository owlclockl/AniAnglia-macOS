import SwiftUI

@main
struct AniAngliaApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.auth)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("О программе AniAnglia") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "AniAnglia",
                        .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1",
                        .credits: NSAttributedString(
                            string: "Неофициальный клиент Anixart для macOS.",
                            attributes: [.foregroundColor: NSColor.labelColor]
                        )
                    ])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 520, height: 420)
        }
    }
}
