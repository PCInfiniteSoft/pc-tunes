import PCTunesCore
import SwiftUI

/// The window opened by "Settings…" in the dropdown (via `SettingsLink`). Every control
/// binds straight to `Settings.shared`, so there is no separate view state to keep in
/// sync with it.
struct SettingsView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var hotkeys = Hotkeys.shared

    /// Deliberately longer than `MenuBarTitle.lengthRange`'s upper bound, so the
    /// preview line actually shows truncation happening across the whole slider range
    /// rather than going un-truncated once the user drags past some shorter sample.
    private static let previewTitle = "A Very Long Song Title That Just Keeps Going and Going"
    private static let previewArtist = "An Artist With An Extremely Long And Unwieldy Name Too"

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                if model.loginItemNeedsApproval {
                    Text("Waiting for approval in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Menu Bar") {
                Toggle("Show track title beside the icon", isOn: $settings.showMenuBarTitle)
                Stepper(
                    value: $settings.menuBarTitleLength,
                    in: MenuBarTitle.lengthRange
                ) {
                    Text("Title length: \(settings.menuBarTitleLength) characters")
                }
                .disabled(!settings.showMenuBarTitle)
                Text(MenuBarTitle.format(
                    title: Self.previewTitle, artist: Self.previewArtist,
                    limit: settings.menuBarTitleLength
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(settings.showMenuBarTitle ? 1 : 0.4)
            }

            Section("Notifications") {
                Toggle("Show notifications when the track changes", isOn: $settings.showNotifications)
                    // Authorization is asked for here, when the user expresses actual
                    // interest — never at launch, which is how an app's notifications
                    // end up muted forever before they are ever seen.
                    .onChange(of: settings.showNotifications) { _, isOn in
                        if isOn {
                            TrackNotifier.shared.requestAuthorizationIfNeeded()
                        }
                    }
            }

            Section("Hotkeys") {
                Toggle("Global hotkeys", isOn: $settings.hotkeysEnabled)

                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        VStack(alignment: .trailing, spacing: 2) {
                            KeyRecorder(combo: binding(for: action))
                            if hotkeys.unavailable.contains(action) {
                                Text("Already in use by another app")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .disabled(!settings.hotkeysEnabled)
                }

                HStack {
                    Text("Shortcuts need at least one of ⌃, ⌥ or ⌘.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Defaults") { settings.resetHotkeyCombos() }
                }
            }
        }
        // `.grouped` rather than the default automatic style: the automatic one lays a
        // form out in two columns sized to the widest label, which for these labels is
        // wider than any reasonable window and pushed the first row off both edges.
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
    }

    /// `Settings.hotkeyCombos` holds an entry for every action, so this reads a value
    /// rather than an optional the view would have to second-guess. Writing through it
    /// persists the change and re-registers the hotkey in one step.
    private func binding(for action: HotkeyAction) -> Binding<KeyCombo> {
        Binding(
            get: { settings.hotkeyCombos[action] ?? action.defaultCombo },
            set: { settings.hotkeyCombos[action] = $0 }
        )
    }
}
