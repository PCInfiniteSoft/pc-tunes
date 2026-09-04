import Foundation

/// One installed Chromium progressive web app, as found on disk.
public struct WebAppCandidate: Equatable, Sendable {
    /// Absolute path to the `.app` bundle.
    public let path: String
    /// The bundle's `CrAppModeShortcutURL`, if it has one. Ordinary apps do not.
    public let shortcutURL: String?

    public init(path: String, shortcutURL: String?) {
        self.path = path
        self.shortcutURL = shortcutURL
    }
}

public enum ChromiumWebApp {
    /// Finds the web app pointing at `host`.
    ///
    /// Chromium browsers install PWAs under a browser-specific, localized folder and
    /// name the bundle from the site's own web app manifest, which the site localizes
    /// too — so neither path nor name can be matched against. The shortcut URL each
    /// bundle records is stable across both.
    public static func pick(host: String, from candidates: [WebAppCandidate]) -> String? {
        candidates.first { candidate in
            guard
                let raw = candidate.shortcutURL,
                let url = URL(string: raw),
                let candidateHost = url.host
            else { return false }
            return candidateHost.caseInsensitiveCompare(host) == .orderedSame
        }?.path
    }
}
