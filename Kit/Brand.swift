//
//  Brand.swift
//  Kit
//
//  The Dead Air token layer, public so every target that links Kit draws from the same
//  palette. Mirrors Modules/DeadAir/Brand.swift and BRAND.md.
//

import AppKit

/// The token layer. Every colour and font the UI draws comes from here, so BRAND.md has
/// exactly one place to land in code and a designer reading both recognises the names.
///
/// Two things the published palette does not cover, filled in here:
/// the table is a dark-ground palette, so the light half of each state colour is derived
/// (see `stateDead` and `stateLive`), and Studio dark doubles as the type colour on the
/// light ground because nothing else in the palette can carry it.
public enum Brand {

    // MARK: - Palette

    /// The six hexes from the BRAND.md table, plus the two light-ground pairs derived for
    /// them. Composed into the semantic tokens below and never read from a call site, so
    /// no view has to know which theme it is in.
    fileprivate enum Palette {
        static let studioDark = brandHex(0x171C19)
        static let panelSage = brandHex(0xDDE0D8)
        static let legendCream = brandHex(0xE6E1D3)
        static let tallyAmber = brandHex(0xF5AE3A)
        static let oxide = brandHex(0xCE7A53)
        static let signalTeal = brandHex(0x63A38D)

        /// Oxide and Signal teal at 0.68 and 0.65 HSL lightness, hue and saturation kept.
        /// The least darkening that clears 4.5:1 on Panel sage and on white.
        static let oxideOnLight = brandHex(0x994E2C)
        static let signalTealOnLight = brandHex(0x3F6B5C)
    }

    // MARK: - Grounds

    /// The opaque inset plate a branded readout paints for itself. Small rounded inset,
    /// never a whole row.
    ///
    /// The state colours below were measured against this plate. Note what that does and
    /// does not buy: only the readout rows actually paint a plate. Legends, device names
    /// and caveats set their colour straight onto the menu's own translucent material,
    /// whose luminance moves with the desktop behind it and was never measured. Those
    /// rows are why `legendSecondary` and `legendTertiary` are pitched for the worst
    /// realistic material rather than for this plate.
    public static let groundPanel = brandDynamic(
        "groundPanel", light: Palette.panelSage, dark: Palette.studioDark)

    /// The cleaning overlay's cover. Identical in both themes on purpose, lights out is
    /// not a theme.
    public static let groundBlackout = brandDynamic(
        "groundBlackout", light: Palette.studioDark, dark: Palette.studioDark)

    // MARK: - Type colours

    /// Primary type, body or display, on `groundPanel` or `groundBlackout`.
    public static let legendPrimary = brandDynamic(
        "legendPrimary", light: Palette.studioDark, dark: Palette.legendCream)

    /// Secondary body and utility type: hints, device names, log lines.
    public static let legendSecondary = brandDynamic(
        "legendSecondary", light: brandHex(0x4E534E), dark: brandHex(0xACAA9F))

    /// The quietest row in the menu, for caveats about what macOS will not tell us.
    /// Never carries state.
    ///
    /// Both branches moved away from their first values: the light one cleared only 4.35:1
    /// on Panel sage, and the dark one was both under 4.5:1 on real menu material and
    /// byte-identical to `lampUnlit`, so a caveat row and a dead lamp were the same colour.
    public static let legendTertiary = brandDynamic(
        "legendTertiary", light: brandHex(0x555955), dark: brandHex(0x9A9C93))

    /// Separator rules and the rim of a plate. Decorative, never the only carrier of
    /// meaning.
    public static let hairline = brandDynamic(
        "hairline", light: brandHex(0xC5C8C1), dark: brandHex(0x30342F))

    // MARK: - States

    /// Oxide. The dead and muted state, and the accent voice generally. Tape, not danger,
    /// and it replaces every use of red.
    public static let stateDead = brandDynamic(
        "stateDead", light: Palette.oxideOnLight, dark: Palette.oxide)

