//
//  MarkWidget.swift
//  Kit
//
//  The Dead Air mark as a menu bar widget: one 64 unit grid, one stroke weight, and
//  only the interior line changes between states, so live, muted and locked read as
//  one object doing different things rather than three icons.
//

import Cocoa

public class MarkWidget: WidgetWrapper {
    public enum State: String {
        case live
        case muted
        case locked

        internal var mark: String {
            switch self {
            case .live: return "waveform"
            case .muted: return "flatline"
            case .locked: return "keycap"
            }
        }

        internal var label: String {
            switch self {
            case .live: return "microphone live"
            case .muted: return "microphone muted"
            case .locked: return "input locked"
            }
        }
    }

    private var state: State = .muted

    public init(title: String, config: NSDictionary, preview: Bool = false) {
        let side = Constants.Widget.height - (2 * Constants.Widget.margin.y)

        super.init(.mark, title: title, frame: CGRect(
            x: 0,
            y: Constants.Widget.margin.y,
            width: side + (2 * Constants.Widget.spacing),
            height: side
        ))

        if preview {
            self.state = .live
        }

        self.canDrawConcurrently = true
        self.setAccessibilityLabel("Dead Air")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Called by the module whenever the mic or the lock changes. Locked outranks
    /// muted, because a locked keyboard is the more consequential state to be in.
    public func setState(_ state: State) {
        var changed = false
        self.queue.sync {
            changed = state != self.state
            if changed { self.state = state }
        }
        guard changed else { return }
        self.setAccessibilityValue(state.label)
        DispatchQueue.main.async {
            self.display()
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // The ink is the brand's own, not a template tint: the widget is a subview of
        // the status item button, where template tinting never applies.
        // `canDrawConcurrently` is on, so the state is read through the same queue that
        // writes it, the way every other widget in Kit guards its value.
        let mark = self.queue.sync { self.state.mark }
        Brand.drawMark(mark, in: self.bounds, color: Brand.legendPrimary)
    }

    public override func settings() -> NSView {
        let view = SettingsContainerView()
        return view
    }
}
