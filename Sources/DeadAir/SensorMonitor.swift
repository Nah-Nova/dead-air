import AppKit
import CoreAudio
import CoreMediaIO

/// Reports whether the camera or mic is in use, the same signal behind the green
/// and orange dots in the menu bar.
///
/// It cannot say *which* app is responsible. macOS exposes no such API, which
/// Objective Development confirm for Micro Snitch:
/// https://www.obdev.at/support/microsnitch/vajq8
final class SensorMonitor {
    static let shared = SensorMonitor()
    static let didChange = Notification.Name("DeadAir.sensorDidChange")

    private(set) var cameraInUse = false
    private(set) var micInUse = false
    private var timer: Timer?
    private var hasBaseline = false

    private init() {}

    func start() {
        poll()
        hasBaseline = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let camera = Self.anyCameraRunning()
        let mic = Self.anyInputDeviceRunning()
        guard camera != cameraInUse || mic != micInUse else { return }

        let cameraTurnedOn = camera && !cameraInUse
        if camera != cameraInUse {
            cameraInUse = camera
            ActivationLog.shared.append(kind: .camera, active: camera)
        }
        if mic != micInUse {
            micInUse = mic
            ActivationLog.shared.append(kind: .microphone, active: mic)
        }

        // Skip the alert on the very first poll, otherwise launching while a call is
        // already running fires a warning about something the user started themselves.
        if cameraTurnedOn, hasBaseline, UserDefaults.standard.bool(forKey: Pref.cameraAlerts) {
            AlertBanner.shared.show(
                title: "Camera is on",
                subtitle: "macOS does not reveal which app. Check the green dot.")
        }

        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // MARK: - Camera

    private static func anyCameraRunning() -> Bool {
        for device in cmioDevices() where cmioIsRunning(device) { return true }
        return false
    }

    private static func cmioDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard
            CMIOObjectGetPropertyDataSize(
                CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0,
            size > 0
        else { return [] }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices)
        guard status == 0 else { return [] }
        return devices
    }

    private static func cmioIsRunning(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &value)
        guard status == 0 else { return false }
        return value != 0
    }

    // MARK: - Microphone

    private static func anyInputDeviceRunning() -> Bool {
        for device in audioDevices() where hasInputStreams(device) && audioIsRunning(device) {
            return true
        }
        return false
    }

    private static func audioDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
            size > 0
        else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
        guard status == noErr else { return [] }
        return devices
    }

    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }

    private static func audioIsRunning(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }
}