    /// Signal teal. Live, passing, allowed, and nothing else in this app.
    public static let stateLive = brandDynamic(
        "stateLive", light: Palette.signalTealOnLight, dark: Palette.signalTeal)

    /// Type that sits on top of a state colour rather than on a ground. Both state colours
    /// are mid tones, so the ink has to be dark in either theme: cream on oxide measures
    /// about 2.2:1 and white about 2.6:1, while Studio dark clears 5.9:1.
    public static let inkOnState = brandDynamic(
        "inkOnState", light: Palette.studioDark, dark: Palette.studioDark)

    // MARK: - Lamps

    /// Every bead sits in this bezel, Studio dark in both themes, which is what lets the
    /// bead colours keep their published hexes and their measured contrast. A tally lamp
    /// lives in a housing anyway.
    /// Deliberately a step below Studio dark rather than equal to it. When the housing and
    /// the dark plate were both Studio dark the bay measured 1.00:1 against its own plate,
    /// so the app's central brand device vanished in the theme BRAND.md calls primary.
    public static let lampHousing = brandDynamic(
        "lampHousing", light: Palette.studioDark, dark: brandHex(0x0B0E0C))

    /// The housing's own edge, so the bezel still reads on a dark menu.
    public static let lampRim = brandDynamic(
        "lampRim", light: Palette.legendCream.withAlphaComponent(0.12),
        dark: Palette.legendCream.withAlphaComponent(0.12))

    /// Tally amber. Fill and glow only, it never sets type and never strokes type.
    public static let lampLit = brandDynamic(
        "lampLit", light: Palette.tallyAmber, dark: Palette.tallyAmber)

    /// The glow under a lit tally bead, as a shadow colour. Forbidden on the menu bar
    /// icon, where a template image discards colour and shadow both.
    public static let lampGlow = brandDynamic(
        "lampGlow", light: Palette.tallyAmber.withAlphaComponent(0.55),
        dark: Palette.tallyAmber.withAlphaComponent(0.55))

    /// A dull bead, meaning idle or off. Never the only channel, a mono state word always
    /// sits beside it.
    public static let lampUnlit = brandDynamic(
        "lampUnlit", light: brandHex(0x74756D), dark: brandHex(0x74756D))

    /// Oxide as a bead. Housing relative, so unlike `stateDead` it keeps the published hex
    /// in both themes.
    ///
    /// There is deliberately no teal bead. A lit tally is amber, full stop, and a teal one
    /// alongside meant the app had two colours for the single fact "signal is passing".
    /// Teal stays what BRAND.md reserves it for: the state word, never the hardware.
    public static let lampDead = brandDynamic("lampDead", light: Palette.oxide, dark: Palette.oxide)

    // MARK: - Type roles

    /// Three roles, no fourth.
    public enum Font {
        /// Display. Heavy condensed uppercase, panel silkscreen. Wordmark and section
        /// heads only, never a sentence. `NSFont(name:size:)` returns nil for an unknown
        /// PostScript name, so the fallback is real rather than a silent substitution.
        public static func display(size: CGFloat) -> NSFont {
            if let named = NSFont(name: "AvenirNextCondensed-Heavy", size: size) { return named }
            if #available(macOS 13.0, *) {
                return NSFont.systemFont(ofSize: size, weight: .heavy, width: .condensed)
            }
            return NSFont.systemFont(ofSize: size, weight: .heavy)
        }

        /// Body. Neutral system sans, for sentences. Never condensed, never uppercase.
        public static func body(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            NSFont.systemFont(ofSize: size, weight: weight)
        }

        /// Utility. Monospace for anything a machine prints: states, timers, levels, hex.
        /// This factory is the only route to SF Mono, its family name is private.
        public static func utility(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
            NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }

        /// Menu rows derive from the menu font rather than a fixed size, so a custom view
        /// lines up with the stock rows around it and follows the system text size.
        public static var menuBody: NSFont { NSFont.menuFont(ofSize: 0) }

        /// Mono a point down, so its x-height reads level with the body beside it.
        public static var menuUtility: NSFont { utility(size: menuBody.pointSize - 1) }

