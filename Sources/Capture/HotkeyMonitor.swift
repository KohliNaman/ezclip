@preconcurrency import AppKit
import Carbon

/// Keycodes for left vs right Command keys.
/// Left:  kVK_Command       = 0x37 = 55
/// Right: kVK_RightCommand  = 0x36 = 54
private let kLeftCommandKeyCode: Int64 = 55

final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var lastCmdDown: Date = .distantPast
    private let doublePressThreshold: TimeInterval = 0.4
    private var onTrigger: (() -> Void)?
    private var enabled = false

    /// Whether the event tap was successfully created (i.e. Accessibility is granted).
    private(set) var isActive = false

    private init() {}

    /// Returns `true` if the event tap was created, `false` if Accessibility is needed.
    func register(onTrigger: @escaping () -> Void) -> Bool {
        self.onTrigger = onTrigger
        self.enabled = true

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
            print("⚠️ HotkeyManager: failed to create event tap — Accessibility permission not granted.")
            isActive = false
            return false
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true

        print("✅ ezclip hotkey ready — double-tap LEFT ⌘ to capture")
        return true
    }

    func unregister() {
        enabled = false
        isActive = false
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard enabled, type == .flagsChanged else { return }

        // Only respond to the LEFT Command key (keycode 55).
        // The right Command key (keycode 54) is ignored.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keycode == kLeftCommandKeyCode else { return }

        let flags = event.flags
        let isCmdDown = flags.contains(.maskCommand)

        if isCmdDown {
            // Command went DOWN — this is either the first press or the second.
            let now = Date()
            let elapsed = now.timeIntervalSince(lastCmdDown)

            if elapsed < doublePressThreshold && elapsed > 0.05 {
                // Double-press detected!
                print("⚡️ Double-press LEFT ⌘ — capturing")
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
