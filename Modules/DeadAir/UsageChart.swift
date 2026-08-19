//
//  UsageChart.swift
//  DeadAir
//
//  The two readouts the Dead Air panel can honestly draw. Neither invents data: the
//  strip is reconstructed from the activation log's own transitions, and the meter is
//  the remaining fraction of a countdown that is already running.
//
//  There is deliberately no input level meter. Metering a microphone means opening it,
//  which needs microphone permission and lights the orange indicator, so an app whose
//  whole point is that it needs no permission to watch the mic cannot have one.
//

import AppKit
import Kit

/// A row of cells, one per slice of the window, filled in proportion to how much of that
/// slice the sensor was in use. Teal because it means the signal was passing, which is the
/// one thing teal is allowed to mean.
internal final class UsageStrip: NSView {
    private var values: [Double] = []

    private static let cellGap: CGFloat = 1.5
    private static let radius: CGFloat = 1

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 14)
    }

    func set(_ values: [Double]) {
        self.values = values
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }

        let count = CGFloat(values.count)
        let cell = (bounds.width - (Self.cellGap * (count - 1))) / count
        guard cell > 0 else { return }

        for (index, value) in values.enumerated() {
            let rect = NSRect(
                x: CGFloat(index) * (cell + Self.cellGap),
                y: 0,
                width: cell,
                height: bounds.height)
            let path = NSBezierPath(roundedRect: rect, xRadius: Self.radius, yRadius: Self.radius)

            // An empty slice still draws its track, so the strip reads as a timeline
            // rather than as a scatter of marks. `hairline` and not `surfaceBorder`: the
            // latter is pitched at 0.08 for a card rim and vanished on a light ground,
            // which turned the timeline back into floating marks. Held back to just under
            // half, because at full strength the empty track competed with the fill.
            Brand.hairline.withAlphaComponent(0.45).setFill()
            path.fill()

            guard value > 0 else { continue }
            // Alpha carries how much of the slice was busy. A floor keeps a two second
            // blip visible instead of rounding it away to nothing.
            Brand.stateLive.withAlphaComponent(max(0.35, min(1, value))).setFill()
            path.fill()
        }
    }
}

/// A countdown as a bar: the fraction of a keep awake session still to run. Empty when
/// nothing is running, and never shown for a session with no end time, because there is
/// no fraction to draw.
internal final class MeterBar: NSView {
    private var fraction: Double = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 4)
    }

    func set(fraction: Double) {
        let clamped = max(0, min(1, fraction))
        guard clamped != self.fraction else { return }
        self.fraction = clamped
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        Brand.hairline.setFill()
        track.fill()

        guard fraction > 0 else { return }
        let width = max(bounds.height, bounds.width * CGFloat(fraction))
        let fill = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height),
            xRadius: radius, yRadius: radius)
        // Oxide once the session is nearly out, so the bar says "about to end" without
        // borrowing the lamp colour for a fill that sits next to type.
        (fraction <= 0.1 ? Brand.stateDead : Brand.stateLive).setFill()
        fill.fill()
    }
}