        public static var menuLegend: NSFont { display(size: menuBody.pointSize - 3) }
    }

    // MARK: - Menu text

    /// A silkscreen section head over a block of rows. Uppercased here because AppKit has
    /// no text transform, and tracked out so it reads as a legend rather than a title.
    public static func legend(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: Font.menuLegend,
                .foregroundColor: legendSecondary,
                .tracking: 0.8,
            ])
    }

    /// Body role menu text, with any substring a machine printed re-set in the utility
    /// face. Ranges come from the passed values, so a changed shortcut or countdown still
    /// styles the right run.
    public static func menuLabel(
        _ text: String, mono: [String] = [], color: NSColor? = nil, monoColor: NSColor? = nil
    ) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(
            string: text, attributes: [.font: Font.menuBody])
        if let color {
            attributed.addAttribute(
                .foregroundColor, value: color, range: NSRange(location: 0, length: attributed.length))
        }
        for value in mono where !value.isEmpty {
            guard let found = text.range(of: value) else { continue }
            var attributes: [NSAttributedString.Key: Any] = [.font: Font.menuUtility]
            if let monoColor { attributes[.foregroundColor] = monoColor }
            attributed.addAttributes(attributes, range: NSRange(found, in: text))
        }
        return attributed
    }

    /// A whole row a machine printed: a device name, a log line, an empty log.
    public static func readout(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text, attributes: [.font: Font.menuUtility, .foregroundColor: color])
    }

    /// A state word on its own, mono and tracked out in caps, for the rows that are a
    /// lamp and a word rather than a sentence.
    public static func stateWord(_ text: String, color: NSColor? = nil) -> NSMutableAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: Font.menuUtility, .tracking: 0.5]
        if let color { attributes[.foregroundColor] = color }
        return NSMutableAttributedString(string: text.uppercased(), attributes: attributes)
    }

    /// The hotkey label trailing a title. Carbon owns the binding, this is only notation,
    /// and it keeps a system colour because it sits on a row that highlights.
    public static func shortcutLabel(_ shortcut: String) -> NSAttributedString {
        NSAttributedString(
            string: shortcut,
            attributes: [
                .font: Font.menuUtility,
                .foregroundColor: NSColor.secondaryLabelColor,
                .tracking: 0.5,
            ])
    }

    // MARK: - Lamp drawing

    /// A bead in its housing, drawn into the current context. Bead colours are housing
    /// relative, which is why none of them varies by theme.
    public static func drawLamp(in rect: NSRect, bead: NSColor, glowing: Bool) {
        let radius = rect.width / 3
        let housing = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        lampHousing.setFill()
        housing.fill()

        let rim = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        rim.lineWidth = 1
        lampRim.setStroke()
        rim.stroke()

        let diameter = rect.width * 0.5
        let beadRect = NSRect(
            x: rect.midX - diameter / 2, y: rect.midY - diameter / 2,
            width: diameter, height: diameter)

        NSGraphicsContext.saveGraphicsState()
        if glowing {
            let shadow = NSShadow()
            shadow.shadowColor = lampGlow
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = .zero
            shadow.set()
        }
        bead.setFill()
        NSBezierPath(ovalIn: beadRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A lamp as a menu item image, which is how an interactive row gets an indicator
    /// without an `item.view`: highlight, checkmarks and keyboard navigation stay stock.
    public static func lampImage(bead: NSColor, glowing: Bool = false, side: CGFloat = 13) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            drawLamp(in: rect, bead: bead, glowing: glowing)
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Both branches resolve, and both `.darkAqua` and `.vibrantDark` count as dark. Matching
/// on `.darkAqua` alone would silently return the light value inside every menu, since
/// menus render vibrant.
private func brandDynamic(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: name) { appearance in
        let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        return match == .darkAqua || match == .vibrantDark ? dark : light
    }
}

private func brandHex(_ value: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1)
}

// MARK: - Bento surfaces

