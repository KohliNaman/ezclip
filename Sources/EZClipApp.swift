import SwiftUI
@preconcurrency import AppKit
import Combine

@main
struct EZClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var libraryViewModel: LibraryViewModel = .init()

    var body: some Scene {
        Window("ezclip", id: "main") {
            LibraryView()
                .environmentObject(libraryViewModel)
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
                .environmentObject(libraryViewModel)
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarViewModel = LibraryViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up database
        do {
            try DatabaseManager.shared.setup()
            print("✅ Database ready")
        } catch {
            print("❌ Database setup failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Database Error"
            alert.informativeText = "Failed to initialize storage: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
        }

        // Menu bar
        setupMenuBar()

        // Hotkey
        HotkeyManager.shared.register {
            Task { await CaptureOrchestrator.shared.capture() }
        }

        // Dock icon
        NSApp.setActivationPolicy(.regular)

        print("🚀 ezclip ready — double-tap ⌘ to capture")
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle.badge.checkmark",
                accessibilityDescription: "ezclip"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(menuBarViewModel)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { await menuBarViewModel.loadAll() }
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
