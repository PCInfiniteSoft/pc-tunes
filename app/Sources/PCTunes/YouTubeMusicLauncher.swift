import AppKit

/// Opens YouTube Music, preferring the installed Chrome PWA over a browser tab.
enum YouTubeMusicLauncher {
    /// Chrome installs PWAs here. Constant on purpose — never built from wire data.
    static let pwaPath = NSString(string: "~/Applications/Chrome Apps.localized/YouTube Music.app")
        .expandingTildeInPath

    static func open() {
        if FileManager.default.fileExists(atPath: pwaPath) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: pwaPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
        guard
            let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
            let url = URL(string: "https://music.youtube.com")
        else { return }
        NSWorkspace.shared.open(
            [url], withApplicationAt: chrome,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
