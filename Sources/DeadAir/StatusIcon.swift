import AppKit

/// The menu bar mark, drawn as a template image so macOS tints it for light and
/// dark bars. Geometry comes straight from BRAND.md: one 64 unit grid, round caps,
/// and only the interior line changes between states, so the swap never shifts.
///
/// Stroke is 6 units rather than 5. At an 18 pt render that lands on 1.69 pt, which
/// clears the 1.5 px minimum a 1x menu bar needs; 5 units would fall under it.
enum StatusIcon {
    enum State {
        case live
        case muted
        case locked
    }

    private static let grid: CGFloat = 64
    private static let side: CGFloat = 18
    private static let stroke: CGFloat = 6

    static func image(for state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            context.saveGraphicsState()

            let transform = NSAffineTransform()
            transform.scale(by: side / grid)
            transform.concat()

            NSColor.black.setStroke()
            for path in paths(for: state) {
                path.lineWidth = stroke
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }

            context.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(for: state)
        return image
    }

    private static func paths(for state: State) -> [NSBezierPath] {
        switch state {
        case .live:
            // Inset to 5..59, not 4..60. With a 6 unit stroke and round caps the ink reaches
            // 3 units past each end, so 4 left only 1 unit of margin where BRAND.md asks
            // for 2.
            return [polyline([(5, 32), (14, 32), (19, 15), (24, 49), (29, 32), (59, 32)])]
        case .muted:
            return [polyline([(5, 32), (59, 32)])]
        case .locked:
            let keycap = NSBezierPath(
                roundedRect: NSRect(x: 8, y: 14, width: 48, height: 36),
                xRadius: 7,
                yRadius: 7)
            return [keycap, polyline([(19, 32), (45, 32)])]
        }
    }

    private static func polyline(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
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

    private static func description(for state: State) -> String {
        switch state {
        case .live: return "Dead Air, microphone live"
        case .muted: return "Dead Air, microphone muted"
        case .locked: return "Dead Air, input locked"
        }
    }
}
