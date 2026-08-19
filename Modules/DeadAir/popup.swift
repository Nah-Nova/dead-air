//
//  popup.swift
//  DeadAir
//
//  The popup as a bento: one card per concern on a quiet ground, the two sensor
//  tiles paired side by side, controls sitting on the row they govern. The brand
//  lives in the lamps, the mono state words and the accent colours, not in the
//  chrome.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private var state = DeadAirState()

    private var micStateRow: LampStateView? = nil
    private var micDeviceField: NSTextField? = nil
    private var muteSwitch: NSSwitch? = nil
    private var camTile: LampStateView? = nil
    private var micUseTile: LampStateView? = nil
    private var cameraAlertsCheck: NSButton? = nil
    private var logFields: [NSTextField] = []
    private var cleaningRow: LampStateView? = nil
    private var lockButton: NSButton? = nil
    private var durationSelector: NSPopUpButton? = nil
    private var trackpadCheck: NSButton? = nil
    private var camStrip: UsageStrip? = nil
    private var micStrip: UsageStrip? = nil
    private var camTotalField: NSTextField? = nil
    private var micTotalField: NSTextField? = nil
    private var awakeMeter: MeterBar? = nil
    private var awakeRow: LampStateView? = nil
    private var awakeSelector: NSPopUpButton? = nil
    private var displaySleepCheck: NSButton? = nil
    private var lidSleepCheck: NSButton? = nil

    private var refreshTimer: Timer? = nil
    internal var refreshCallback: (() -> Void)? = nil

    private static let gutter: CGFloat = 8

    private var contentWidth: CGFloat {
        Constants.Popup.width - (Self.gutter * 2)
    }

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.alignment = .leading
        self.spacing = Self.gutter
        self.edgeInsets = NSEdgeInsets(
            top: Self.gutter, left: Self.gutter, bottom: Self.gutter, right: Self.gutter)

        self.addCard(self.microphoneCard())
        self.addPair(self.cameraTile(), self.micStreamTile())
        self.addCard(self.usageCard())
        self.addCard(self.cleaningCard())
        self.addCard(self.keepAwakeCard())
        self.addCard(self.activityCard())

        self.recalculateHeight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func appear() {
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshCallback?()
        }
    }

    public override func disappear() {
        self.refreshTimer?.invalidate()
        self.refreshTimer = nil
    }

    // MARK: - Cards

    private func microphoneCard() -> BentoCard {
        let mute = NSSwitch()
        mute.controlSize = .mini
        mute.target = self
        mute.action = #selector(self.muteSwitched)
        self.muteSwitch = mute

        let card = BentoCard(title: localizedString("Microphone"), accessory: mute)

        self.micStateRow = self.lampRow(in: card, key: localizedString("State"))
        self.micDeviceField = self.readoutRow(in: card, key: localizedString("Device"))

        card.content.addArrangedSubview(self.hint(
            "\(HotkeyManager.Action.toggleMic.describedShortcut)   \(localizedString("Push to talk")) \(HotkeyManager.Action.pushToTalk.describedShortcut)"))

        return card
    }

    /// A sensor tile: the card title carries the name, so the tile body is only the
    /// lamp and its state word, set a size up. Nothing else earns the room.
    private func cameraTile() -> BentoCard {
        let card = BentoCard(title: localizedString("Camera"))
        let tile = LampStateView(housingSide: 14, wordFont: Brand.Font.utility(size: 12, weight: .semibold))
        self.camTile = tile
        card.content.addArrangedSubview(tile)
        return card
    }

    private func micStreamTile() -> BentoCard {
        let card = BentoCard(title: localizedString("Mic stream"))
        let tile = LampStateView(housingSide: 14, wordFont: Brand.Font.utility(size: 12, weight: .semibold))
        self.micUseTile = tile
        card.content.addArrangedSubview(tile)
        return card
    }

    /// The last eight hours, one cell per five minutes, reconstructed from the activation
    /// log. It answers the question the state tiles cannot: not "is the camera on" but
    /// "how much has it been on today".
    private func usageCard() -> BentoCard {
        let card = BentoCard(title: localizedString("Last 8 hours"))

        let (camStrip, camTotal) = self.stripRow(in: card, key: localizedString("Camera"))
        self.camStrip = camStrip
        self.camTotalField = camTotal

        let (micStrip, micTotal) = self.stripRow(in: card, key: localizedString("Mic stream"))
        self.micStrip = micStrip
        self.micTotalField = micTotal

        return card
    }

    private func cleaningCard() -> BentoCard {
        let card = BentoCard(title: localizedString("Cleaning mode"))

        self.cleaningRow = self.lampRow(in: card, key: localizedString("Keyboard"))

        let button = NSButton()
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = Brand.Font.body(size: 11)
        button.title = localizedString("Lock to clean")
        button.target = self
        button.action = #selector(self.toggleCleaning)
        self.lockButton = button

        let duration = NSPopUpButton()
        duration.controlSize = .small
        duration.font = Brand.Font.body(size: 11)
        duration.target = self
        duration.action = #selector(self.durationSelected)
        InputLocker.durationOptions.forEach { duration.addItem(withTitle: localizedString($0.title)) }
        let current = UserDefaults.standard.double(forKey: Pref.cleaningDuration)
        if let index = InputLocker.durationOptions.firstIndex(where: { $0.seconds == current }) {
            duration.selectItem(at: index)
        }
        self.durationSelector = duration

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.addArrangedSubview(button)
        controls.addArrangedSubview(duration)
        card.content.addArrangedSubview(controls)

        let trackpad = self.checkbox(
            title: localizedString("Also lock the trackpad"),
            checked: UserDefaults.standard.bool(forKey: Pref.lockTrackpad),
            action: #selector(self.trackpadToggled))
        self.trackpadCheck = trackpad
        card.content.addArrangedSubview(trackpad)

        card.content.addArrangedSubview(self.hint(
            "\(localizedString("Unlock")) \(localizedString("hold both ⌘ keys for 3 seconds"))"))

        return card
    }

    private func keepAwakeCard() -> BentoCard {
        let card = BentoCard(title: localizedString("Keep awake"))

        self.awakeRow = self.lampRow(in: card, key: localizedString("State"))

        let meter = MeterBar()
        self.awakeMeter = meter
        card.content.addArrangedSubview(meter)
        meter.widthAnchor.constraint(equalTo: card.content.widthAnchor).isActive = true

        let selector = NSPopUpButton()
        selector.controlSize = .small
        selector.font = Brand.Font.body(size: 11)
        selector.target = self
        selector.action = #selector(self.keepAwakeSelected)
        selector.addItem(withTitle: localizedString("Off"))
        KeepAwake.presets.forEach { selector.addItem(withTitle: localizedString($0.title)) }
        self.awakeSelector = selector
        card.content.addArrangedSubview(selector)

        let displaySleep = self.checkbox(
            title: localizedString("Let the display sleep"),
            checked: UserDefaults.standard.bool(forKey: Pref.allowDisplaySleep),
            action: #selector(self.displaySleepToggled))
        self.displaySleepCheck = displaySleep
        card.content.addArrangedSubview(displaySleep)

        let lidSleep = self.checkbox(
            title: localizedString("Stay awake with the lid closed"),
            checked: false,
            action: #selector(self.lidSleepToggled))
        self.lidSleepCheck = lidSleep
        card.content.addArrangedSubview(lidSleep)

        card.content.addArrangedSubview(self.hint(
            localizedString("With no end time set, a banner reminds you every hour")))

        return card
    }

    /// The closer look. macOS does not reveal which app is responsible, so the log
    /// deliberately records only what happened and when.
    private func activityCard() -> BentoCard {
        let alerts = self.checkbox(
            title: localizedString("Banner"),
            checked: UserDefaults.standard.bool(forKey: Pref.cameraAlerts),
            action: #selector(self.cameraAlertsToggled))
        self.cameraAlertsCheck = alerts

        let card = BentoCard(title: localizedString("Activity"), accessory: alerts)

        for _ in 0..<3 {
            let line = NSTextField(labelWithString: "")
            line.font = Brand.Font.utility(size: 10)
            line.textColor = Brand.legendTertiary
            line.lineBreakMode = .byTruncatingTail
            self.logFields.append(line)
            card.content.addArrangedSubview(line)
        }

        return card
    }

    // MARK: - Render

    internal func callback(_ state: DeadAirState) {
        self.state = state

        if !state.hasInputDevice {
            self.micStateRow?.set(
                state: localizedString("No input device"),
                bead: Brand.lampUnlit, glowing: false, color: Brand.legendSecondary)
        } else if state.micMuted {
            self.micStateRow?.set(
                state: localizedString("Muted"),
                bead: Brand.lampDead, glowing: false, color: Brand.stateDead)
        } else {
            self.micStateRow?.set(
                state: localizedString("Live"),
                bead: Brand.lampLit, glowing: true, color: Brand.stateLive)
        }
        self.micDeviceField?.stringValue = state.micDevice
        self.muteSwitch?.state = state.micMuted ? .on : .off
        self.muteSwitch?.isEnabled = state.hasInputDevice

        if state.cameraInUse {
            self.camTile?.set(
                state: localizedString("In use"),
                bead: Brand.lampLit, glowing: true, color: Brand.stateLive)
        } else {
            self.camTile?.set(
                state: localizedString("Off"),
                bead: Brand.lampUnlit, glowing: false, color: Brand.legendSecondary)
        }
        if state.micInUse {
            self.micUseTile?.set(
                state: localizedString("Active"),
                bead: Brand.lampLit, glowing: true, color: Brand.stateLive)
        } else {
            self.micUseTile?.set(
                state: localizedString("Idle"),
                bead: Brand.lampUnlit, glowing: false, color: Brand.legendSecondary)
        }

        let events = Array(ActivationLog.shared.events.suffix(3).reversed())
        for (i, field) in self.logFields.enumerated() {
            if i < events.count {
                field.stringValue = ActivationLog.shared.describe(events[i])
            } else {
                field.stringValue = i == 0 && events.isEmpty ? localizedString("No activity yet") : ""
            }
        }

        if state.cleaningLocked {
            self.cleaningRow?.set(
                state: localizedString(state.cleaningStatus),
                bead: Brand.lampDead, glowing: false, color: Brand.stateDead)
        } else {
            self.cleaningRow?.set(
                state: localizedString(state.cleaningStatus),
                bead: Brand.lampUnlit, glowing: false, color: Brand.legendSecondary)
        }
        self.lockButton?.title = state.cleaningLocked ? localizedString("Unlock") : localizedString("Lock to clean")

        if state.keepAwakeActive {
            self.awakeRow?.set(
                state: localizedString(state.keepAwakeStatus),
                bead: Brand.lampLit, glowing: true, color: Brand.legendPrimary)
        } else {
            self.awakeRow?.set(
                state: localizedString(state.keepAwakeStatus),
                bead: Brand.lampUnlit, glowing: false, color: Brand.legendSecondary)
        }
        self.renderUsage()

        if let meter = self.awakeMeter {
            // A session with no end time has no fraction to draw, so the meter stays empty
            // rather than inventing a full bar.
            meter.set(fraction: state.keepAwakeFraction)
            meter.isHidden = !state.keepAwakeActive || state.keepAwakeFraction <= 0
        }

        self.lidSleepCheck?.state = state.sleepDisabled ? .on : .off

        if let selector = self.awakeSelector {
            let wanted = state.keepAwakeActive ? (KeepAwake.shared.activePresetIndex ?? -1) + 1 : 0
            if selector.indexOfSelectedItem != wanted && wanted >= 0 {
                selector.selectItem(at: wanted)
            }
        }

        // The meter appears and disappears with a finite session, which changes the height
        // of its card, so the popup is measured again rather than only at init.
        self.recalculateHeight()
    }

    /// Eight hours in five minute cells. Recomputed on the popup's own one second tick,
    /// which is cheap: it is a scan of at most 500 stored transitions.
    private func renderUsage() {
        let window: TimeInterval = 8 * 60 * 60
        let buckets = 96
        let since = Date().addingTimeInterval(-window)
        let log = ActivationLog.shared

        self.camStrip?.set(log.occupancy(kind: .camera, since: since, buckets: buckets))
        self.micStrip?.set(log.occupancy(kind: .microphone, since: since, buckets: buckets))
        self.camTotalField?.stringValue = ActivationLog.describe(
            duration: log.duration(kind: .camera, since: since))
        self.micTotalField?.stringValue = ActivationLog.describe(
            duration: log.duration(kind: .microphone, since: since))
    }

    // MARK: - Actions

    @objc private func muteSwitched(_ sender: NSSwitch) {
        MicController.shared.setMuted(sender.state == .on)
    }

    @objc private func toggleCleaning() {
        InputLocker.shared.toggle()
    }

    @objc private func durationSelected(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard InputLocker.durationOptions.indices.contains(index) else { return }
        UserDefaults.standard.set(InputLocker.durationOptions[index].seconds, forKey: Pref.cleaningDuration)
    }

    @objc private func trackpadToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Pref.lockTrackpad)
    }

    @objc private func cameraAlertsToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Pref.cameraAlerts)
    }

    @objc private func displaySleepToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Pref.allowDisplaySleep)
        KeepAwake.shared.reapplyIfActive()
    }

    /// Unlike everything else here this changes a system wide setting that survives
    /// reboots, so `LidSleep` confirms before doing anything and macOS asks for the
    /// password itself. The box is redrawn from the real state afterwards, because the
    /// user can cancel at the password dialog.
    @objc private func lidSleepToggled(_ sender: NSButton) {
        LidSleep.toggle()
        DispatchQueue.global(qos: .userInitiated).async {
            let disabled = LidSleep.isDisabled
            DispatchQueue.main.async { sender.state = disabled ? .on : .off }
        }
    }

    @objc private func keepAwakeSelected(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        if index <= 0 {
            KeepAwake.shared.deactivate()
        } else {
            KeepAwake.shared.activate(presetIndex: index - 1)
        }
    }

    // MARK: - Bento layout

    private func addCard(_ card: NSView) {
        card.translatesAutoresizingMaskIntoConstraints = false
        self.addArrangedSubview(card)
        card.widthAnchor.constraint(equalToConstant: self.contentWidth).isActive = true
    }

    /// Two tiles on one line, each taking half the gutter-separated width. The only
    /// place the grid splits, because a sensor state is the one readout small enough
    /// to share a line.
    private func addPair(_ left: NSView, _ right: NSView) {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = Self.gutter
        row.addArrangedSubview(left)
        row.addArrangedSubview(right)

        self.addArrangedSubview(row)
        row.widthAnchor.constraint(equalToConstant: self.contentWidth).isActive = true
    }

    // MARK: - Rows

    private func lampRow(in card: BentoCard, key: String) -> LampStateView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4

        // Built from a plain string, not an attributed one: an attributed string carries
        // its own font and silently wins over a later assignment, which left every key
        // two points taller than the design next to it.
        let keyField = NSTextField(labelWithString: key)
        keyField.font = Brand.Font.body(size: 11)
        keyField.textColor = Brand.legendSecondary

        let value = LampStateView()

        row.addArrangedSubview(keyField)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(value)
        card.content.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: card.content.widthAnchor).isActive = true

        return value
    }

    private func readoutRow(in card: BentoCard, key: String) -> NSTextField {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4

        // Built from a plain string, not an attributed one: an attributed string carries
        // its own font and silently wins over a later assignment, which left every key
        // two points taller than the design next to it.
        let keyField = NSTextField(labelWithString: key)
        keyField.font = Brand.Font.body(size: 11)
        keyField.textColor = Brand.legendSecondary

        let valueField = NSTextField(labelWithString: "")
        valueField.font = Brand.Font.utility(size: 11)
        valueField.textColor = Brand.legendSecondary
        valueField.alignment = .right
        valueField.lineBreakMode = .byTruncatingTail

        row.addArrangedSubview(keyField)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(valueField)
        card.content.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: card.content.widthAnchor).isActive = true

        return valueField
    }

    /// A key and its total on one line, with the strip filling the width underneath.
    private func stripRow(in card: BentoCard, key: String) -> (UsageStrip, NSTextField) {
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 4

        let keyField = NSTextField(labelWithString: key)
        keyField.font = Brand.Font.body(size: 11)
        keyField.textColor = Brand.legendSecondary

        let totalField = NSTextField(labelWithString: "")
        totalField.font = Brand.Font.utility(size: 11)
        totalField.textColor = Brand.legendPrimary
        totalField.alignment = .right

        header.addArrangedSubview(keyField)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(totalField)
        card.content.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: card.content.widthAnchor).isActive = true

        let strip = UsageStrip()
        card.content.addArrangedSubview(strip)
        strip.widthAnchor.constraint(equalTo: card.content.widthAnchor).isActive = true

        return (strip, totalField)
    }

    private func checkbox(title: String, checked: Bool, action: Selector) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: self, action: action)
        box.controlSize = .small
        box.font = Brand.Font.body(size: 11)
        box.state = checked ? .on : .off
        return box
    }

    private func hint(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Brand.Font.body(size: 10)
        field.textColor = Brand.legendTertiary
        field.lineBreakMode = .byTruncatingTail
        field.isSelectable = false
        return field
    }

    private func recalculateHeight() {
        let cards = self.arrangedSubviews.map { $0.fittingSize.height }.reduce(0, +)
        let gaps = CGFloat(max(0, self.arrangedSubviews.count - 1)) * self.spacing
        let height = cards + gaps + self.edgeInsets.top + self.edgeInsets.bottom
        if self.frame.size.height != height {
            self.setFrameSize(NSSize(width: self.frame.width, height: height))
            self.sizeCallback?(self.frame.size)
        }
    }
}

