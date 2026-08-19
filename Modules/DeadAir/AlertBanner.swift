import AppKit
import Kit

/// A floating banner near the top of the screen.
///
/// Chosen over a real notification so the app needs no notification permission
/// and the warning cannot be silenced by a Focus mode.
final class AlertBanner {
    static let shared = AlertBanner()

    /// Wide enough that the camera subtitle sets on one line. It was truncating.
    static let size = NSSize(width: 376, height: 74)

    private var window: NSWindow?
    private var dismissTimer: Timer?

    private init() {}

    /// `accent` is the lamp bead, never the type colour. Tally amber by default, because
    /// the banner only fires when a sensor came on and a lit tally is what a studio shows
    /// for that. Oxide is the other legal bead, for a state that went dead.
    ///
    /// `glowing` is passed rather than inferred from the colour. It used to be derived by
    /// comparing the bead against the amber token, and `NSColor(name:dynamicProvider:)` has
    /// no documented equality contract, so an equal but separately built colour would have
    /// silently lost its halo.
    func show(
        title: String, subtitle: String, accent: NSColor = Brand.lampLit, glowing: Bool = true
    ) {
        dismiss()

        guard let screen = NSScreen.main else { return }

        let frame = NSRect(
            x: screen.frame.midX - Self.size.width / 2,
            y: screen.visibleFrame.maxY - Self.size.height - 12,
            width: Self.size.width,
            height: Self.size.height)

        let window = NSWindow(
            contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        window.contentView = Self.content(
            title: title, subtitle: subtitle, accent: accent, glowing: glowing)
        window.orderFrontRegardless()
        self.window = window

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        window = nil
    }

    /// The banner's content view. Shared by `show` and the UI dump, so the render that gets
    /// judged is the one that ships rather than a lookalike.
    static func content(
        title: String, subtitle: String, accent: NSColor = Brand.lampLit, glowing: Bool = true
    ) -> NSView {
        let panel = Panel(frame: NSRect(origin: .zero, size: size), bead: accent, glowing: glowing)

        let textX = Panel.textInset
        let textWidth = size.width - textX - Panel.inset

        let titleLabel = label(
            title, font: Brand.Font.body(size: 13, weight: .semibold), color: Brand.legendPrimary)
        titleLabel.frame = NSRect(x: textX, y: size.height / 2 + 1, width: textWidth, height: 18)
        panel.addSubview(titleLabel)

        let subtitleLabel = label(
            subtitle, font: Brand.Font.body(size: 11), color: Brand.legendSecondary)
        subtitleLabel.frame = NSRect(
            x: textX, y: size.height / 2 - 19, width: textWidth, height: 16)
        panel.addSubview(subtitleLabel)

        return panel
    }

    private static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    /// The panel the banner is: painted ground, amber rim, a tally lamp in its own bay at
    /// the left. Ground, rim and lamp are drawn instead of set as layer properties, since a
    /// `CGColor` resolves once and would keep the light theme's paint in a dark bar.
    private final class Panel: NSView {
        static let inset: CGFloat = 14
        static let textInset: CGFloat = 48
        private static let housingSide: CGFloat = 22
        private static let cornerRadius: CGFloat = 14

        private let bead: NSColor
        private let glowing: Bool

        init(frame: NSRect, bead: NSColor, glowing: Bool) {
            self.bead = bead
            self.glowing = glowing
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            fatalError("AlertBanner.Panel is built in code only")
        }

        /// A click anywhere on the banner dismisses it, so acknowledging a reminder
        /// costs one click and no aim.
        override func mouseDown(with event: NSEvent) {
            AlertBanner.shared.dismiss()
        }

        override func draw(_ dirtyRect: NSRect) {
            let radius = Self.cornerRadius
            Brand.groundPanel.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

            // The rim takes the lamp's own colour. It used to be amber unconditionally, which
            // made the largest amber shape in the app a border rather than a lamp, and framed
            // an oxide banner in lit amber: the frame claiming on air while the lamp said dead.
            let rim = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            rim.lineWidth = 1
            bead.withAlphaComponent(0.55).setStroke()
            rim.stroke()

            let housing = NSRect(
                x: Self.inset, y: (bounds.height - Self.housingSide) / 2,
                width: Self.housingSide, height: Self.housingSide)
            Brand.drawLamp(in: housing, bead: bead, glowing: glowing)
        }
    }
}
