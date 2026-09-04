import SwiftUI

@main
struct PCTunesApp: App {
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if let title = model.menuBarTitle {
                Label { Text(title) } icon: { Image(nsImage: MenuBarIcon.image) }
            } else {
                Image(nsImage: MenuBarIcon.image)
            }
        }
        .menuBarExtraStyle(.window)

        // A real Settings scene, opened from the dropdown via `SettingsLink`. SwiftUI
        // manages the window itself — nothing here has to create or retain it.
        // Qualified as `SwiftUI.Settings` because this app's own `Settings` class
        // (the preferences store) shadows the identically named scene type.
        SwiftUI.Settings {
            SettingsView()
        }
    }
}
