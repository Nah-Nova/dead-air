import AppKit
import Carbon.HIToolbox

private func hotkeyEventHandler(
    _ callRef: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID)
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.dispatch(id: hotkeyID.id, kind: GetEventKind(event))
    return noErr
}

/// Global hotkeys via Carbon, which needs no Accessibility permission.
///
/// Note that while cleaning mode is active the event tap swallows keystrokes before
/// they reach hotkey dispatch, so hotkeys cannot unlock it. That is what the
/// command-key chord in InputLocker is for.
final class HotkeyManager {
    static let shared = HotkeyManager()

    enum Action: UInt32 {
        case toggleMic = 1
        case pushToTalk = 2
        case toggleCleaning = 3

        var defaultsKey: String {
            switch self {
            case .toggleMic: return "toggleMic"
            case .pushToTalk: return "pushToTalk"
            case .toggleCleaning: return "toggleCleaning"
            }
        }

        /// Carbon key code plus Carbon modifier mask.
        var fallback: (keyCode: UInt32, modifiers: UInt32) {
            switch self {
            case .toggleMic:
                return (46, UInt32(controlKey | optionKey | cmdKey))  // M
            case .pushToTalk:
                return (49, UInt32(controlKey | optionKey))  // Space
            case .toggleCleaning:
                return (40, UInt32(controlKey | optionKey | cmdKey))  // K
            }
        }

        var describedShortcut: String {
            switch self {
            case .toggleMic: return "⌃⌥⌘M"
            case .pushToTalk: return "⌃⌥Space"
            case .toggleCleaning: return "⌃⌥⌘K"
            }
        }
    }

    var onPress: ((Action) -> Void)?
    var onRelease: ((Action) -> Void)?

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private(set) var failedActions: [Action] = []

    private init() {}

    func start() {
        installHandler()
        for action in [Action.toggleMic, .pushToTalk, .toggleCleaning] {
            register(action)
        }
    }

    private func installHandler() {
        var specs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyEventHandler,
            specs.count,
            &specs,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler)
    }

    private func register(_ action: Action) {
        let defaults = UserDefaults.standard
        let keyCodeKey = Pref.hotkeyPrefix + action.defaultsKey + ".keyCode"
        let modifiersKey = Pref.hotkeyPrefix + action.defaultsKey + ".modifiers"

        let keyCode =
            defaults.object(forKey: keyCodeKey) as? Int ?? Int(action.fallback.keyCode)
        let modifiers =
            defaults.object(forKey: modifiersKey) as? Int ?? Int(action.fallback.modifiers)

        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: OSType(0x4445_4144), id: action.rawValue)  // 'DEAD'
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotkeyID, GetEventDispatcherTarget(), 0, &ref)

        if status == noErr, let ref {
            refs[action.rawValue] = ref
        } else {
            // Almost always another app already owns the combination.
            failedActions.append(action)
        }
    }

    fileprivate func dispatch(id: UInt32, kind: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        DispatchQueue.main.async { [weak self] in
            if kind == UInt32(kEventHotKeyPressed) {
                self?.onPress?(action)
            } else if kind == UInt32(kEventHotKeyReleased) {
                self?.onRelease?(action)
            }
        }
    }
}
