import AppKit

/// The token layer. Every colour and font the UI draws comes from here, so BRAND.md has
/// exactly one place to land in code and a designer reading both recognises the names.
///
/// Two things the published palette does not cover, filled in here:
/// the table is a dark-ground palette, so the light half of each state colour is derived
/// (see `stateDead` and `stateLive`), and Studio dark doubles as the type colour on the
/// light ground because nothing else in the palette can carry it.
enum Brand {

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
    static let groundPanel = brandDynamic(
        "groundPanel", light: Palette.panelSage, dark: Palette.studioDark)

    /// The cleaning overlay's cover. Identical in both themes on purpose, lights out is
    /// not a theme.
    static let groundBlackout = brandDynamic(
        "groundBlackout", light: Palette.studioDark, dark: Palette.studioDark)

    // MARK: - Type colours

    /// Primary type, body or display, on `groundPanel` or `groundBlackout`.
    static let legendPrimary = brandDynamic(
        "legendPrimary", light: Palette.studioDark, dark: Palette.legendCream)

    /// Secondary body and utility type: hints, device names, log lines.
    static let legendSecondary = brandDynamic(
        "legendSecondary", light: brandHex(0x4E534E), dark: brandHex(0xACAA9F))

    /// The quietest row in the menu, for caveats about what macOS will not tell us.
    /// Never carries state.
    ///
    /// Both branches moved away from their first values: the light one cleared only 4.35:1
    /// on Panel sage, and the dark one was both under 4.5:1 on real menu material and
    /// byte-identical to `lampUnlit`, so a caveat row and a dead lamp were the same colour.
    static let legendTertiary = brandDynamic(
        "legendTertiary", light: brandHex(0x555955), dark: brandHex(0x9A9C93))

    /// Separator rules and the rim of a plate. Decorative, never the only carrier of
    /// meaning.
    static let hairline = brandDynamic(
        "hairline", light: brandHex(0xC5C8C1), dark: brandHex(0x30342F))

    // MARK: - States

    /// Oxide. The dead and muted state, and the accent voice generally. Tape, not danger,
    /// and it replaces every use of red.
    static let stateDead = brandDynamic(
        "stateDead", light: Palette.oxideOnLight, dark: Palette.oxide)

    /// Signal teal. Live, passing, allowed, and nothing else in this app.
    static let stateLive = brandDynamic(
        "stateLive", light: Palette.signalTealOnLight, dark: Palette.signalTeal)

    // MARK: - Lamps

    /// Every bead sits in this bezel, Studio dark in both themes, which is what lets the
    /// bead colours keep their published hexes and their measured contrast. A tally lamp
    /// lives in a housing anyway.
    /// Deliberately a step below Studio dark rather than equal to it. When the housing and
    /// the dark plate were both Studio dark the bay measured 1.00:1 against its own plate,
    /// so the app's central brand device vanished in the theme BRAND.md calls primary.
    static let lampHousing = brandDynamic(
        "lampHousing", light: Palette.studioDark, dark: brandHex(0x0B0E0C))

    /// The housing's own edge, so the bezel still reads on a dark menu.
    static let lampRim = brandDynamic(
        "lampRim", light: Palette.legendCream.withAlphaComponent(0.12),
        dark: Palette.legendCream.withAlphaComponent(0.12))

    /// Tally amber. Fill and glow only, it never sets type and never strokes type.
    static let lampLit = brandDynamic(
        "lampLit", light: Palette.tallyAmber, dark: Palette.tallyAmber)

    /// The glow under a lit tally bead, as a shadow colour. Forbidden on the menu bar
    /// icon, where a template image discards colour and shadow both.
    static let lampGlow = brandDynamic(
        "lampGlow", light: Palette.tallyAmber.withAlphaComponent(0.55),
        dark: Palette.tallyAmber.withAlphaComponent(0.55))

    /// A dull bead, meaning idle or off. Never the only channel, a mono state word always
    /// sits beside it.
    static let lampUnlit = brandDynamic(
        "lampUnlit", light: brandHex(0x74756D), dark: brandHex(0x74756D))

    /// Oxide as a bead. Housing relative, so unlike `stateDead` it keeps the published hex
    /// in both themes.
    ///
    /// There is deliberately no teal bead. A lit tally is amber, full stop, and a teal one
    /// alongside meant the app had two colours for the single fact "signal is passing".
    /// Teal stays what BRAND.md reserves it for: the state word, never the hardware.
    static let lampDead = brandDynamic("lampDead", light: Palette.oxide, dark: Palette.oxide)

    // MARK: - Type roles

    /// Three roles, no fourth.
    enum Font {
        /// Display. Heavy condensed uppercase, panel silkscreen. Wordmark and section
        /// heads only, never a sentence. `NSFont(name:size:)` returns nil for an unknown
        /// PostScript name, so the fallback is real rather than a silent substitution.
        static func display(size: CGFloat) -> NSFont {
            NSFont(name: "AvenirNextCondensed-Heavy", size: size)
                ?? NSFont.systemFont(ofSize: size, weight: .heavy, width: .condensed)
        }

        /// Body. Neutral system sans, for sentences. Never condensed, never uppercase.
        static func body(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            NSFont.systemFont(ofSize: size, weight: weight)
        }

        /// Utility. Monospace for anything a machine prints: states, timers, levels, hex.
        /// This factory is the only route to SF Mono, its family name is private.
        static func utility(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
            NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }

        /// Menu rows derive from the menu font rather than a fixed size, so a custom view
        /// lines up with the stock rows around it and follows the system text size.
        static var menuBody: NSFont { NSFont.menuFont(ofSize: 0) }

        /// Mono a point down, so its x-height reads level with the body beside it.
        static var menuUtility: NSFont { utility(size: menuBody.pointSize - 1) }

        static var menuLegend: NSFont { display(size: menuBody.pointSize - 3) }
    }

    // MARK: - Menu text

    /// A silkscreen section head over a block of rows. Uppercased here because AppKit has
    /// no text transform, and tracked out so it reads as a legend rather than a title.
    static func legend(_ text: String) -> NSAttributedString {
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
    static func menuLabel(
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
    static func readout(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text, attributes: [.font: Font.menuUtility, .foregroundColor: color])
    }

    /// A state word on its own, mono and tracked out in caps, for the rows that are a
    /// lamp and a word rather than a sentence.
    static func stateWord(_ text: String, color: NSColor? = nil) -> NSMutableAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: Font.menuUtility, .tracking: 0.5]
        if let color { attributes[.foregroundColor] = color }
        return NSMutableAttributedString(string: text.uppercased(), attributes: attributes)
    }

    /// The hotkey label trailing a title. Carbon owns the binding, this is only notation,
    /// and it keeps a system colour because it sits on a row that highlights.
    static func shortcutLabel(_ shortcut: String) -> NSAttributedString {
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
    static func drawLamp(in rect: NSRect, bead: NSColor, glowing: Bool) {
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
    static func lampImage(bead: NSColor, glowing: Bool = false, side: CGFloat = 13) -> NSImage {
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
