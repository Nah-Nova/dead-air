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

    private let assertion = PowerAssertion()
    private var expiryTimer: Timer?
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
        assertion.release()
        expiryTimer?.invalidate()
        expiryTimer = nil

        guard assertion.hold(preventDisplaySleep: !allowDisplaySleep, reason: "Dead Air keep awake")
        else {
            expiry = nil
            notify()
            return
        }

        if let duration {
            expiry = Date().addingTimeInterval(duration)
            expiryTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
                [weak self] _ in
                self?.deactivate()
            }
        } else {
            expiry = nil
        }
        notify()
    }

    func deactivate() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        expiry = nil
        activePresetIndex = nil
        assertion.release()
        notify()
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
