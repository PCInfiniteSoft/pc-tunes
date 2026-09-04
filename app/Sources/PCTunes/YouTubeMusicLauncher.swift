import AppKit
import PCTunesCore

/// Opens YouTube Music, preferring the installed progressive web app over a tab.
enum YouTubeMusicLauncher {
    static let host = "music.youtube.com"

    /// The installed YouTube Music web app, or `nil` if there is not one.
    ///
    /// Chromium browsers put these under `~/Applications/<Browser> Apps.localized/`,
    /// where both the folder and the bundle name vary by browser and by language, so
    /// the search matches each bundle's recorded shortcut URL instead.
    static func installedApp() -> String? {
        ChromiumWebApp.pick(host: host, from: candidates())
    }

    /// - Parameter activating: `true` brings the window forward, for the menu item that
    ///   exists to show it. `false` launches it hidden, so playback can start from the
    ///   widget without taking over the screen.
    static func open(activating: Bool = true) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activating
        configuration.hides = !activating

        if let app = installedApp() {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: app),
                configuration: configuration
            )
            return
        }
        // No installed web app — hand the URL to whatever the user has set as their
        // default browser, rather than assuming Chrome. A Brave or Edge user with no
        // web app installed otherwise gets nothing.
        guard let url = URL(string: "https://\(host)") else {
            NSLog("[PC Tunes] could not build a URL for \(host)")
            return
        }
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error {
                NSLog("[PC Tunes] could not open \(url) with the default browser: \(error)")
            }
        }
    }

    /// Every `.app` directly inside `~/Applications` or one level below it, paired with
    /// its shortcut URL. One level is enough: Chromium nests web apps exactly that deep.
    private static func candidates() -> [WebAppCandidate] {
        let manager = FileManager.default
        let root = NSString(string: "~/Applications").expandingTildeInPath

        var bundles: [String] = []
        for entry in (try? manager.contentsOfDirectory(atPath: root)) ?? [] {
            let path = (root as NSString).appendingPathComponent(entry)
            if entry.hasSuffix(".app") {
                bundles.append(path)
                continue
            }
            for inner in (try? manager.contentsOfDirectory(atPath: path)) ?? []
            where inner.hasSuffix(".app") {
                bundles.append((path as NSString).appendingPathComponent(inner))
            }
        }

        return bundles.map { path in
            let plist = (path as NSString).appendingPathComponent("Contents/Info.plist")
            let info = NSDictionary(contentsOfFile: plist)
            return WebAppCandidate(
                path: path,
                shortcutURL: info?["CrAppModeShortcutURL"] as? String
            )
        }
    }
}
