import Foundation
import PCTunesCore

/// Persisted user preferences, backed by `UserDefaults.standard`. A single shared
/// instance so the menu bar scene, the settings window and the hotkey registrar all
/// observe the same values.
///
/// `showNotifications` and `hotkeysEnabled` default to off deliberately: a widget that
/// starts nagging with notifications or grabbing global keyboard shortcuts on first
/// launch is one people uninstall.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let menuBarTitleLength = "menuBarTitleLength"
        static let showNotifications = "showNotifications"
        static let hotkeysEnabled = "hotkeysEnabled"
        static let hotkeyCombos = "hotkeyCombos"
    }

    private let defaults: UserDefaults

    /// Characters kept in the menu bar title. Always within `MenuBarTitle.lengthRange`,
    /// on both read and write.
    @Published var menuBarTitleLength: Int {
        didSet {
            let clamped = MenuBarTitle.clampLength(menuBarTitleLength)
            guard clamped == menuBarTitleLength else {
                // Re-assigning triggers this observer again; the second pass is
                // already clamped and falls through to the write below.
                menuBarTitleLength = clamped
                return
            }
            defaults.set(clamped, forKey: Key.menuBarTitleLength)
        }
    }

    @Published var showNotifications: Bool {
        didSet { defaults.set(showNotifications, forKey: Key.showNotifications) }
    }

    @Published var hotkeysEnabled: Bool {
        didSet { defaults.set(hotkeysEnabled, forKey: Key.hotkeysEnabled) }
    }

    /// One combo per action, always complete: a missing or unreadable entry reads back
    /// as that action's default, so nothing downstream has to handle an unbound action.
    @Published var hotkeyCombos: [HotkeyAction: KeyCombo] {
        didSet {
            var stored: [String: [String: Int]] = [:]
            for (action, combo) in hotkeyCombos {
                stored[String(action.rawValue)] = combo.stored
            }
            defaults.set(stored, forKey: Key.hotkeyCombos)
        }
    }

    func resetHotkeyCombos() {
        hotkeyCombos = Self.defaultCombos
    }

    private static var defaultCombos: [HotkeyAction: KeyCombo] {
        Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, $0.defaultCombo) })
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // UserDefaults.integer(forKey:) returns 0 for a key that was never set, which
        // looks like a real (if extreme) value, so presence is checked before reading.
        if defaults.object(forKey: Key.menuBarTitleLength) != nil {
            menuBarTitleLength = MenuBarTitle.clampLength(defaults.integer(forKey: Key.menuBarTitleLength))
        } else {
            menuBarTitleLength = MenuBarTitle.maxLength
        }
        showNotifications = defaults.bool(forKey: Key.showNotifications)
        hotkeysEnabled = defaults.bool(forKey: Key.hotkeysEnabled)

        let stored = defaults.dictionary(forKey: Key.hotkeyCombos)
        hotkeyCombos = Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { action in
            (action, KeyCombo(stored: stored?[String(action.rawValue)]) ?? action.defaultCombo)
        })
    }
}
