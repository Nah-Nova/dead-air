import AppKit
import ApplicationServices
import CoreGraphics

private let inputTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let locker = Unmanaged<InputLocker>.fromOpaque(refcon).takeUnretainedValue()
    return locker.handle(proxy: proxy, type: type, event: event)
}

/// Swallows input system-wide so the keyboard can be cleaned.
///
/// Escape hatches, in order of reliability:
///   1. Auto-unlock timer, always running when the trackpad is locked.
///   2. Holding both command keys for 3 seconds.
///   3. The Unlock button, when the trackpad is still live.
///   4. Killing the process. The tap dies with it, so a crash can never lock you out.
final class InputLocker {
    static let shared = InputLocker()
    static let didChange = Notification.Name("DeadAir.lockDidChange")

    static let unlockChordHold: TimeInterval = 3
    /// Ceiling applied when the trackpad is locked too, so "no timeout" can never
    /// leave the machine with no working input device.
    static let trackpadLockedSafetyCap: TimeInterval = 5 * 60

    struct DurationOption {
        let title: String
        let seconds: TimeInterval
    }

    static let durationOptions: [DurationOption] = [
        DurationOption(title: "30 seconds", seconds: 30),
        DurationOption(title: "1 minute", seconds: 60),
        DurationOption(title: "5 minutes", seconds: 300),
        DurationOption(title: "No timeout", seconds: 0),
    ]

    private let leftCommandKey: CGKeyCode = 55
    private let rightCommandKey: CGKeyCode = 54

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tickTimer: Timer?
    private let overlay = CleaningOverlay()
    private let assertion = PowerAssertion()

    private(set) var isLocked = false
    private(set) var expiry: Date?
    private var chordStart: Date?
    private var trackpadLocked = false

    private init() {}

    // MARK: - Permission

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Lock

    func toggle() {
        if isLocked {
            unlock()
        } else {
            lock()
        }
    }

    func lock() {
        guard !isLocked else { return }

        guard Self.hasAccessibility else {
            Self.requestAccessibility()
            showAccessibilityAlert()
            return
        }

        trackpadLocked = UserDefaults.standard.bool(forKey: Pref.lockTrackpad)

        guard createTap() else {
            showTapFailureAlert()
            return
        }

        isLocked = true
        chordStart = nil

        // The display must not sleep and lock mid-wipe.
        assertion.hold(preventDisplaySleep: true, reason: "Dead Air cleaning mode")

        var duration = UserDefaults.standard.double(forKey: Pref.cleaningDuration)
        if trackpadLocked, duration <= 0 || duration > Self.trackpadLockedSafetyCap {
            duration = Self.trackpadLockedSafetyCap
        }
        expiry = duration > 0 ? Date().addingTimeInterval(duration) : nil

        if UserDefaults.standard.bool(forKey: Pref.showOverlay) {
            overlay.show(trackpadLocked: trackpadLocked) { [weak self] in
                self?.unlock()
            }
        }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
        notify()
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        expiry = nil
        chordStart = nil

        tickTimer?.invalidate()
        tickTimer = nil
        destroyTap()
        assertion.release()
        overlay.hide()
        notify()
    }

    var remainingDescription: String {
        guard isLocked else { return "Off" }
        guard let expiry else { return "Locked, no timeout" }
        let remaining = max(0, Int(expiry.timeIntervalSinceNow.rounded()))
        return "Locked, \(remaining)s left"
    }

    // MARK: - Tap plumbing

    private func createTap() -> Bool {
        var mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            // NSEvent.EventType.systemDefined, which carries the media, volume and
            // brightness keys. Without it those keep working while "locked".
            | (1 << 14)

        if trackpadLocked {
            let pointerEvents: [CGEventType] = [
                .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
            ]
            for event in pointerEvents { mask |= (1 << event.rawValue) }
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: inputTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func destroyTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        // macOS disables a tap that is too slow. Re-arm instead of silently unlocking.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }
        return nil
    }

    /// Chord state is read from HID, not from the events we swallow, so consuming
    /// the keystroke does not hide it from us.
    private func tick() {
        guard isLocked else { return }

        let bothCommandsDown =
            CGEventSource.keyState(.hidSystemState, key: leftCommandKey)
            && CGEventSource.keyState(.hidSystemState, key: rightCommandKey)

        if bothCommandsDown {
            if chordStart == nil { chordStart = Date() }
            if let chordStart, Date().timeIntervalSince(chordStart) >= Self.unlockChordHold {
                unlock()
                return
            }
        } else {
            chordStart = nil
        }

        if let expiry, Date() >= expiry {
            unlock()
            return
        }

        overlay.update(status: overlayStatus(bothCommandsDown: bothCommandsDown))
    }

    private func overlayStatus(bothCommandsDown: Bool) -> String {
        if let chordStart, bothCommandsDown {
            let held = Date().timeIntervalSince(chordStart)
            let left = max(0, Self.unlockChordHold - held)
            return String(format: "Unlocking in %.1fs, keep holding", left)
        }
        guard let expiry else { return "No timeout set" }
        let remaining = max(0, Int(expiry.timeIntervalSinceNow.rounded()))
        return "Unlocks automatically in \(remaining)s"
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // MARK: - Alerts

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Dead Air needs Accessibility access"
        alert.informativeText = """
            Blocking the keyboard requires Accessibility permission.

            Open System Settings > Privacy & Security > Accessibility, switch Dead Air \
            on, then try again.

            Because the app is signed ad-hoc, macOS may ask again after every rebuild.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func showTapFailureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Could not lock input"
        alert.informativeText = """
            macOS refused the event tap even though Accessibility looks granted. \
            Removing Dead Air from the Accessibility list and adding it again usually \
            fixes this, since the permission is tied to the exact build.
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
