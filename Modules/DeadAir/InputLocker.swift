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

    /// `NSEvent.EventType.systemDefined`, which carries the media, volume, brightness and
    /// power keys. The subtype comes from AppKit rather than a literal, because the value
    /// is 1 and a hand written 6 silently matched nothing.
    private static let systemDefinedEventType: UInt32 = 14
    private static let powerKeySubtype: Int16 = NSEvent.EventSubtype.powerOff.rawValue

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tickTimer: Timer?
    private var watchdog: DispatchSourceTimer?
    private let overlay = CleaningOverlay()
    private let assertion = PowerAssertion()

    private(set) var isLocked = false
    private(set) var expiry: Date?
    private var chordStart: Date?
    private static let watchdogQueue = DispatchQueue(label: "nu.soep.deadair.inputlock.watchdog")
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
            // Ask macOS first. It only draws its own sheet while no approval entry exists
            // for this identity, and returns the trust state either way, so a false return
            // means the user saw nothing and needs our explanation. Gating this on a flag
            // instead made the first click of every launch a silent no-op for anyone who
            // had ever dismissed the system prompt.
            if !Self.requestAccessibility() {
                showAccessibilityAlert()
            }
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

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        startWatchdog(deadline: expiry)

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
        stopWatchdog()
        destroyTap()
        assertion.release()
        overlay.hide()
        notify()
    }

    /// The deadline of last resort against run loop *mode* starvation. `tickTimer` only
    /// fires in modes the main run loop is currently running, so a modal panel or an event
    /// tracking loop can park it indefinitely; this fires from its own queue regardless of
    /// mode, and samples the unlock chord too. It still unlocks by hopping to main, so a
    /// genuinely wedged main thread is not covered: there the backstop is macOS disabling
    /// an unresponsive tap, which returns input on its own.
    ///
    /// It deliberately shares no mutable state with the main thread: the deadline is
    /// snapshotted, the chord clock is a local captured by the handler, and `unlock()` is
    /// idempotent, so the worst a cancellation race can do is one extra no-op hop.
    private func startWatchdog(deadline: Date?) {
        stopWatchdog()

        let timer = DispatchSource.makeTimerSource(queue: Self.watchdogQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)

        let left = leftCommandKey
        let right = rightCommandKey
        var chordSince: Date?

        timer.setEventHandler { [weak self] in
            guard let self else { return }

            if let deadline, Date() >= deadline {
                DispatchQueue.main.async { self.unlock() }
                return
            }

            let bothCommandsDown =
                CGEventSource.keyState(.hidSystemState, key: left)
                && CGEventSource.keyState(.hidSystemState, key: right)

            guard bothCommandsDown else {
                chordSince = nil
                return
            }
            let since = chordSince ?? Date()
            chordSince = since
            if Date().timeIntervalSince(since) >= Self.unlockChordHold {
                DispatchQueue.main.async { self.unlock() }
            }
        }

        timer.resume()
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
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
        if let tap {
            CFMachPortInvalidate(tap)
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

        // The power key arrives as a system defined event, in the same class as the media
        // and brightness keys we do swallow. It is never blocked: it is the last way out
        // of a locked machine, so it is passed through explicitly rather than left to
        // whatever macOS happens to do with it.
        if type.rawValue == Self.systemDefinedEventType,
            let systemEvent = NSEvent(cgEvent: event),
            systemEvent.subtype.rawValue == Self.powerKeySubtype {
            return Unmanaged.passUnretained(event)
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

    /// Shown only after the permission was asked for once and still did not take, which
    /// on an ad-hoc signed build almost always means macOS is holding an entry for an
    /// older copy of the app: the switch reads as on while the running binary does not
    /// match what was approved. So the first button repairs that rather than sending the
    /// user back to a switch that already looks correct.
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "macOS is still refusing Accessibility access"
        alert.informativeText = """
            Blocking the keyboard needs Accessibility permission, and macOS says Dead Air \
            does not have it.

            If you already switched it on, macOS is holding a stale approval for an \
            earlier build of the app. This build is signed ad-hoc, so its identity changes \
            every time it is rebuilt, and the old approval no longer matches. Clearing the \
            approval and granting it once more fixes it.
            """
        alert.addButton(withTitle: "Clear and ask again")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Self.resetAccessibilityApproval()
            Self.requestAccessibility()
        case .alertSecondButtonReturn:
            if let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    /// Drops this app's own Accessibility approval. An app is allowed to reset its own
    /// entry, so this needs no password and cannot touch any other app.
    private static func resetAccessibilityApproval() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        try? process.run()
        process.waitUntilExit()
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
