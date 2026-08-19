import Foundation
import IOKit.pwr_mgt

/// One IOKit power assertion. Released when the holder says so or the process dies,
/// which is why nothing can leave the Mac permanently awake after a crash.
final class PowerAssertion {
    private var id: IOPMAssertionID = IOPMAssertionID(0)
    private(set) var isHeld = false

    /// - Parameter preventDisplaySleep: true keeps the screen on as well, false lets
    ///   the display sleep while the system stays awake.
    @discardableResult
    func hold(preventDisplaySleep: Bool, reason: String) -> Bool {
        guard !isHeld else { return true }
        let type =
            preventDisplaySleep
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newID)
        guard result == kIOReturnSuccess else { return false }
        id = newID
        isHeld = true
        return true
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(id)
        isHeld = false
        id = IOPMAssertionID(0)
    }
}

/// The user-facing keep-awake feature, with presets and a live countdown.
final class KeepAwake {
    static let shared = KeepAwake()
    static let didChange = Notification.Name("DeadAir.keepAwakeDidChange")

    /// nil duration means "until I turn it off".
    struct Preset {
        let title: String
        let duration: TimeInterval?
    }

    static let presets: [Preset] = [
        Preset(title: "15 minutes", duration: 15 * 60),
        Preset(title: "30 minutes", duration: 30 * 60),
        Preset(title: "1 hour", duration: 60 * 60),
        Preset(title: "2 hours", duration: 2 * 60 * 60),
        Preset(title: "4 hours", duration: 4 * 60 * 60),
        Preset(title: "Until I turn it off", duration: nil),
    ]

    /// How often the banner repeats while keep awake runs with no end time. An hourly
    /// nudge with the start time is planning help, not nagging.
    static let reminderInterval: TimeInterval = 60 * 60

    private let assertion = PowerAssertion()
    private var expiryTimer: Timer?
    private var reminderTimer: Timer?
    private(set) var activatedAt: Date?
    private(set) var expiry: Date?
    /// Kept separately from `expiry` so the menu can tick a checkmark next to the
    /// chosen preset, which the shrinking remaining time no longer matches.
    private(set) var activePresetIndex: Int?

    var isActive: Bool { assertion.isHeld }

    private init() {}

    func activate(presetIndex: Int) {
        guard Self.presets.indices.contains(presetIndex) else { return }
        activePresetIndex = presetIndex
        activate(duration: Self.presets[presetIndex].duration)
    }

    func activate(duration: TimeInterval?) {
        let allowDisplaySleep = UserDefaults.standard.bool(forKey: Pref.allowDisplaySleep)
        let wasActive = assertion.isHeld
        assertion.release()
        expiryTimer?.invalidate()
        expiryTimer = nil
        // The reminder clock is deliberately not reset here. Re-applying an already
        // running indefinite session (which is what a display sleep preference change
        // does) used to push the hourly nudge a full hour out, so toggling that checkbox
        // often enough meant the banner never arrived.
        if !wasActive {
            reminderTimer?.invalidate()
            reminderTimer = nil
        }

        guard assertion.hold(preventDisplaySleep: !allowDisplaySleep, reason: "Dead Air keep awake")
        else {
            expiry = nil
            activatedAt = nil
            notify()
            return
        }

        if !wasActive {
            activatedAt = Date()
        }

        if let duration {
            reminderTimer?.invalidate()
            reminderTimer = nil
            expiry = Date().addingTimeInterval(duration)
            expiryTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
                [weak self] _ in
                self?.deactivate()
            }
        } else {
            expiry = nil
            // No end time means nothing will ever turn this off, so the app takes on
            // the reminding: a banner every hour, carrying the start time, until the
            // user decides. Only started if one is not already running.
            if reminderTimer == nil {
                let timer = Timer(timeInterval: Self.reminderInterval, repeats: true) { [weak self] _ in
                    self?.remind()
                }
                RunLoop.main.add(timer, forMode: .common)
                reminderTimer = timer
            }
        }
        notify()
    }

    func deactivate() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        reminderTimer?.invalidate()
        reminderTimer = nil
        expiry = nil
        activatedAt = nil
        activePresetIndex = nil
        assertion.release()
        notify()
    }

    private func remind() {
        guard isActive, expiry == nil else { return }
        let since: String
        if let activatedAt {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            since = "On since \(formatter.string(from: activatedAt)) with no end time."
        } else {
            since = "On with no end time."
        }
        AlertBanner.shared.show(
            title: "Keep awake is still on",
            subtitle: "\(since) Turn it off in the Dead Air menu when you are done.")
    }

    /// Re-applies the assertion so a display-sleep preference change takes effect now.
    func reapplyIfActive() {
        guard isActive else { return }
        let remaining = expiry?.timeIntervalSinceNow
        if let remaining, remaining <= 0 {
            deactivate()
        } else {
            activate(duration: remaining)
        }
    }

    /// How much of a finite session is still to run. Zero for an indefinite session,
    /// which has no fraction, and zero when nothing is running.
    var remainingFraction: Double {
        guard isActive, let expiry, let index = activePresetIndex,
            let total = Self.presets[index].duration, total > 0 else { return 0 }
        return max(0, min(1, expiry.timeIntervalSinceNow / total))
    }

    var statusDescription: String {
        guard isActive else { return "Off" }
        guard let expiry else { return "On, until turned off" }
        let remaining = max(0, Int(expiry.timeIntervalSinceNow))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 { return String(format: "On, %dh %02dm left", hours, minutes) }
        if minutes > 0 { return String(format: "On, %dm %02ds left", minutes, seconds) }
        return "On, \(seconds)s left"
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
