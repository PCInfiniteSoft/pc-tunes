import PCTunesCore
import SwiftUI

/// The window opened by "Settings…" in the dropdown (via `SettingsLink`). Every control
/// binds straight to `Settings.shared`, so there is no separate view state to keep in
/// sync with it.
struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    /// Deliberately longer than `MenuBarTitle.lengthRange`'s upper bound, so the
    /// preview line actually shows truncation happening across the whole slider range
    /// rather than going un-truncated once the user drags past some shorter sample.
    private static let previewTitle = "A Very Long Song Title That Just Keeps Going and Going"
    private static let previewArtist = "An Artist With An Extremely Long And Unwieldy Name Too"

    var body: some View {
        Form {
            Section("Menu Bar") {
                Stepper(
                    value: $settings.menuBarTitleLength,
                    in: MenuBarTitle.lengthRange
                ) {
                    Text("Title length: \(settings.menuBarTitleLength) characters")
                }
                Text(MenuBarTitle.format(
                    title: Self.previewTitle, artist: Self.previewArtist,
                    limit: settings.menuBarTitleLength
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("⌃⌥Space — Play/Pause")
                    Text("⌃⌥→ — Next")
                    Text("⌃⌥← — Previous")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                Text("These bindings are fixed and cannot be changed in this version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
