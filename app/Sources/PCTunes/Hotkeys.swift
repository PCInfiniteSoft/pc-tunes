import Carbon.HIToolbox
import Combine
import PCTunesCore

/// Registers PC Tunes' three global hotkeys with Carbon's `RegisterEventHotKey`,
/// deliberately **not** `NSEvent.addGlobalMonitorForEvents`. The `NSEvent` route only
/// delivers global key events to apps granted Accessibility permission, which is a real
/// barrier at install time for a tool whose whole appeal is being small and asking for
/// nothing. `RegisterEventHotKey` needs no permission at all — it is what most menu bar
/// apps use for exactly this reason. Do not "modernise" this to `NSEvent`; that would
/// reintroduce the permission prompt this design deliberately avoids.
@MainActor
final class Hotkeys {
    static let shared = Hotkeys()

    enum Binding: UInt32, CaseIterable {
        case playPause = 1
        case next = 2
        case previous = 3

        fileprivate var keyCode: UInt32 {
            switch self {
            case .playPause: return UInt32(kVK_Space)
            case .next: return UInt32(kVK_RightArrow)
            case .previous: return UInt32(kVK_LeftArrow)
            }
        }

        fileprivate var label: String {
            switch self {
            case .playPause: return "play/pause (⌃⌥Space)"
            case .next: return "next (⌃⌥→)"
            case .previous: return "previous (⌃⌥←)"
            }
        }
    }

    /// Four-char signature identifying PC Tunes' hotkeys to Carbon, packed the way
    /// `OSType`/`FourCharCode` constants conventionally are.
    fileprivate static let signature: OSType = {
        "PCTn".utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    private var hotKeyRefs: [Binding: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private weak var model: PlayerModel?
    private var cancellable: AnyCancellable?

    private init() {}

    /// Starts watching `Settings.shared.hotkeysEnabled`. `@Published`'s publisher hands
    /// a new subscriber the current value immediately, so this registers right away
    /// when hotkeys are already on, and again on every later flip — one code path for
    /// both "at launch" and "toggled".
    func start(model: PlayerModel) {
        self.model = model
        cancellable = Settings.shared.$hotkeysEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled {
                    self?.register()
                } else {
                    self?.unregisterAll()
                }
            }
    }

    private func register() {
        guard hotKeyRefs.isEmpty else { return }
        installHandlerIfNeeded()

        for binding in Binding.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: binding.rawValue)
            let status = RegisterEventHotKey(
                binding.keyCode,
                UInt32(controlKey | optionKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            guard status == noErr, let hotKeyRef else {
                NSLog("[PC Tunes] failed to register hotkey \(binding.label): OSStatus \(status)")
                // Another app already owns one of the combinations. Leaving the rest
                // registered with the setting still on would be half-wired and silently
                // dead for the one that failed, so undo everything and reflect the
                // setting back off instead.
                unregisterAll()
                Task { @MainActor in Settings.shared.hotkeysEnabled = false }
                return
            }
            hotKeyRefs[binding] = hotKeyRef
        }
    }

    private func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == Hotkeys.signature,
                      let binding = Hotkeys.Binding(rawValue: hotKeyID.id)
                else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon calls this handler on the main thread, but it is a plain C
                // callback with no actor isolation the compiler can see — hop
                // explicitly before touching anything MainActor-isolated.
                Task { @MainActor in
                    Hotkeys.shared.handle(binding)
                }
                return noErr
            },
            1, &eventType, nil, &eventHandlerRef
        )
    }

    private func handle(_ binding: Binding) {
        switch binding {
        case .playPause: model?.playPause()
        case .next: model?.next()
        case .previous: model?.previous()
        }
    }
}
