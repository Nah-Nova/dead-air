import AppKit
import Foundation

/// Keeping the Mac awake with the lid shut is not a power assertion, it is
/// `pmset -a disablesleep`, and that needs root.
///
/// A persistent privileged helper would need a Developer ID certificate, which this build
/// does not have. One authorised command does not: macOS puts up its own authentication
/// dialog, so the password never passes through this app.
///
/// Unlike everything else in Dead Air this changes a system-wide setting that survives
/// reboots, so every call is gated behind a confirmation that says exactly that.
enum LidSleep {
    static let didChange = Notification.Name("DeadAir.lidSleepDidChange")

    /// True when sleep is disabled system wide, which is what lets the lid close.
    static var isDisabled: Bool {
        guard let output = run("/usr/bin/pmset", ["-g"]).output else { return false }
        for line in output.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.contains("1")
        }
        return false
    }

    static func toggle() {
        let turningOn = !isDisabled
        guard confirm(turningOn: turningOn) else { return }

        let value = turningOn ? "1" : "0"
        let result = run(
            "/usr/bin/osascript",
            [
                "-e",
                "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" "
                    + "with administrator privileges",
            ])

        // -128 is the user dismissing the password dialog. That is a decision, not a fault,
        // so it gets no error alert.
        if result.status != 0, result.status != 128, !(result.output ?? "").contains("-128") {
            reportFailure(result.output ?? "pmset failed with status \(result.status)")
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: - Shell

    private static func run(_ path: String, _ arguments: [String]) -> (
        output: String?, status: Int32
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (error.localizedDescription, -1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(data: data, encoding: .utf8), process.terminationStatus)
    }

    // MARK: - Alerts

    private static func confirm(turningOn: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if turningOn {
            alert.messageText = "Keep the Mac awake with the lid closed?"
            alert.informativeText = """
                This runs pmset as an administrator, so macOS will ask for your password.

                Two things it does that the rest of Dead Air does not. It disables sleep \
                entirely, not just closing the lid, so the Mac stays awake on battery too \
                and can get hot in a bag. And it survives reboots until you turn it off \
                again here.
                """
            alert.addButton(withTitle: "Disable sleep")
        } else {
            alert.messageText = "Allow the Mac to sleep again?"
            alert.informativeText =
                "This restores normal sleep behaviour. macOS will ask for your password."
            alert.addButton(withTitle: "Restore sleep")
        }
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func reportFailure(_ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Could not change the sleep setting"
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
