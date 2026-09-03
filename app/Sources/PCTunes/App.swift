import SwiftUI

@main
struct PCTunesApp: App {
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if let icon = MenuBarIcon.image {
                if let title = model.menuBarTitle {
                    Label { Text(title) } icon: { Image(nsImage: icon) }
                } else {
                    Image(nsImage: icon)
                }
            } else if let title = model.menuBarTitle {
                Label(title, systemImage: "play.circle.fill")
            } else {
                Image(systemName: "play.circle.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
