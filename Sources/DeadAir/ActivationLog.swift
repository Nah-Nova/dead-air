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
