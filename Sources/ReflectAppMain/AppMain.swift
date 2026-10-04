import SwiftUI
import ReflectLib

@main
struct ReflectMainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Reflect") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 620, minHeight: 520)
        }
        // Native Settings scene: supplies the application menu's Settings…
        // entry and Command-comma. It shares the same AppStore as the main
        // window and the macOS 13 in-window Settings route, so every entry
        // point shows the same persisted preference and agent state.
        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(minWidth: 620, minHeight: 460)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Source Availability") {
                    store.refreshAvailability()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
