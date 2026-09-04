import SwiftUI

@main
struct PCTunesApp: App {
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, openSettings: {})
        } label: {
            if let title = model.menuBarTitle {
                Label { Text(title) } icon: { Image(nsImage: MenuBarIcon.image) }
            } else {
                Image(nsImage: MenuBarIcon.image)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
