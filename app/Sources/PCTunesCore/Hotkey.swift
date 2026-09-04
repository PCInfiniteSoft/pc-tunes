/// The three things a global hotkey can do. The raw values are the ids PC Tunes hands
/// Carbon when registering, so they must stay stable across releases: a changed id
/// would silently rebind whatever the user had saved.
public enum HotkeyAction: UInt32, CaseIterable, Sendable {
    case playPause = 1
    case next = 2
    case previous = 3

    public var title: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .next: return "Next"
        case .previous: return "Previous"
        }
    }

    public var defaultCombo: KeyCombo {
        switch self {
        case .playPause:
            return KeyCombo(keyCode: KeyCombo.space, modifiers: KeyCombo.control | KeyCombo.option)
        case .next:
            return KeyCombo(keyCode: KeyCombo.rightArrow, modifiers: KeyCombo.control | KeyCombo.option)
        case .previous:
            return KeyCombo(keyCode: KeyCombo.leftArrow, modifiers: KeyCombo.control | KeyCombo.option)
        }
    }
}

/// A key plus its modifiers, in the form Carbon's `RegisterEventHotKey` wants them:
/// a virtual key code and a mask of `controlKey`/`optionKey`/`shiftKey`/`cmdKey`.
///
/// The masks are spelled out here rather than imported from Carbon so this module stays
/// free of AppKit and Carbon and can be tested on its own. They are fixed constants of
/// the platform ABI, not something that can drift.
public struct KeyCombo: Equatable, Hashable, Sendable {
    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000

    public static let space: UInt32 = 49
    public static let leftArrow: UInt32 = 123
    public static let rightArrow: UInt32 = 124

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (Self.command | Self.shift | Self.option | Self.control)
    }

    /// Shift alone does not count. A global hotkey with no modifier — or with only
    /// shift — swallows an ordinary typing key everywhere in the system, which is never
    /// what someone means to configure.
    public var hasRequiredModifier: Bool {
        modifiers & (Self.control | Self.option | Self.command) != 0
    }

    /// Modifier symbols in the order macOS shows them in menus: ⌃⌥⇧⌘.
    public var modifierSymbols: String {
        var symbols = ""
        if modifiers & Self.control != 0 { symbols += "⌃" }
        if modifiers & Self.option != 0 { symbols += "⌥" }
        if modifiers & Self.shift != 0 { symbols += "⇧" }
        if modifiers & Self.command != 0 { symbols += "⌘" }
        return symbols
    }

    /// - Parameter keyLabel: what the key itself is called. Supplied by the caller
    ///   because naming a printable key means asking the current keyboard layout what
    ///   it produces, which this module deliberately cannot do.
    public func displayString(keyLabel: String) -> String {
        modifierSymbols + keyLabel
    }

    /// The name of a key that prints nothing, or `nil` for one that does.
    ///
    /// Only these are named here. A printable key's label depends on the keyboard
    /// layout — the key `kVK_ANSI_A` produces "a" on a US layout and "ฟ" on a Thai one —
    /// so it is resolved against the live layout instead of guessed from a table.
    public static func specialKeyName(for keyCode: UInt32) -> String? {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 76: return "⌤"
        case 48: return "⇥"
        case 51: return "⌫"
        case 117: return "⌦"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return nil
        }
    }

    // MARK: - Storage

    /// A property-list-safe form, for `UserDefaults`.
    public var stored: [String: Int] {
        ["keyCode": Int(keyCode), "modifiers": Int(modifiers)]
    }

    /// Rejects anything that is not a well-formed combo — including a stored value from
    /// a future version, or one hand-edited into the defaults — so a bad entry falls
    /// back to the default binding rather than registering something unusable.
    public init?(stored: Any?) {
        guard let dictionary = stored as? [String: Int],
              let keyCode = dictionary["keyCode"], keyCode >= 0, keyCode <= 0xFFFF,
              let modifiers = dictionary["modifiers"], modifiers >= 0
        else { return nil }
        let combo = KeyCombo(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        guard combo.hasRequiredModifier else { return nil }
        self = combo
    }
}
