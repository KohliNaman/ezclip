import SwiftUI

@main
struct EzclipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var libraryViewModel: LibraryViewModel = .init()

    var body: some Scene {
        Window("ezclip", id: "main") {
            LibraryView()
                .environment(libraryViewModel)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Capture Now") {
                    Task { await CaptureOrchestrator.shared.capture() }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(libraryViewModel)
        }
    }
}
