import Carbon.HIToolbox
import Combine
import PCTunesCore

/// Registers PC Tunes' global hotkeys with Carbon's `RegisterEventHotKey`,
/// deliberately **not** `NSEvent.addGlobalMonitorForEvents`. The `NSEvent` route only
/// delivers global key events to apps granted Accessibility permission, which is a real
/// barrier at install time for a tool whose whole appeal is being small and asking for
/// nothing. `RegisterEventHotKey` needs no permission at all — it is what most menu bar
/// apps use for exactly this reason. Do not "modernise" this to `NSEvent`; that would
/// reintroduce the permission prompt this design deliberately avoids.
@MainActor
final class Hotkeys: ObservableObject {
    static let shared = Hotkeys()

    /// Actions whose combo the system refused, almost always because another app got
    /// there first. Published so the settings window can say which one is dead rather
    /// than leaving the user to discover it by pressing keys and getting nothing.
    @Published private(set) var unavailable: Set<HotkeyAction> = []

    /// Four-char signature identifying PC Tunes' hotkeys to Carbon, packed the way
    /// `OSType`/`FourCharCode` constants conventionally are.
    fileprivate static let signature: OSType = {
        "PCTn".utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private weak var model: PlayerModel?
    private var cancellable: AnyCancellable?

    private init() {}

    /// Starts watching the hotkey settings. `@Published`'s publisher hands a new
    /// subscriber the current value immediately, so this registers right away when
    /// hotkeys are already on, and again on every later change — one code path for
    /// "at launch", "toggled" and "rebound".
    func start(model: PlayerModel) {
        self.model = model
        cancellable = Settings.shared.$hotkeysEnabled
            .combineLatest(Settings.shared.$hotkeyCombos)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] enabled, combos in
                self?.apply(enabled: enabled, combos: combos)
            }
    }

    private func apply(enabled: Bool, combos: [HotkeyAction: KeyCombo]) {
        // Rebinding replaces the lot rather than diffing: three registrations cost
        // nothing, and a diff would have to reason about a combo moving between two
        // actions, where releasing the old one has to happen before claiming the new.
        unregisterAll()
        guard enabled else {
            unavailable = []
            return
        }
        installHandlerIfNeeded()

        var failed: Set<HotkeyAction> = []
        for action in HotkeyAction.allCases {
            let combo = combos[action] ?? action.defaultCombo
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(
                combo.keyCode,
                combo.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            // One combo already belonging to another app is no reason to drop the other
            // two — the user rebinds the one that clashed and keeps the rest working.
            guard status == noErr, let hotKeyRef else {
                NSLog("[PC Tunes] failed to register hotkey for \(action.title): OSStatus \(status)")
                failed.insert(action)
                continue
            }
            hotKeyRefs[action] = hotKeyRef
        }
        unavailable = failed
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
                      let action = HotkeyAction(rawValue: hotKeyID.id)
                else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon calls this handler on the main thread, but it is a plain C
                // callback with no actor isolation the compiler can see — hop
                // explicitly before touching anything MainActor-isolated.
                Task { @MainActor in
                    Hotkeys.shared.handle(action)
                }
                return noErr
            },
            1, &eventType, nil, &eventHandlerRef
        )
    }

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .playPause: model?.playPause()
        case .next: model?.next()
        case .previous: model?.previous()
        }
    }
}
