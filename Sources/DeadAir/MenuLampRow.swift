import AppKit

/// One sensor readout as a piece of panel hardware: a legend, then a tally lamp and its
/// state word on a painted plate.
///
/// A custom view is only safe on a disabled row, which is the one thing every call site
/// must keep true. There is no checkmark to lose, no highlight to redraw and no keyboard
/// focus to preserve. Everything is drawn in `draw(_:)` with no subviews, so nothing can
/// clip the lamp's glow and the whole row renders straight into a bitmap for the UI dump.
final class MenuLampRow: NSView {
    private let labelText: String
    private let stateText: String
    private let lit: Bool

    private static let leftInset: CGFloat = 20
    private static let rightInset: CGFloat = 12
    private static let gap: CGFloat = 10
    private static let platePadding: CGFloat = 5
    private static let beadGap: CGFloat = 6
    private static let housingSide: CGFloat = 12

    init(label: String, state: String, lit: Bool) {
        labelText = label
        stateText = state
        self.lit = lit
        super.init(frame: .zero)

        let height = max(20, Brand.Font.menuBody.pointSize + 9)
        frame = NSRect(x: 0, y: 0, width: intrinsicWidth, height: height)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(label): \(state)")
    }

    required init?(coder: NSCoder) {
        fatalError("MenuLampRow is built in code only")
    }

    /// Menus size to their widest item, so this stays as tight as the text allows.
    private var intrinsicWidth: CGFloat {
        Self.leftInset + ceil(legend.size().width) + Self.gap + plateWidth + Self.rightInset
    }

    private var plateWidth: CGFloat {
        Self.platePadding * 2 + Self.housingSide + Self.beadGap + ceil(state.size().width)
    }

    private var legend: NSAttributedString {
        Brand.menuLabel(labelText, color: Brand.legendSecondary)
    }

    /// Teal only when something really is capturing. The lamp beside it is the tally.
    private var state: NSAttributedString {
        Brand.stateWord(stateText, color: lit ? Brand.stateLive : Brand.legendSecondary)
    }

    override func draw(_ dirtyRect: NSRect) {
        let legend = self.legend
        let state = self.state
        let legendSize = legend.size()
        legend.draw(at: NSPoint(x: Self.leftInset, y: (bounds.height - legendSize.height) / 2))

        let plateHeight = Self.housingSide + Self.platePadding * 2
        let plate = NSRect(
            x: Self.leftInset + ceil(legendSize.width) + Self.gap,
            y: (bounds.height - plateHeight) / 2,
            width: plateWidth,
            height: plateHeight)

        Brand.groundPanel.setFill()
        NSBezierPath(roundedRect: plate, xRadius: 4, yRadius: 4).fill()
        let rim = NSBezierPath(
            roundedRect: plate.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        rim.lineWidth = 1
        Brand.hairline.setStroke()
        rim.stroke()

        let housing = NSRect(
            x: plate.minX + Self.platePadding, y: plate.minY + Self.platePadding,
            width: Self.housingSide, height: Self.housingSide)
        Brand.drawLamp(in: housing, bead: lit ? Brand.lampLit : Brand.lampUnlit, glowing: lit)

        let stateSize = state.size()
        state.draw(
            at: NSPoint(x: housing.maxX + Self.beadGap, y: plate.midY - stateSize.height / 2))
    }
}
