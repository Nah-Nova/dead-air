import AppKit

/// Full-screen cover shown while input is locked, dressed as a piece of gear that has been
/// taken off air: a dead tally lamp, a silkscreen legend, a mono countdown.
///
/// The ground stays Studio dark on purpose: it makes smudges on the display visible while
/// you wipe, and leaves no doubt that input is locked. Nothing here paints a light panel,
/// that would defeat the point.
final class CleaningOverlay: NSObject {
    private var windows: [NSWindow] = []
    private var statusLabel: NSTextField?
    private var onUnlock: (() -> Void)?

    func show(trackpadLocked: Bool, onUnlock: @escaping () -> Void) {
        hide()
        self.onUnlock = onUnlock

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
            window.backgroundColor = Brand.groundBlackout
            window.isOpaque = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            // Lights out is not a theme: the ground is Studio dark in both, so the type on
            // it has to resolve dark too. Without this every brand colour picks its light
            // branch in a light system and legend cream lands as Studio dark on Studio dark.
            window.appearance = NSAppearance(named: .darkAqua)

            let content = BlackoutView(frame: NSRect(origin: .zero, size: screen.frame.size))
            content.wantsLayer = true
            window.contentView = content

            if screen == NSScreen.main {
                addContent(to: content, trackpadLocked: trackpadLocked)
            }

            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func update(status: String) {
        statusLabel?.stringValue = status
    }

    func hide() {
        for window in windows { window.orderOut(nil) }
        windows = []
        statusLabel = nil
        onUnlock = nil
    }

    /// Builds the overlay content offscreen so the look can be judged without locking the
    /// machine. Deliberately the same code path as `show`, otherwise the render would be a
    /// second implementation and prove nothing about what ships.
    func renderableContent(size: NSSize, trackpadLocked: Bool, status: String) -> NSView {
        let content = BlackoutView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        addContent(to: content, trackpadLocked: trackpadLocked)
        update(status: status)
        return content
    }

    private func addContent(to content: BlackoutView, trackpadLocked: Bool) {
        let width = content.bounds.width
        let centerY = content.bounds.height / 2

        let tally = TallyIndicator(state: "Off air")
        tally.setFrameOrigin(
            NSPoint(x: ((width - tally.frame.width) / 2).rounded(), y: centerY + 96))
        content.addSubview(tally)

        let title = Self.label(Self.displayLegend("Input locked", size: 40, tracking: 1))
        place(title, in: content, width: width, y: centerY + 30)

        // The rule sits under the legend and takes its width from it, the way a panel
        // silkscreen is scored to the type it labels.
        let ruleWidth = ceil(title.intrinsicContentSize.width)
        content.ruleRect = NSRect(
            x: ((width - ruleWidth) / 2).rounded(), y: centerY + 16, width: ruleWidth, height: 1)

        let status = Self.readout()
        status.frame = NSRect(x: 0, y: centerY - 20, width: width, height: 22)
        content.addSubview(status)
        statusLabel = status

        let hintText =
            trackpadLocked
            ? "Hold both ⌘ keys for 3 seconds to unlock"
            : "Hold both ⌘ keys for 3 seconds, or click Unlock"
        let hint = Self.label(Self.hint(hintText))
        place(hint, in: content, width: width, y: centerY - 52)

        // Pointless when the trackpad is locked, since the tap eats the click too.
        if !trackpadLocked {
            let button = UnlockButton(
                title: "Unlock", target: self, action: #selector(unlockTapped))
            button.frame = NSRect(
                x: (width / 2 - 75).rounded(), y: centerY - 112, width: 150, height: 36)
            content.addSubview(button)
        }
    }

    @objc private func unlockTapped() {
        onUnlock?()
    }

    private func place(_ field: NSTextField, in content: NSView, width: CGFloat, y: CGFloat) {
        field.frame = NSRect(
            x: 0, y: y, width: width, height: ceil(field.intrinsicContentSize.height))
        content.addSubview(field)
    }

    // MARK: - Type

    private static func label(_ attributed: NSAttributedString) -> NSTextField {
        let field = NSTextField(labelWithAttributedString: attributed)
        field.alignment = .center
        field.drawsBackground = false
        return field
    }

    /// The one display run on the screen. Uppercased here because AppKit has no text
    /// transform, and it is a panel legend, never a sentence.
    private static func displayLegend(_ text: String, size: CGFloat, tracking: CGFloat)
        -> NSAttributedString
    {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: Brand.Font.display(size: size),
                .foregroundColor: Brand.legendPrimary,
                .tracking: tracking,
                .paragraphStyle: centred,
            ])
    }

