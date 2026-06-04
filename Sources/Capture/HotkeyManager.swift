import AppKit
import Carbon

final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var lastCommandPress: Date = .distantPast
    private let doublePressThreshold: TimeInterval = 0.4
    private var onTrigger: (() -> Void)?
    private var enabled = false

    private init() {}

    func register(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        self.enabled = true

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ HotkeyManager: failed to create event tap — needs Accessibility permission.")
            print("   Open System Settings → Privacy & Security → Accessibility, add ezclip.")
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("✅ ezclip hotkey ready — double-tap ⌘ to capture")
    }

    func unregister() {
        enabled = false
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard enabled, type == .flagsChanged else { return }

        let flags = event.flags
        let isCmdPressed = flags.contains(.maskCommand)
        let isCmdReleased = !isCmdPressed

        if isCmdPressed {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastCommandPress)

            if elapsed < doublePressThreshold && elapsed > 0.05 {
                // Double press!
                lastCommandPress = .distantPast
                DispatchQueue.main.async { [weak self] in
                    self?.onTrigger?()
                }
            } else {
                lastCommandPress = now
            }
        }

        // Reset if command not pressed for a while (avoids stale state)
        if isCmdReleased {
            let now = Date()
            if now.timeIntervalSince(lastCommandPress) > doublePressThreshold * 2 {
                lastCommandPress = .distantPast
            }
        }
    }
}
