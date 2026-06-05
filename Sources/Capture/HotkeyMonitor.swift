@preconcurrency import AppKit
import Carbon

/// Keycodes
/// Left Command:  kVK_Command       = 0x37 = 55
/// Right Command: kVK_RightCommand  = 0x36 = 54
private let kLeftCommandKeyCode: Int64 = 55

final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var globalMonitor: Any?
    private var lastCmdDown: Date = .distantPast
    private let doublePressThreshold: TimeInterval = 0.4
    private var onTrigger: (() -> Void)?
    private var enabled = false

    /// Whether the event tap (or global monitor) is active.
    private(set) var isActive = false

    /// Reason the tap couldn't be created — set only when accessibility IS granted but tapCreate still fails.
    private(set) var failureReason: String?

    private init() {}

    // MARK: - Public

    /// Returns `true` if the event listener was set up.
    /// Returns `false` if Accessibility permission is needed OR something else is blocking the tap.
    func register(onTrigger: @escaping () -> Void) -> Bool {
        self.onTrigger = onTrigger
        self.enabled = true
        failureReason = nil

        // ── Primary: CGEvent tap (snappy, low-latency) ──
        if createEventTap() {
            return true
        }

        // ── Fallback: NSEvent global monitor (also needs Accessibility, but some
        //   macOS 26 betas handle this path differently) ──
        if createGlobalMonitor() {
            return true
        }

        // ── Both failed ──
        isActive = false
        print("❌ HotkeyManager: all listener methods failed")
        if failureReason == nil {
            failureReason = "Accessibility permission not granted"
        }
        return false
    }

    func unregister() {
        enabled = false
        isActive = false
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    /// Returns whether Accessibility is currently trusted (uses the system API, not heuristics).
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission.
    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - CGEvent Tap

    private func createEventTap() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            let trusted = AXIsProcessTrusted()
            if trusted {
                failureReason = "CGEvent.tapCreate returned nil despite Accessibility being granted (macOS 26 quirk?)"
                print("⚠️ \(failureReason!)")
            } else {
                print("⚠️ HotkeyManager: Accessibility not trusted — event tap unavailable")
                failureReason = "Accessibility permission not granted"
            }
            return false
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true

        print("✅ CGEvent tap ready — double-tap LEFT ⌘")
        return true
    }

    // MARK: - NSEvent Global Monitor (fallback)

    private func createGlobalMonitor() -> Bool {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            print("⚠️ Global monitor unavailable — Accessibility not trusted")
            return false
        }

        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEvent(event)
        }
        guard monitor != nil else {
            failureReason = "NSEvent.addGlobalMonitor returned nil (Accessibility granted but API refused)"
            print("⚠️ \(failureReason!)")
            return false
        }

        self.globalMonitor = monitor
        isActive = true
        print("✅ NSEvent global monitor ready (fallback) — double-tap LEFT ⌘")
        return true
    }

    private func handleNSEvent(_ event: NSEvent) {
        guard enabled, event.type == .flagsChanged else { return }

        // NSEvent keyCode is UInt16, CGEvent is Int64. kVK_Command = 55 both ways.
        guard event.keyCode == UInt16(kLeftCommandKeyCode) else { return }

        let isCmdDown = event.modifierFlags.contains(.command)

        if isCmdDown {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastCmdDown)

            if elapsed < doublePressThreshold && elapsed > 0.05 {
                print("⚡️ Double-press LEFT ⌘ (NSEvent) — capturing")
                lastCmdDown = .distantPast
                DispatchQueue.main.async { [weak self] in
                    self?.onTrigger?()
                }
            } else {
                lastCmdDown = now
            }
        }
    }

    // MARK: - CGEvent Handler

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard enabled, type == .flagsChanged else { return }

        // Only respond to the LEFT Command key (keycode 55).
        // The right Command key (keycode 54) is ignored.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keycode == kLeftCommandKeyCode else { return }

        let flags = event.flags
        let isCmdDown = flags.contains(.maskCommand)

        if isCmdDown {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastCmdDown)

            if elapsed < doublePressThreshold && elapsed > 0.05 {
                print("⚡️ Double-press LEFT ⌘ (CGEvent) — capturing")
                lastCmdDown = .distantPast
                DispatchQueue.main.async { [weak self] in
                    self?.onTrigger?()
                }
            } else {
                lastCmdDown = now
            }
        }
    }
}
