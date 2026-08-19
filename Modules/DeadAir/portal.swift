//
//  portal.swift
//  DeadAir
//
//  The dashboard tile: four state lines, no controls. Each line is a tally lamp and
//  its mono state word, same hardware as the popup rows.
//

import AppKit
import Kit

public class Portal: PortalWrapper {
    private var micRow: LampStateView? = nil
    private var camRow: LampStateView? = nil
    private var lockRow: LampStateView? = nil
    private var awakeRow: LampStateView? = nil

    public override func load() {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 4

        self.micRow = self.row(in: container, key: localizedString("Microphone"))
        self.camRow = self.row(in: container, key: localizedString("Camera"))
        self.lockRow = self.row(in: container, key: localizedString("Keyboard"))
        self.awakeRow = self.row(in: container, key: localizedString("Keep awake"))

        self.body.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: self.body.widthAnchor).isActive = true
    }

    internal func callback(_ state: DeadAirState) {
        if state.micMuted {
            self.micRow?.set(
                state: localizedString("Muted"),
                bead: Brand.lampDead, glowing: false, color: Brand.stateDead)
        } else {
            self.micRow?.set(
                state: localizedString("Live"),
                bead: Brand.lampLit, glowing: true, color: Brand.stateLive)
        }
        if state.cameraInUse {
            self.camRow?.set(
                state: localizedString("In use"),
                bead: Brand.lampLit, glowing: true, color: Brand.stateLive)
        } else {
            self.camRow?.set(
                state: localizedString("Off"),
                bead: Brand.lampUnlit, glowing: false, color: Brand.legendSecondary)
        }
        if state.cleaningLocked {
            self.lockRow?.set(
                state: localizedString("Locked"),
                bead: Brand.lampDead, glowing: false, color: Brand.stateDead)
        } else {
            self.lockRow?.set(
                state: localizedString("Off"),
                bead: Brand.lampUnlit, glowing: false, color: Brand.legendSecondary)
        }
        if state.keepAwakeActive {
            self.awakeRow?.set(
                state: localizedString("On"),
                bead: Brand.lampLit, glowing: true, color: Brand.legendPrimary)
        } else {
            self.awakeRow?.set(
                state: localizedString("Off"),
                bead: Brand.lampUnlit, glowing: false, color: Brand.legendSecondary)
        }
    }

    private func row(in container: NSStackView, key: String) -> LampStateView {
        let row = NSStackView()
        row.orientation = .horizontal

        let keyField = NSTextField(labelWithAttributedString:
            Brand.menuLabel(key, color: Brand.legendSecondary))

        let value = LampStateView()

        row.addArrangedSubview(keyField)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(value)
        container.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        return value
    }
}
