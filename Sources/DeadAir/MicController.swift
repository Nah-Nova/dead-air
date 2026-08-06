import CoreAudio
import Foundation

/// Mutes the default input device system-wide.
///
/// Preference order is the device's own mute property, which is what a hardware
/// mute would use. Plenty of devices do not implement it, so we fall back to
/// forcing input volume to zero and restoring the old value on unmute.
final class MicController {
    static let shared = MicController()
    static let didChange = Notification.Name("DeadAir.micDidChange")

    private(set) var isMuted = false
    private var savedVolumes: [AudioObjectPropertyElement: Float32] = [:]
    private let queue = DispatchQueue(label: "nu.soep.deadair.mic")
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var listenedDevice: AudioDeviceID?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        observeDefaultDeviceChanges()
        observeCurrentDevice()
        // The user's last choice outlives a restart, matching what they expect
        // from a mute switch.
        if UserDefaults.standard.bool(forKey: Pref.micMuteDesired) {
            setMuted(true)
        } else {
            isMuted = readMuteState()
            notify()
        }
    }

    var deviceName: String {
        guard let device = Self.defaultInputDevice() else { return "No input device" }
        return Self.name(of: device) ?? "Unknown device"
    }

    var hasInputDevice: Bool { Self.defaultInputDevice() != nil }

    // MARK: - Commands

    func toggle() { setMuted(!isMuted) }

    /// - Parameter remember: false for push-to-talk, where the temporary unmute
    ///   must not overwrite the state we return to on release.
    func setMuted(_ muted: Bool, remember: Bool = true) {
        if remember {
            UserDefaults.standard.set(muted, forKey: Pref.micMuteDesired)
        }
        guard let device = Self.defaultInputDevice() else {
            isMuted = false
            notify()
            return
        }
        if !Self.setMuteProperty(device, muted) {
            applyVolumeFallback(device, muted: muted)
        }
        isMuted = readMuteState()
        notify()
    }

    private func applyVolumeFallback(_ device: AudioDeviceID, muted: Bool) {
        let elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]
        if muted {
            savedVolumes.removeAll()
            for element in elements {
                if let volume = Self.volume(of: device, element: element), volume > 0 {
                    savedVolumes[element] = volume
                }
                _ = Self.setVolume(device, element: element, value: 0)
            }
        } else {
            for element in elements {
                _ = Self.setVolume(device, element: element, value: savedVolumes[element] ?? 0.75)
            }
            savedVolumes.removeAll()
        }
    }

    private func readMuteState() -> Bool {
        guard let device = Self.defaultInputDevice() else { return false }
        if let muted = Self.muteProperty(of: device) { return muted }
        if let volume = Self.volume(of: device, element: kAudioObjectPropertyElementMain) {
            return volume <= 0.0001
        }
        if let volume = Self.volume(of: device, element: 1) { return volume <= 0.0001 }
        return false
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // MARK: - Listeners

    private func observeDefaultDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.defaultDeviceChanged() }
        }
        systemListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    /// A freshly connected device arrives unmuted, so re-assert what the user asked for.
    private func defaultDeviceChanged() {
        observeCurrentDevice()
        if UserDefaults.standard.bool(forKey: Pref.micMuteDesired) {
            setMuted(true)
        } else {
            isMuted = readMuteState()
            notify()
        }
    }

    /// Keeps the menu honest when something else changes the mute state.
    private func observeCurrentDevice() {
        if let old = listenedDevice, let block = deviceListener {
            var address = Self.muteAddress()
            AudioObjectRemovePropertyListenerBlock(old, &address, queue, block)
        }
        listenedDevice = nil
        deviceListener = nil

        guard let device = Self.defaultInputDevice() else { return }
        var address = Self.muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMuted = self.readMuteState()
                self.notify()
            }
        }
        deviceListener = block
        listenedDevice = device
        AudioObjectAddPropertyListenerBlock(device, &address, queue, block)
    }

    // MARK: - CoreAudio plumbing

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func muteProperty(of device: AudioDeviceID) -> Bool? {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    private static func setMuteProperty(_ device: AudioDeviceID, _ muted: Bool) -> Bool {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
            settable.boolValue
        else { return false }
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        return status == noErr
    }

    private static func volumeAddress(_ element: AudioObjectPropertyElement)
        -> AudioObjectPropertyAddress
    {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: element)
    }

    private static func volume(of device: AudioDeviceID, element: AudioObjectPropertyElement)
        -> Float32?
    {
        var address = volumeAddress(element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func setVolume(
        _ device: AudioDeviceID, element: AudioObjectPropertyElement, value: Float32
    ) -> Bool {
        var address = volumeAddress(element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
            settable.boolValue
        else { return false }
        var value = value
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        return status == noErr
    }

    static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // CoreAudio hands back a +1 retained string, so go through Unmanaged rather
        // than letting ARC guess at the ownership.
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &unmanaged)
        guard status == noErr, let unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as String
    }
}