/// A tally lamp and its mono state word, drawn as one piece of hardware so nothing can
/// clip the lamp's glow. The bead carries the lamp rules: amber only when something is
/// lit, oxide for dead, dull for idle, and the word beside it is always the second
/// channel, never amber.
internal final class LampStateView: NSView {
    private var word = NSAttributedString()
    private var bead: NSColor = Brand.lampUnlit
    private var glowing = false

    private let housingSide: CGFloat
    private let wordFont: NSFont
    private static let gap: CGFloat = 6

    init(housingSide: CGFloat = 11, wordFont: NSFont? = nil) {
        self.housingSide = housingSide
        self.wordFont = wordFont ?? Brand.Font.utility(size: 11)
        super.init(frame: .zero)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        fatalError("LampStateView is built in code only")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: housingSide + Self.gap + ceil(word.size().width),
            height: max(housingSide + 4, ceil(word.size().height)))
    }

    func set(state: String, bead: NSColor, glowing: Bool, color: NSColor) {
        let word = Brand.stateWord(state, color: color)
        word.addAttribute(
            .font, value: self.wordFont, range: NSRange(location: 0, length: word.length))
        self.word = word
        self.bead = bead
        self.glowing = glowing
        setAccessibilityLabel(state)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let housing = NSRect(
            x: 0, y: ((bounds.height - housingSide) / 2).rounded(),
            width: housingSide, height: housingSide)
        Brand.drawLamp(in: housing, bead: bead, glowing: glowing)

        let size = word.size()
        word.draw(at: NSPoint(x: housing.maxX + Self.gap, y: (bounds.height - size.height) / 2))
    }
}
