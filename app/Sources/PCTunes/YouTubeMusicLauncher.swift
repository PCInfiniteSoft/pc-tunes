import AppKit

/// Opens YouTube Music, preferring the installed Chrome PWA over a browser tab.
enum YouTubeMusicLauncher {
    /// Chrome installs PWAs here. Constant on purpose — never built from wire data.
    static let pwaPath = NSString(string: "~/Applications/Chrome Apps.localized/YouTube Music.app")
        .expandingTildeInPath

    /// - Parameter activating: `true` brings the window forward, for the menu item that
    ///   exists to show it. `false` launches it hidden, so playback can start from the
    ///   widget without taking over the screen.
    static func open(activating: Bool = true) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activating
        configuration.hides = !activating

        if FileManager.default.fileExists(atPath: pwaPath) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: pwaPath),
                configuration: configuration
            )
            return
        }
        guard
            let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
            let url = URL(string: "https://music.youtube.com")
        else { return }
        NSWorkspace.shared.open(
            [url], withApplicationAt: chrome,
            configuration: configuration
        )
    }
}
