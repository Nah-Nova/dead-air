//
//  main.swift
//  DeadAir
//
//  The Dead Air module: mic mute, cleaning mode, camera and mic monitor,
//  and keep awake, hosted in the Stats module system.
//

import Cocoa
import Kit

internal struct DeadAirState {
    var micMuted: Bool = false
    var micDevice: String = ""
    var hasInputDevice: Bool = false
    var micInUse: Bool = false
    var cameraInUse: Bool = false
    var cleaningLocked: Bool = false
    var cleaningStatus: String = "Off"
    var keepAwakeActive: Bool = false
    var keepAwakeStatus: String = "Off"
    var sleepDisabled: Bool = false
    /// Remaining share of a finite keep awake session, 0 when it is indefinite or off.
    var keepAwakeFraction: Double = 0
}

public class DeadAir: Module {
    private let popupView: Popup
    private let portalView: Portal

    private var pushToTalkActive = false

    /// `LidSleep.isDisabled` spawns pmset, so it is sampled off the main thread and cached
    /// rather than read on every popup refresh.
    private static var lastKnownSleepDisabled = false

    public init() {
        // Registered before the popup exists, not after. A stored property initializer
        // runs ahead of the init body, so the popup used to read every preference before
        // its default was registered: the banner box drew unchecked while banners were on,
        // and the duration menu read "No timeout" while the lock actually used 60s.
        Pref.register()

        self.popupView = Popup(.deadair)
        self.portalView = Portal(.deadair)

        super.init(
            moduleType: .deadair,
            popup: self.popupView,
            portal: self.portalView
        )
        guard self.available else { return }

        MicController.shared.start()
        SensorMonitor.shared.start()
        self.setUpHotkeys()

        [
            MicController.didChange,
            SensorMonitor.didChange,
            InputLocker.didChange,
            KeepAwake.didChange
        ].forEach { name in
            NotificationCenter.default.addObserver(
                self, selector: #selector(self.stateDidChange), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.sleepSettingDidChange),
            name: LidSleep.didChange, object: nil)

        self.popupView.refreshCallback = { [weak self] in
            self?.stateDidChange()
        }

        // Sleep disabled via pmset survives reboots and outlives the app, so it is the
        // one state worth flagging unprompted: once, shortly after launch.
        self.refreshSleepState(announce: true, after: 15)

        self.stateDidChange()
    }

    /// Samples the system sleep setting off the main thread and republishes the state.
    private func refreshSleepState(announce: Bool = false, after delay: TimeInterval = 0) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            let disabled = LidSleep.isDisabled
            DispatchQueue.main.async {
                guard let self else { return }
                Self.lastKnownSleepDisabled = disabled
                if announce, disabled {
                    AlertBanner.shared.show(
                        title: "Sleep is disabled system-wide",
                        subtitle: "The Mac stays awake even with the lid closed, also on battery.")
                }
                self.stateDidChange()
            }
        }
    }

    @objc private func sleepSettingDidChange() {
        self.refreshSleepState()
    }

    @objc private func stateDidChange() {
        var state = DeadAirState()
        state.micMuted = MicController.shared.isMuted
        state.micDevice = MicController.shared.deviceName
        state.hasInputDevice = MicController.shared.hasInputDevice
        state.micInUse = SensorMonitor.shared.micInUse
        state.cameraInUse = SensorMonitor.shared.cameraInUse
        state.cleaningLocked = InputLocker.shared.isLocked
        state.cleaningStatus = InputLocker.shared.remainingDescription
        state.keepAwakeActive = KeepAwake.shared.isActive
        state.keepAwakeStatus = KeepAwake.shared.statusDescription
        state.sleepDisabled = Self.lastKnownSleepDisabled
        state.keepAwakeFraction = KeepAwake.shared.remainingFraction

        DispatchQueue.main.async {
            self.popupView.callback(state)
            self.portalView.callback(state)
        }

        let values: [Stack_t] = [
            Stack_t(key: "MIC", value: state.micMuted ? "MUTED" : "LIVE"),
            Stack_t(key: "CAM", value: state.cameraInUse ? "ON" : "OFF")
        ]
        if state.cleaningLocked {
            self.endPushToTalk()
        }

        // Locked outranks muted: a locked keyboard is the more consequential state to
        // be caught in, so it owns the mark while cleaning mode runs.
        let mark: MarkWidget.State = state.cleaningLocked
            ? .locked
            : (state.micMuted ? .muted : .live)

        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as StackWidget: widget.setValues(values)
            case let widget as MarkWidget: widget.setState(mark)
            default: break
            }
        }
    }

    private func setUpHotkeys() {
        HotkeyManager.shared.onPress = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleMic:
                MicController.shared.toggle()
            case .toggleCleaning:
                InputLocker.shared.toggle()
            case .pushToTalk:
                // Only meaningful while muted, and it must not overwrite the
                // remembered state we return to on release. Not while the keyboard is
                // locked either: the tap swallows the key up, so the release would never
                // arrive and the mic would stay open after cleaning mode ended.
                guard MicController.shared.isMuted, !InputLocker.shared.isLocked else { return }
                self.pushToTalkActive = true
                MicController.shared.setMuted(false, remember: false)
            }
        }
        HotkeyManager.shared.onRelease = { [weak self] action in
            guard let self, action == .pushToTalk else { return }
            self.endPushToTalk()
        }
        HotkeyManager.shared.start()
    }

    /// Returns the mic to the remembered state after a push to talk hold. Called from the
    /// hotkey release and from anything that can swallow that release, because a lost
    /// release used to leave the mic live with the menu still reading muted.
    private func endPushToTalk() {
        guard pushToTalkActive else { return }
        pushToTalkActive = false
        MicController.shared.setMuted(
            UserDefaults.standard.bool(forKey: Pref.micMuteDesired), remember: false)
    }
}