extension Brand {
    /// The quiet ground behind bento cards. Off-white with the palette's sage cast in
    /// light, a step under Studio dark in dark, so cards read as raised surfaces.
    public static let groundApp = brandDynamic(
        "groundApp", light: brandHex(0xF4F5F1), dark: brandHex(0x121513))

    /// The card surface itself.
    public static let surface = brandDynamic(
        "surface", light: brandHex(0xFFFFFF), dark: brandHex(0x1C211E))

    /// The card's hairline rim. Low alpha on purpose: the border separates, it never
    /// decorates.
    public static let surfaceBorder = brandDynamic(
        "surfaceBorder",
        light: brandHex(0x171C19).withAlphaComponent(0.08),
        dark: brandHex(0xE6E1D3).withAlphaComponent(0.08))

    /// A card or section head: the panel silkscreen, small and quiet. Display role,
    /// because BRAND.md reserves section heads for it, tracked out so it reads as a
    /// label rather than a word, and set in the quietest legend colour so the card's
    /// content stays the loudest thing in the frame.
    public static func cardTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: Font.display(size: 11),
                .foregroundColor: legendTertiary,
                .tracking: 0.9,
            ])
    }
}

/// A bento card: a rounded raised surface with a quiet small-caps title, an optional
/// trailing accessory control on the title row, and a vertical content stack. The one
/// container every popup section shares, so the popups read as one system.
public final class BentoCard: NSView {
    public let content: NSStackView = NSStackView()

    private static let radius: CGFloat = 10
    private static let inset: CGFloat = 10

    public init(title: String = "", accessory: NSView? = nil) {
        super.init(frame: .zero)

        let column = NSStackView()
        column.translatesAutoresizingMaskIntoConstraints = false
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6

        if !title.isEmpty {
            let header = NSStackView()
            header.orientation = .horizontal
            header.spacing = 4
            header.addArrangedSubview(NSTextField(labelWithAttributedString: Brand.cardTitle(title)))
            if let accessory {
                header.addArrangedSubview(NSView())
                header.addArrangedSubview(accessory)
            }
            column.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }

        self.content.orientation = .vertical
        self.content.alignment = .leading
        self.content.spacing = 5
        column.addArrangedSubview(self.content)
        self.content.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true

        self.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: self.topAnchor, constant: Self.inset),
            column.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: Self.inset),
            column.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -Self.inset),
            column.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -Self.inset)
        ])
    }

    required public init?(coder: NSCoder) {
        fatalError("BentoCard is built in code only")
    }

    public override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: self.bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.radius, yRadius: Self.radius)
        Brand.surface.setFill()
        path.fill()
        path.lineWidth = 1
        Brand.surfaceBorder.setStroke()
        path.stroke()
    }
}

// MARK: - Module marks

/// The module icon family, drawn as template images on the mark grid from BRAND.md:
/// one 64 unit grid, one 6 unit stroke, round caps, two units of padding, no gradient
/// and no glow. Every module gets a figure in the same hand, so ten icons read as one
/// set rather than ten borrowed system symbols.
///
/// Round caps put ink three units past each endpoint, so endpoints stay inside 5...59
/// and stroked rectangles are inset by at least eight.
extension Brand {
    private static let markGrid: CGFloat = 64
    private static let markStroke: CGFloat = 6

