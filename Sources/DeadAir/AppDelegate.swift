import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var pushToTalkActive = false
    /// Unhighlighted attributed titles, so `willHighlight` can put them back.
    private var brandedTitles: [ObjectIdentifier: NSAttributedString] = [:]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.register()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        MicController.shared.start()
        SensorMonitor.shared.start()
        setUpHotkeys()

        for name in [
            MicController.didChange, SensorMonitor.didChange, InputLocker.didChange,
            KeepAwake.didChange,
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(stateChanged), name: name, object: nil)
        }

        updateStatusIcon()

        if ProcessInfo.processInfo.environment["DEADAIR_SELFTEST"] != nil {
            runSelfTest()
        }
        if ProcessInfo.processInfo.environment["DEADAIR_REQUEST_AX"] != nil {
            grantAccessibility()
        }
    }

    /// Builds every menu and exercises the toggles that need no permission, so a
    /// crash in menu construction shows up without anyone having to click.
    /// Run with `DEADAIR_SELFTEST=1 ./build/DeadAir.app/Contents/MacOS/DeadAir`.
    private func runSelfTest() {
        func dump(_ menu: NSMenu, indent: String = "  ") {
            for item in menu.items {
                let mark = item.state == .on ? "[x]" : (item.isEnabled ? "[ ]" : "   ")
                print("\(indent)\(mark) \(item.isSeparatorItem ? "---" : item.title)")
                if let submenu = item.submenu { dump(submenu, indent: indent + "    ") }
            }
        }

        print("accessibility granted: \(InputLocker.hasAccessibility)")
        let failed = HotkeyManager.shared.failedActions
        print(
            "hotkeys failed to register: "
                + (failed.isEmpty ? "none" : failed.map(\.describedShortcut).joined(separator: ", ")))
        print("mic device: \(MicController.shared.deviceName), muted: \(MicController.shared.isMuted)")
        print("camera in use: \(SensorMonitor.shared.cameraInUse)")

        let menu = statusItem.menu!
        menuNeedsUpdate(menu)
        print("--- MENU (\(menu.items.count) top-level items) ---")
        dump(menu)

        KeepAwake.shared.activate(presetIndex: 0)
        print("keep awake after activate: \(KeepAwake.shared.statusDescription)")
        KeepAwake.shared.deactivate()
        print("keep awake after deactivate: \(KeepAwake.shared.statusDescription)")

        print("--- MENU WITH TRACKPAD LOCK ON ---")
        UserDefaults.standard.set(true, forKey: Pref.lockTrackpad)
        menuNeedsUpdate(menu)
        dump(menu)
        UserDefaults.standard.set(false, forKey: Pref.lockTrackpad)

        if let dir = ProcessInfo.processInfo.environment["DEADAIR_ICON_DUMP"] {
            for (name, state) in [
                ("live", StatusIcon.State.live), ("muted", .muted), ("locked", .locked),
            ] {
                // Rendered at 8x so the shape is inspectable, same paths as the bar uses.
                let image = StatusIcon.image(for: state)
                let scaled = NSSize(width: image.size.width * 8, height: image.size.height * 8)
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(scaled.width),
                    pixelsHigh: Int(scaled.height), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSColor.white.setFill()
                NSRect(origin: .zero, size: scaled).fill()
                image.draw(in: NSRect(origin: .zero, size: scaled))
                NSGraphicsContext.restoreGraphicsState()
                let data = bitmap.representation(using: .png, properties: [:])!
                let url = URL(fileURLWithPath: dir).appendingPathComponent("icon-\(name).png")
                try? data.write(to: url)
                print("wrote \(url.path)")
            }
        }

        if let dir = ProcessInfo.processInfo.environment["DEADAIR_UI_DUMP"] {
            dumpBrandViews(to: dir)
        }

        print("selftest complete")
        NSApp.terminate(nil)
    }

    /// Renders every custom menu view, and the lamp images that ride on interactive rows,
    /// so the look can be judged without anyone opening the menu. Each one is drawn at 3x
    /// on the brand ground it actually sits on, once per appearance, because a dark-on-dark
    /// mistake only shows up in the theme it happens in.
    /// Run with `DEADAIR_SELFTEST=1 DEADAIR_UI_DUMP=/some/dir ...`.
    private func dumpBrandViews(to dir: String) {
        let scale: CGFloat = 3
        let themes: [(String, NSAppearance.Name, NSColor)] = [
            ("light", .vibrantLight, Brand.groundPanel),
            ("dark", .vibrantDark, Brand.groundBlackout),
        ]

        func write(_ name: String, size: NSSize, draw: (NSRect) -> Void) {
            for (suffix, appearanceName, ground) in themes {
                guard let appearance = NSAppearance(named: appearanceName) else { continue }
                let scaled = NSSize(width: size.width * scale, height: size.height * scale)
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(scaled.width),
                    pixelsHigh: Int(scaled.height), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                appearance.performAsCurrentDrawingAppearance {
                    ground.setFill()
                    NSRect(origin: .zero, size: scaled).fill()
                    let transform = NSAffineTransform()
                    transform.scale(by: scale)
                    transform.concat()
                    draw(NSRect(origin: .zero, size: size))
                }
                NSGraphicsContext.restoreGraphicsState()
                let data = bitmap.representation(using: .png, properties: [:])!
                let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(suffix).png")
                try? data.write(to: url)
                print("wrote \(url.path)")
            }
        }

        for (name, view) in [
            ("lamprow-camera-in-use", MenuLampRow(label: "Camera", state: "in use", lit: true)),
            ("lamprow-camera-idle", MenuLampRow(label: "Camera", state: "idle", lit: false)),
            ("lamprow-mic-stream-active", MenuLampRow(label: "Mic stream", state: "active", lit: true)),
            ("lamprow-mic-stream-idle", MenuLampRow(label: "Mic stream", state: "idle", lit: false)),
        ] {
            write(name, size: view.bounds.size) { rect in view.draw(rect) }
        }

        for (name, bead, glow) in [
            ("lamp-lit", Brand.lampLit, true), ("lamp-dead", Brand.lampDead, false),
            ("lamp-unlit", Brand.lampUnlit, false),
        ] {
            let image = Brand.lampImage(bead: bead, glowing: glow)
            write(name, size: image.size) { rect in image.draw(in: rect) }
        }

        // The banner and the overlay are view hierarchies, not single custom draws, so
        // cacheDisplay has to walk them. draw(_:) alone would paint the container and leave
        // every label out, which would have looked like a working render of nothing.
        for (suffix, appearanceName) in [("light", NSAppearance.Name.vibrantLight), ("dark", .vibrantDark)] {
            let banner = AlertBanner.content(
                title: "Camera is on",
                subtitle: "macOS does not reveal which app. Check the green dot.")
            writeHierarchy("banner-camera-\(suffix)", view: banner, appearance: appearanceName, to: dir)
        }

        // Only ever rendered dark: the overlay pins its window to darkAqua, so a light
        // variant would be a picture of a state that cannot happen.
        for (name, trackpadLocked) in [("overlay", false), ("overlay-trackpad-locked", true)] {
            // The overlay has to outlive the render: NSButton holds its target weakly, so a
            // temporary would leave the unlock button unwired before it is drawn.
            let overlay = CleaningOverlay()
            withExtendedLifetime(overlay) {
                let content = overlay.renderableContent(
                    size: NSSize(width: 1280, height: 720),
                    trackpadLocked: trackpadLocked,
                    status: "Unlocks automatically in 47s")
                writeHierarchy(name, view: content, appearance: .darkAqua, to: dir)
            }
        }
    }

    /// Renders a whole view tree by hanging it in an offscreen window, so the appearance and
    /// every subview resolve exactly as they do on screen.
    private func writeHierarchy(
        _ name: String, view: NSView, appearance: NSAppearance.Name, to dir: String
    ) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: view.bounds.size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("could not cache \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("wrote \(url.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        InputLocker.shared.unlock()
        KeepAwake.shared.deactivate()
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
                // remembered state we return to on release.
                guard MicController.shared.isMuted else { return }
                self.pushToTalkActive = true
                MicController.shared.setMuted(false, remember: false)
            }
        }
        HotkeyManager.shared.onRelease = { [weak self] action in
            guard let self, action == .pushToTalk, self.pushToTalkActive else { return }
            self.pushToTalkActive = false
            MicController.shared.setMuted(true, remember: false)
        }
        HotkeyManager.shared.start()
    }

    @objc private func stateChanged() {
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let state: StatusIcon.State
        if InputLocker.shared.isLocked {
            state = .locked
        } else if MicController.shared.isMuted {
            state = .muted
        } else {
            state = .live
        }
        statusItem.button?.image = StatusIcon.image(for: state)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Submenus share this delegate so they get `willHighlight` too, so only the root
        // menu may rebuild itself here.
        guard menu === statusItem.menu else { return }

        brandedTitles.removeAll()
        menu.removeAllItems()

        addLegend(to: menu, "Microphone")

        let mic = MicController.shared
        let micState = mic.isMuted ? "muted" : "live"
        // The state word alone, in mono, with the lamp carrying the colour: a switch on a
        // panel rather than a sentence. item.title keeps the full readout.
        let micRow = add(
            to: menu,
            title: "Microphone: \(micState)",
            display: Brand.stateWord(micState),
            action: #selector(toggleMic),
            shortcut: HotkeyManager.Action.toggleMic.describedShortcut)
        // A lit tally is amber, the same as every other lamp in the app. It used to be teal
        // here, which gave the app two colours for one fact while the sensor rows next to it
        // lit amber for the same thing.
        micRow.image = Brand.lampImage(
            bead: mic.isMuted ? Brand.lampDead : Brand.lampLit, glowing: !mic.isMuted)

        add(
            to: menu, readout: mic.hasInputDevice ? mic.deviceName : "No input device",
            dead: !mic.hasInputDevice)
        let pushToTalk = HotkeyManager.Action.pushToTalk.describedShortcut
        add(to: menu, hint: "Push to talk: hold \(pushToTalk)", mono: [pushToTalk])

        menu.addItem(.separator())
        addLegend(to: menu, "Sensors")

        let monitor = SensorMonitor.shared
        addLamp(
            to: menu, label: "Camera", state: monitor.cameraInUse ? "in use" : "idle",
            lit: monitor.cameraInUse)
        addLamp(
            to: menu, label: "Mic stream", state: monitor.micInUse ? "active" : "idle",
            lit: monitor.micInUse)
        menu.addItem(logSubmenuItem())

        menu.addItem(.separator())
        addLegend(to: menu, "Input")

        let locker = InputLocker.shared
        // Read the countdown once, or the mono run would be searching for a value that has
        // already ticked on.
        let remaining = locker.isLocked ? locker.remainingDescription : nil
        add(
            to: menu,
            title: remaining.map { "Unlock input (\($0))" } ?? "Lock input for cleaning",
            action: #selector(toggleCleaning),
            shortcut: HotkeyManager.Action.toggleCleaning.describedShortcut,
            mono: remaining.map { [$0] } ?? [])
        menu.addItem(cleaningSubmenuItem())
        if !InputLocker.hasAccessibility {
            // A blocked capability is the dead state, and an oxide bead survives the
            // selection fill in a way a coloured title would not.
            let grant = add(
                to: menu, title: "Grant Accessibility access…",
                action: #selector(grantAccessibility))
            grant.image = Brand.lampImage(bead: Brand.lampDead)
        }

        menu.addItem(.separator())
        addLegend(to: menu, "Power")

        menu.addItem(keepAwakeSubmenuItem())

        menu.addItem(.separator())

        add(
            to: menu, title: "Warn when camera turns on", action: #selector(toggleCameraAlerts),
            state: UserDefaults.standard.bool(forKey: Pref.cameraAlerts))
        add(
            to: menu, title: "Launch at login", action: #selector(toggleLaunchAtLogin),
            state: SMAppService.mainApp.status == .enabled)

        menu.addItem(.separator())

        add(to: menu, title: "About Dead Air", action: #selector(showAbout))
        add(to: menu, title: "Quit", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items { item.submenu?.delegate = self }
    }

    /// AppKit substitutes `selectedMenuItemTextColor` only for plain titles. An item with an
    /// `attributedTitle` is drawn with the string's own colours, so without this the branded
    /// rows keep dark type sitting on the selection fill while every plain row inverts.
    ///
    /// The unhighlighted string is captured on first highlight, which is safe because it is
    /// still the original at that point, and dropped whenever the menu rebuilds.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for candidate in menu.items where candidate.attributedTitle != nil {
            let key = ObjectIdentifier(candidate)
            if candidate === item {
                if brandedTitles[key] == nil, let current = candidate.attributedTitle {
                    brandedTitles[key] = current
                }
                guard let base = brandedTitles[key] else { continue }
                candidate.attributedTitle = Self.inverted(base)
            } else if let base = brandedTitles[key] {
                candidate.attributedTitle = base
            }
        }
    }

    private static func inverted(_ base: NSAttributedString) -> NSAttributedString {
        let inverted = NSMutableAttributedString(attributedString: base)
        inverted.addAttribute(
            .foregroundColor, value: NSColor.selectedMenuItemTextColor,
            range: NSRange(location: 0, length: inverted.length))
        return inverted
    }

    private func cleaningSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Cleaning options", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = UserDefaults.standard.double(forKey: Pref.cleaningDuration)

        addLegend(to: submenu, "Auto unlock after")
        for option in InputLocker.durationOptions {
            let entry = add(
                to: submenu, title: option.title, action: #selector(setCleaningDuration),
                state: current == option.seconds)
            entry.indentationLevel = 1
            entry.representedObject = option.seconds
        }

        submenu.addItem(.separator())
        add(
            to: submenu, title: "Lock trackpad too", action: #selector(toggleLockTrackpad),
            state: UserDefaults.standard.bool(forKey: Pref.lockTrackpad))
        add(
            to: submenu, title: "Black screen overlay", action: #selector(toggleOverlay),
            state: UserDefaults.standard.bool(forKey: Pref.showOverlay))
        submenu.addItem(.separator())
        add(to: submenu, hint: "Hold both ⌘ keys 3s to unlock", mono: ["⌘"])
        if UserDefaults.standard.bool(forKey: Pref.lockTrackpad) {
            add(to: submenu, caveat: "Trackpad lock caps the timeout at 5 min")
        }

        item.submenu = submenu
        return item
    }

    private func keepAwakeSubmenuItem() -> NSMenuItem {
        let keepAwake = KeepAwake.shared
        let status = keepAwake.statusDescription
        let item = NSMenuItem(
            title: "Keep awake: \(status)", action: nil, keyEquivalent: "")
        // attributedTitle only. A view here would cost the disclosure arrow and
        // hover-to-open.
        item.attributedTitle = Brand.menuLabel(item.title, mono: [status])
        let submenu = NSMenu()

        add(
            to: submenu, title: "Off", action: #selector(keepAwakeOff),
            state: !keepAwake.isActive)
        submenu.addItem(.separator())
        for (index, preset) in KeepAwake.presets.enumerated() {
            let entry = add(
                to: submenu, title: preset.title, action: #selector(setKeepAwake),
                state: keepAwake.isActive && keepAwake.activePresetIndex == index)
            entry.representedObject = index
        }
        submenu.addItem(.separator())
        add(
            to: submenu, title: "Let the display sleep",
            action: #selector(toggleAllowDisplaySleep),
            state: UserDefaults.standard.bool(forKey: Pref.allowDisplaySleep))
        add(
            to: submenu, title: "Stay awake with the lid closed",
            action: #selector(toggleLidSleep), state: LidSleep.isDisabled)
        add(to: submenu, note: "Asks for your admin password")

        item.submenu = submenu
        return item
    }

    private func logSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Recent activity", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let log = ActivationLog.shared
        let recent = log.events.suffix(15).reversed()

        if recent.isEmpty {
            add(to: submenu, readout: "Nothing recorded yet", quiet: true)
        } else {
            for event in recent {
                // Mono, so the timestamp column lines up and the list reads as a log.
                add(to: submenu, readout: log.describe(event))
            }
            submenu.addItem(.separator())
            add(to: submenu, title: "Copy full log", action: #selector(copyLog))
            add(to: submenu, title: "Clear log", action: #selector(clearLog))
        }
        add(to: submenu, note: "macOS does not expose the app name")

        item.submenu = submenu
        return item
    }

    // MARK: - Menu helpers

    /// Interactive rows stay stock NSMenuItems and are branded by font alone. A pinned
    /// brand colour would not invert under the selection fill, and a custom view would
    /// cost the checkmark, the highlight and keyboard navigation.
    ///
    /// `display` replaces the rendered text where the row reads better as hardware than as
    /// a sentence; `mono` re-sets machine-printed runs inside the title. `item.title` is
    /// the plain readout either way, which is what the selftest dump and VoiceOver read.
    @discardableResult
    private func add(
        to menu: NSMenu, title: String, display: NSAttributedString? = nil, action: Selector,
        shortcut: String? = nil, keyEquivalent: String = "", state: Bool? = nil,
        mono: [String] = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let state { item.state = state ? .on : .off }
        if display != nil || shortcut != nil || !mono.isEmpty {
            let base: NSAttributedString = display ?? Brand.menuLabel(title, mono: mono)
            let attributed = NSMutableAttributedString(attributedString: base)
            if let shortcut {
                // Carbon owns the real hotkey, so this is a label rather than a binding.
                attributed.append(NSAttributedString(string: "   "))
                attributed.append(Brand.shortcutLabel(shortcut))
            }
            item.attributedTitle = attributed
            // Setting attributedTitle wipes the plain title, and the selftest dump and
            // VoiceOver both read that. Rendering keeps following the attributed string.
            item.title = title
        }
        menu.addItem(item)
        return item
    }

    /// A silkscreen head over a block of rows. Disabled, so keyboard navigation never
    /// lands on decoration.
    private func addLegend(to menu: NSMenu, _ text: String) {
        // Plain text in `title`, since that is what the selftest dump and VoiceOver read.
        // `Brand.legend` already owns the uppercasing for rendering.
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = Brand.legend(text)
        item.isEnabled = false
        menu.addItem(item)
    }

    /// A row a machine printed: a device name, a log line, an empty log.
    private func add(to menu: NSMenu, readout title: String, dead: Bool = false, quiet: Bool = false) {
        let colour = dead ? Brand.stateDead : (quiet ? Brand.legendTertiary : Brand.legendSecondary)
        addDisabled(to: menu, title: title, styled: Brand.readout(title, color: colour))
    }

    /// A sentence, with any machine-printed run in it set in the utility face.
    private func add(to menu: NSMenu, hint title: String, mono: [String] = []) {
        addDisabled(
            to: menu, title: title,
            styled: Brand.menuLabel(
                title, mono: mono, color: Brand.legendSecondary, monoColor: Brand.legendSecondary))
    }

    /// A limit the app imposes. Oxide is the accent voice, so a constraint reads as one.
    private func add(to menu: NSMenu, caveat title: String) {
        addDisabled(
            to: menu, title: title, styled: Brand.menuLabel(title, color: Brand.stateDead))
    }

    /// Something macOS will not tell us. The quietest row in the menu, and it never
    /// carries state.
    private func add(to menu: NSMenu, note title: String) {
        addDisabled(
            to: menu, title: title, styled: Brand.menuLabel(title, color: Brand.legendTertiary))
    }

    /// A lamp and its readout on a painted plate. A custom view is safe here only because
    /// the row is disabled.
    private func addLamp(to menu: NSMenu, label: String, state: String, lit: Bool) {
        let item = NSMenuItem(title: "\(label): \(state)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.view = MenuLampRow(label: label, state: state, lit: lit)
        menu.addItem(item)
    }

    private func addDisabled(to menu: NSMenu, title: String, styled: NSAttributedString) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = styled
        item.title = title
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func toggleMic() {
        MicController.shared.toggle()
    }

    @objc private func toggleCleaning() {
        InputLocker.shared.toggle()
    }

    /// Fires the system Accessibility prompt and opens the pane. macOS only shows the
    /// dialog once per code identity, so a rebuild gets a fresh prompt and a stale
    /// entry gets none.
    @objc private func grantAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        InputLocker.requestAccessibility()
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func setCleaningDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        UserDefaults.standard.set(seconds, forKey: Pref.cleaningDuration)
    }

    @objc private func toggleLockTrackpad() {
        let key = Pref.lockTrackpad
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }

    @objc private func toggleOverlay() {
        let key = Pref.showOverlay
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }

    @objc private func toggleCameraAlerts() {
        let key = Pref.cameraAlerts
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }

    @objc private func setKeepAwake(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        KeepAwake.shared.activate(presetIndex: index)
    }

    @objc private func keepAwakeOff() {
        KeepAwake.shared.deactivate()
    }

    @objc private func toggleLidSleep() {
        LidSleep.toggle()
    }

    @objc private func toggleAllowDisplaySleep() {
        let key = Pref.allowDisplaySleep
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        KeepAwake.shared.reapplyIfActive()
    }

    @objc private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ActivationLog.shared.formattedAll(), forType: .string)
    }

    @objc private func clearLog() {
        ActivationLog.shared.clear()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = """
                \(error.localizedDescription)

                This usually means the app is not in a stable location. Move Dead Air \
                to ~/Applications or /Applications and try again.
                """
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func showAbout() {
        let failed = HotkeyManager.shared.failedActions
        let hotkeyNote =
            failed.isEmpty
            ? "All hotkeys registered."
            : "Unavailable, another app owns them: "
                + failed.map(\.describedShortcut).joined(separator: ", ")

        let alert = NSAlert()
        alert.messageText = "Dead Air"
        alert.informativeText = """
            Mute the mic, lock the keyboard for cleaning, watch the camera, keep the Mac awake.

            The camera cannot be disabled. macOS offers no API for it, so Dead Air reports \
            camera use instead of pretending to block it. It also cannot name the app using \
            the camera or mic, because macOS does not expose that either.

            \(hotkeyNote)
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
