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
                .frame(minWidth: 1000, minHeight: 660)
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
