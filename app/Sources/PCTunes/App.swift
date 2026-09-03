import SwiftUI

@main
struct PCTunesApp: App {
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if let title = model.menuBarTitle {
                Label(title, systemImage: "music.note")
            } else {
                Image(systemName: "music.note")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