    /// Alignment has to travel inside the attributed string. Setting `alignment` on a field
    /// built with `labelWithAttributedString` loses to the string's own paragraph style, which
    /// is how the legend ended up flush left while everything around it was centred.
    private static var centred: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    /// Stays a plain field, never an attributed one, so `update(status:)` can keep writing
    /// `stringValue` without losing the styling. Mono holds the digits on a fixed advance,
    /// so the countdown does not shuffle the line as it ticks.
    private static func readout() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = Brand.Font.utility(size: 15)
        field.textColor = Brand.legendPrimary
        field.alignment = .center
        field.drawsBackground = false
        return field
    }

    /// A sentence, so body role, with the key glyphs re-set in the utility face because
    /// they are notation rather than words.
    private static func hint(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Brand.Font.body(size: 13),
                .foregroundColor: Brand.legendSecondary,
                .paragraphStyle: centred,
            ])
        var rest = text.startIndex..<text.endIndex
        while let found = text.range(of: "⌘", range: rest) {
            attributed.addAttribute(
                .font, value: Brand.Font.utility(size: 13), range: NSRange(found, in: text))
            rest = found.upperBound..<text.endIndex
        }
        return attributed
    }
}

/// The blackout ground, plus the single hairline scored across it. Drawn rather than set as
/// a layer colour so both resolve against the window's own appearance.
private final class BlackoutView: NSView {
    var ruleRect: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        Brand.groundBlackout.setFill()
        bounds.fill()

        guard ruleRect.width > 0 else { return }
        // Not `hairline`: that token is pitched for a plate rim and measures 1.36:1 on
        // the blackout ground, so the one piece of scored detail on this screen was
        // invisible. The overlay pins darkAqua, so this value is fixed by design.
        Brand.legendPrimary.withAlphaComponent(0.2).setFill()
        ruleRect.fill()
    }
}

/// The dead state as hardware: an oxide bead in its housing with the mono state word beside
/// it. No plate behind it, the ground has to stay essentially black.
private final class TallyIndicator: NSView {
    private let stateText: String

    private static let housingSide: CGFloat = 24
    private static let gap: CGFloat = 12

    init(state: String) {
        stateText = state
        super.init(frame: .zero)

        frame = NSRect(
            x: 0, y: 0,
            width: Self.housingSide + Self.gap + ceil(word.size().width),
            height: Self.housingSide)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(state)
    }

    required init?(coder: NSCoder) {
        fatalError("TallyIndicator is built in code only")
    }

    private var word: NSAttributedString {
        NSAttributedString(
            string: stateText.uppercased(),
            attributes: [
                .font: Brand.Font.utility(size: 13, weight: .semibold),
                .foregroundColor: Brand.stateDead,
                .tracking: 2,
            ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let housing = NSRect(
            x: 0, y: (bounds.height - Self.housingSide) / 2,
            width: Self.housingSide, height: Self.housingSide)
        Brand.drawLamp(in: housing, bead: Brand.lampDead, glowing: false)

        let word = self.word
        let size = word.size()
        word.draw(at: NSPoint(x: housing.maxX + Self.gap, y: bounds.midY - size.height / 2))
    }
}

/// The unlock control as panel hardware: an oxide rim and a mono legend on the blackout
/// ground. Custom drawn rather than bezeled, because a stock rounded button is the one
/// thing that would give away that this is not a piece of gear. Target, action and mouse
/// tracking stay stock `NSButton`, only the drawing is ours.
private final class UnlockButton: NSButton {
    private var hovering = false

    private static let tracking: CGFloat = 1.6

    init(title: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        fatalError("UnlockButton is built in code only")
    }

    override var allowsVibrancy: Bool { false }

    private var legend: NSAttributedString {
        NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: Brand.Font.body(size: 12, weight: .semibold),
                .foregroundColor: Brand.stateDead,
                .tracking: Self.tracking,
            ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)

        // Oxide at a low alpha rather than a lighter fill, so pressing it never turns the
        // control into a light panel.
        let fillAlpha: CGFloat = isHighlighted ? 0.22 : (hovering ? 0.12 : 0)
        if fillAlpha > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(fillAlpha)
            Brand.stateDead.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        path.lineWidth = 1
        Brand.stateDead.setStroke()
        path.stroke()

        let legend = self.legend
        let size = legend.size()
        legend.draw(
            at: NSPoint(
                x: (bounds.width - size.width + Self.tracking) / 2,
                y: (bounds.height - size.height) / 2))
    }
}
