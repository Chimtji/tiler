import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys using the Carbon RegisterEventHotKey API.
/// Hotkey specs look like "ctrl+alt+1", "cmd+shift+f1", "ctrl+alt+left".
final class HotKeyManager {
    static let shared = HotKeyManager()

    static let layoutsGroup = "layouts"
    static let slotsGroup = "slots"

    private struct Registration {
        let ref: EventHotKeyRef
        let id: UInt32
        let group: String
    }

    private var registrations: [Registration] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x544C_5231 // 'TLR1'

    private init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                HotKeyManager.shared.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    /// Registers a hotkey. Returns false if the spec can't be parsed or the
    /// key is already taken by another app.
    @discardableResult
    func register(_ spec: String, group: String = "default", handler: @escaping () -> Void) -> Bool {
        guard let (keyCode, modifiers) = Self.parse(spec) else { return false }

        let hotKeyID = EventHotKeyID(signature: signature, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }

        registrations.append(Registration(ref: ref, id: nextID, group: group))
        handlers[nextID] = handler
        nextID += 1
        return true
    }

    func unregister(group: String) {
        for registration in registrations where registration.group == group {
            UnregisterEventHotKey(registration.ref)
            handlers.removeValue(forKey: registration.id)
        }
        registrations.removeAll { $0.group == group }
    }

    func unregisterAll() {
        registrations.forEach { UnregisterEventHotKey($0.ref) }
        registrations.removeAll()
        handlers.removeAll()
    }

    // MARK: - Parsing

    /// Parses "ctrl+alt+1" into (Carbon key code, Carbon modifier flags).
    static func parse(_ spec: String) -> (UInt32, UInt32)? {
        var modifiers: UInt32 = 0
        var key: String?

        for part in spec.lowercased().split(separator: "+").map(String.init) {
            switch part.trimmingCharacters(in: .whitespaces) {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "alt", "opt", "option": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case let k: key = k
            }
        }

        guard let key, let keyCode = keyCodes[key] else { return nil }
        return (keyCode, modifiers)
    }

    /// Formats "ctrl+alt+1" as "⌃⌥1" for display.
    static func pretty(_ spec: String) -> String {
        spec.lowercased()
            .replacingOccurrences(of: "command", with: "⌘")
            .replacingOccurrences(of: "cmd", with: "⌘")
            .replacingOccurrences(of: "control", with: "⌃")
            .replacingOccurrences(of: "ctrl", with: "⌃")
            .replacingOccurrences(of: "option", with: "⌥")
            .replacingOccurrences(of: "opt", with: "⌥")
            .replacingOccurrences(of: "alt", with: "⌥")
            .replacingOccurrences(of: "shift", with: "⇧")
            .replacingOccurrences(of: "+", with: "")
            .uppercased()
    }

    /// ANSI (US) virtual key codes.
    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
