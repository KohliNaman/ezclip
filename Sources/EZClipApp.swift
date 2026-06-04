import SwiftUI
import AppKit
import Combine

@main
struct EZClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var libraryViewModel = LibraryViewModel()

    var body: some Scene {
        // Main library window
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

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(libraryViewModel)
        }
    }
}

// MARK: - App Delegate (Menu Bar + Hotkey + Lifecycle)

final class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarViewModel = LibraryViewModel()
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Set up database
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

        // 2. Set up menu bar
        setupMenuBar()

        // 3. Register global hotkey
        HotkeyManager.shared.register {
            Task { @MainActor in
                await CaptureOrchestrator.shared.capture()
            }
        }

        // 4. Set up notifications
        NSUserNotificationCenter.default.delegate = self

        // 5. Hide Dock icon? No — we want both menu bar + dock
        NSApp.setActivationPolicy(.regular)

        print("🚀 ezclip ready — double-tap ⌘ to capture")
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No windows open — show the main window
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

            // Refresh menu bar data
            Task { await menuBarViewModel.loadAll() }

            // Ensure popover stays on top
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Notifications

    func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        didActivate notification: NSUserNotification
    ) {
        // Open main window when user clicks notification
        if notification.activationType == .actionButtonClicked {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
