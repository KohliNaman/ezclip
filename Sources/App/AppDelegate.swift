@preconcurrency import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarViewModel = LibraryViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── Database ──
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

        BrowserExtensionInstaller.installNativeMessagingManifests()
        setupMenuBar()

        // ── Register hotkey ──
        // AXIsProcessTrustedWithOptions() is called inside HotkeyManager.
        // macOS shows its OWN native permission prompt automatically —
        // we don't show custom alerts that would interfere with it.
        let tapOk = HotkeyManager.shared.register {
            Task { await CaptureOrchestrator.shared.capture() }
        }

        // Log status only — no custom alert to interfere with native macOS dialogs.
        // Every reinstall generates a new ad-hoc code signature hash, so macOS
        // correctly requires re-granting permissions. That's expected behavior
        // for unsigned apps and cannot be avoided without a paid Developer account.
        if !tapOk {
            let reason = HotkeyManager.shared.failureReason ?? "unknown"
            print("⚠️ Hotkey inactive: \(reason)")
            print("   → macOS will show its own Accessibility prompt. Grant it in System Settings.")
        } else {
            print("✅ Hotkey active")
        }

        NSApp.setActivationPolicy(.regular)

        print("🚀 ezclip ready")
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
