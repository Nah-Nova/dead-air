import Foundation

struct ActivationEvent: Codable {
    enum Kind: String, Codable {
        case camera
        case microphone

        var label: String {
            switch self {
            case .camera: return "Camera"
            case .microphone: return "Microphone"
            }
        }
    }

    let kind: Kind
    let active: Bool
    let date: Date
}

/// Timestamped history of camera and mic activations.
///
/// Deliberately records no app name: macOS does not expose which process is using
/// the camera or mic, so any name here would be a guess.
final class ActivationLog {
    static let shared = ActivationLog()
    static let didChange = Notification.Name("DeadAir.logDidChange")

    private(set) var events: [ActivationEvent] = []
    private let limit = 500

    private lazy var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm:ss"
        return formatter
    }()

    private init() {
        load()
    }

    func append(kind: ActivationEvent.Kind, active: Bool) {
        events.append(ActivationEvent(kind: kind, active: active, date: Date()))
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
        save()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func clear() {
        events = []
        save()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func describe(_ event: ActivationEvent) -> String {
        "\(formatter.string(from: event.date))  \(event.kind.label) \(event.active ? "on" : "off")"
    }

    func formattedAll() -> String {
        events.reversed().map(describe).joined(separator: "\n")
    }

    // MARK: - History

    /// The intervals a sensor was in use, reconstructed from the on and off transitions.
    ///
    /// The whole log is scanned before clipping, not just the window, so a session that
    /// began before the window still contributes the part that falls inside it. A trailing
    /// "on" with no matching "off" is treated as running until `now`, which is what it is.
    func sessions(
        kind: ActivationEvent.Kind, since: Date, now: Date = Date()
    ) -> [(start: Date, end: Date)] {
        var intervals: [(start: Date, end: Date)] = []
        var openedAt: Date?

        for event in events where event.kind == kind {
            if event.active {
                if openedAt == nil { openedAt = event.date }
            } else if let start = openedAt {
                intervals.append((start, event.date))
                openedAt = nil
            }
        }
        if let start = openedAt {
            intervals.append((start, now))
        }

        return intervals.compactMap { interval in
            let start = max(interval.start, since)
            let end = min(interval.end, now)
            return end > start ? (start, end) : nil
        }
    }

    func duration(kind: ActivationEvent.Kind, since: Date, now: Date = Date()) -> TimeInterval {
        sessions(kind: kind, since: since, now: now)
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// How much of each equal slice of the window the sensor was in use, 0 to 1 per slice.
    /// The strip in the popup draws exactly this, so a two second blip in a five minute
    /// bucket reads as a faint cell rather than a lit one.
    func occupancy(
        kind: ActivationEvent.Kind, since: Date, now: Date = Date(), buckets: Int
    ) -> [Double] {
        guard buckets > 0, now > since else { return [] }

        let span = now.timeIntervalSince(since) / Double(buckets)
        guard span > 0 else { return [] }

        var result = [Double](repeating: 0, count: buckets)
        for session in sessions(kind: kind, since: since, now: now) {
            let first = Int(session.start.timeIntervalSince(since) / span)
            let last = Int(session.end.timeIntervalSince(since) / span)
            for index in max(0, first)...min(buckets - 1, max(0, last)) {
                let bucketStart = since.addingTimeInterval(Double(index) * span)
                let bucketEnd = bucketStart.addingTimeInterval(span)
                let overlap = min(session.end, bucketEnd).timeIntervalSince(
                    max(session.start, bucketStart))
                if overlap > 0 {
                    result[index] = min(1, result[index] + (overlap / span))
                }
            }
        }
        return result
    }

    /// A duration as a readout: minutes until it needs hours, and never a bare zero.
    static func describe(duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        if total < 60 { return total <= 0 ? "None" : "\(total)s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Pref.activationLog),
            let decoded = try? JSONDecoder().decode([ActivationEvent].self, from: data)
        else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: Pref.activationLog)
    }
}
