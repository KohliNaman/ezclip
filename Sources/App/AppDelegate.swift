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

        setupMenuBar()

        // ── Accessibility (required for double-press LEFT ⌘) ──
        let tapOk = HotkeyManager.shared.register {
            Task { await CaptureOrchestrator.shared.capture() }
        }

        if !tapOk {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showAccessibilityAlert()
            }
        }

        NSApp.setActivationPolicy(.regular)

        print("🚀 ezclip ready — double-tap LEFT ⌘ to capture")
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

    // MARK: - Permission Prompts

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = """
        ezclip needs Accessibility access to detect the double-press LEFT ⌘ shortcut.

        Open System Settings → Privacy & Security → Accessibility
        Toggle ezclip ON, then restart the app.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
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