    public static func moduleMark(_ name: String, side: CGFloat = 18) -> NSImage? {
        guard markPaths(name) != nil else { return nil }

        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            drawMark(name, in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }

    /// Strokes a mark into `rect` in the current context, scaled from the 64 unit grid
    /// and centred on the square. Used by the menu bar widget, which draws its own ink
    /// colour rather than relying on template tinting.
    public static func drawMark(_ name: String, in rect: NSRect, color: NSColor) {
        guard let paths = markPaths(name), let context = NSGraphicsContext.current else { return }

        let side = min(rect.width, rect.height)
        context.saveGraphicsState()

        let transform = NSAffineTransform()
        transform.translateX(
            by: rect.minX + ((rect.width - side) / 2),
            yBy: rect.minY + ((rect.height - side) / 2))
        transform.concat()

        // The marks are drawn on a y down grid. An unflipped host view would mirror
        // them, which puts the display's foot on top and inverts the waveform, so the
        // y axis is pinned here rather than assumed.
        if !context.isFlipped {
            let flip = NSAffineTransform()
            flip.translateX(by: 0, yBy: side)
            flip.scaleX(by: 1, yBy: -1)
            flip.concat()
        }

        let scale = NSAffineTransform()
        scale.scale(by: side / markGrid)
        scale.concat()

        color.setStroke()
        for path in paths {
            path.lineWidth = markStroke
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        context.restoreGraphicsState()
    }

    private static func markPaths(_ name: String) -> [NSBezierPath]? {
        switch name {
        case "waveform":
            // The identity mark: signal passing. Same geometry as the menu bar live state.
            return [markLine([(5, 32), (14, 32), (19, 15), (24, 49), (29, 32), (59, 32)])]

        case "flatline":
            // Dead air. The flat line is the whole idea of the name.
            return [markLine([(5, 32), (59, 32)])]

        case "keycap":
            // Input locked, for cleaning mode.
            return [
                markRect(x: 8, y: 14, w: 48, h: 36, r: 7),
                markLine([(19, 32), (45, 32)])
            ]

        case "chip":
            // A processor: the package and its die. Square where the disk is round, so
            // the two centre marked figures stay apart at 16 points.
            return [
                markRect(x: 12, y: 12, w: 40, h: 40, r: 8),
                markDot(32, 32)
            ]

        case "display":
            // A screen on a foot, for the graphics module.
            return [
                markRect(x: 10, y: 14, w: 44, h: 30, r: 6),
                markLine([(24, 52), (40, 52)])
            ]

        case "stick":
            // A memory module: a wide body standing on two contacts.
            return [
                markRect(x: 9, y: 15, w: 46, h: 20, r: 5),
                markLine([(22, 38), (22, 50)]),
                markLine([(42, 38), (42, 50)])
            ]

        case "platter":
            // A disk: the plate and its spindle.
            return [
                markOval(x: 14, y: 14, w: 36, h: 36),
                markDot(32, 32)
            ]

        case "traffic":
            // Up and down, the only thing a network readout ever says.
            return [
                markLine([(21, 46), (21, 20)]),
                markLine([(14, 27), (21, 20), (28, 27)]),
                markLine([(43, 18), (43, 44)]),
                markLine([(36, 37), (43, 44), (50, 37)])
            ]

        case "cell":
            // A battery: body and terminal.
            return [
                markRect(x: 9, y: 22, w: 40, h: 20, r: 5),
                markLine([(54, 28), (54, 36)])
            ]

        case "probe":
            // A temperature probe: a short stem carrying a heavy bulb.
            return [
                markLine([(32, 11), (32, 32)]),
                markOval(x: 22, y: 32, w: 20, h: 20)
            ]

        case "link":
            // The pairing rune, drawn in the same stroke as everything else.
            return [
                markLine([(32, 9), (32, 55)]),
                markLine([(21, 21), (43, 41), (32, 52)]),
                markLine([(21, 43), (43, 23), (32, 12)])
            ]

        case "dial":
            // A clock face: two hands, no numerals, nothing survives numerals at 16 points.
            return [
                markOval(x: 14, y: 14, w: 36, h: 36),
                markLine([(32, 32), (32, 21)]),
                markLine([(32, 32), (41, 32)])
            ]

        default:
            return nil
        }
    }

    // MARK: Mark primitives

    private static func markLine(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let target = NSPoint(x: point.0, y: point.1)
            if index == 0 {
                path.move(to: target)
            } else {
                path.line(to: target)
            }
        }
        return path
    }

    private static func markRect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }

    private static func markOval(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h))
    }

    /// A zero length stroke with a round cap, which is the cleanest way to land a dot
    /// exactly one stroke wide on the same grid.
    private static func markDot(_ x: CGFloat, _ y: CGFloat) -> NSBezierPath {
        markLine([(x, y), (x, y)])
    }
}
