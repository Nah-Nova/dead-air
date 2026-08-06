import Foundation

enum Pref {
    static let micMuteDesired = "micMuteDesired"
    static let cleaningDuration = "cleaningDuration"
    static let lockTrackpad = "lockTrackpad"
    static let showOverlay = "showOverlay"
    static let cameraAlerts = "cameraAlerts"
    static let allowDisplaySleep = "allowDisplaySleep"
    static let activationLog = "activationLog"

    /// Hotkeys are overridable with `defaults write nu.soep.deadair <key> -int <n>`.
    static let hotkeyPrefix = "hotkey."

    static func register() {
        UserDefaults.standard.register(defaults: [
            micMuteDesired: false,
            cleaningDuration: 60,
            lockTrackpad: false,
            showOverlay: true,
            cameraAlerts: true,
            allowDisplaySleep: false,
        ])
    }
}
