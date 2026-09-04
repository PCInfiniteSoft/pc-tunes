import PCTunesCore
import UserNotifications

/// Posts a system notification when the playing track's title or artist actually
/// changes. Gated behind `Settings.shared.showNotifications`, which defaults to off.
///
/// `UNUserNotificationCenter` needs a real bundle identifier to do anything, so this
/// only works from the built `PC Tunes.app` — under `swift run` every call into it is a
/// silent no-op.
@MainActor
final class TrackNotifier {
    static let shared = TrackNotifier()

    /// Called when authorization is requested and the user (or a prior decision) denies
    /// it, so the setting can be reflected back off and the reason surfaced somewhere
    /// more visible than a log line. Wired by `PlayerModel` to its `notice` banner —
    /// the same mechanism already used for "the extension couldn't do something".
    var onAuthorizationDenied: (() -> Void)?

    /// Title and artist last seen. `nil` means "nothing seen since launch or since the
    /// last disconnect" — the next arrival is a reconnect, not a change, and must not
    /// notify. Kept up to date regardless of `showNotifications`, so turning the
    /// setting on mid-track does not cause a false "change" on the very next update.
    private var lastKnown: (title: String, artist: String)?

    private init() {}

    /// Call on every update to `PlayerModel.track`, including to `nil`. Decides on its
    /// own whether the transition is a real track change worth notifying about.
    func trackChanged(from oldValue: TrackState?, to newValue: TrackState?) {
        guard let newValue else {
            // Disconnected, or nothing active. Whatever plays next is a fresh arrival,
            // not a continuation of what was playing before.
            lastKnown = nil
            return
        }

        let previous = lastKnown
        lastKnown = (newValue.title, newValue.artist)

        guard let previous else {
            // First state since launch or since a reconnect. Notifying here would
            // surface a notification for a track that was already playing before PC
            // Tunes noticed it — a backlog of noise, not news.
            return
        }

        // A pause, a resume, a position update or a keepalive re-send of the same
        // track all arrive as state messages too; only an actual title/artist change
        // is worth interrupting the user for.
        guard previous.title != newValue.title || previous.artist != newValue.artist else {
            return
        }

        guard Settings.shared.showNotifications else { return }
        notify(title: newValue.title, artist: newValue.artist)
    }

    private func notify(title: String, artist: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = artist
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[PC Tunes] failed to post track-change notification: \(error.localizedDescription)")
            }
        }
    }

    /// Requests notification authorization. Meant to be called only in direct response
    /// to the user switching "Show notifications" on in Settings — never at launch,
    /// which is exactly the behaviour that gets an app's notifications muted forever.
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    NSLog("[PC Tunes] notification authorization request failed: \(error.localizedDescription)")
                }
                guard !granted else { return }
                NSLog("[PC Tunes] notice: notification permission was denied; turning track-change " +
                      "notifications back off. Enable notifications for PC Tunes in System Settings → " +
                      "Notifications, then switch this back on.")
                Settings.shared.showNotifications = false
                self.onAuthorizationDenied?()
            }
        }
    }
}
