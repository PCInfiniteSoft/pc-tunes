import Foundation
import PCTunesCore
import SwiftUI

/// Wires the WebSocket server to the arbiter and republishes the winner for the UI.
@MainActor
final class PlayerModel: ObservableObject {
    /// A source is considered gone this many seconds after its last heartbeat.
    private static let staleAfter: TimeInterval = 15
    /// Addressed to no particular tab: the extension resolves the target itself.
    private static let noTab = -1

    @Published private(set) var track: TrackState? {
        didSet { TrackNotifier.shared.trackChanged(from: oldValue, to: track) }
    }
    @Published private(set) var activeTabId: Int?
    /// Non-nil when the widget cannot function at all. The dropdown surfaces this
    /// instead of the usual "Not playing" state.
    @Published private(set) var startupFailure: String?
    /// Whether the Chrome extension is attached. Distinct from whether anything is
    /// playing: without this the UI cannot tell "extension missing" from "paused".
    @Published private(set) var extensionConnected = false
    /// The port the server actually bound, for the troubleshooting hint.
    @Published private(set) var boundPort: UInt16?
    /// Bound to the dropdown's toggle. Reconciles itself against what `SMAppService`
    /// actually reports, so a failed registration cannot leave the toggle lying.
    @Published var launchAtLogin: Bool = LoginItem.isEnabled {
        didSet {
            guard !isReconcilingLoginItem, launchAtLogin != oldValue else { return }
            let actual = LoginItem.set(launchAtLogin)
            loginItemNeedsApproval = LoginItem.needsApproval
            guard actual != launchAtLogin else { return }
            isReconcilingLoginItem = true
            launchAtLogin = actual
            isReconcilingLoginItem = false
        }
    }

    /// True when the login item is registered but macOS is still waiting for the user
    /// to approve it in System Settings.
    @Published private(set) var loginItemNeedsApproval: Bool = LoginItem.needsApproval

    /// Something the extension could not do — most often a page selector that no longer
    /// matches. Cleared when a command next succeeds, and after a minute regardless.
    @Published private(set) var notice: String?

    /// Up next, populated only after `refreshQueue()`.
    @Published private(set) var queue: [QueueItem] = []

    private var arbiter = SourceArbiter()
    private let server = WSServer()
    private var staleTimer: Timer?
    private var isReconcilingLoginItem = false

    /// When `notice` arrived, so it can expire on its own after a minute.
    private var noticeReceivedAt: Date?
    /// How long a notice stays visible without a fresh command clearing it first.
    private static let noticeLifetime: TimeInterval = 60

    /// The last position reported by a state message, and the instant it arrived.
    /// Backs `displayPosition`; see that property for how the two combine.
    private var anchorPosition: Double = 0
    private var anchoredAt = Date()

    var isConnected: Bool { track != nil }

    /// `nil` renders the icon on its own, with no text beside it — which is the default,
    /// until the user turns the title on in Settings.
    var menuBarTitle: String? {
        guard Settings.shared.showMenuBarTitle, let track else { return nil }
        return MenuBarTitle.format(
            title: track.title, artist: track.artist,
            limit: Settings.shared.menuBarTitleLength
        )
    }

    /// The position to draw right now: the last one reported, plus however long has
    /// passed since, while playing. Keeps the bar smooth without asking the page for a
    /// faster feed.
    var displayPosition: Double {
        guard let track else { return 0 }
        guard track.playing else { return anchorPosition }
        let elapsed = Date().timeIntervalSince(anchoredAt)
        return min(max(anchorPosition + elapsed, 0), track.duration)
    }

    /// The server must be listening from launch, not from the first time the dropdown
    /// opens, so it starts here rather than in a SwiftUI lifecycle hook.
    init() {
        start()
    }

    private func start() {
        // The dropdown's `notice` banner is the same mechanism already used for "the
        // extension couldn't do something" — reused here for "notification permission
        // was denied" so that reaches the user somewhere more visible than a log line.
        TrackNotifier.shared.onAuthorizationDenied = { [weak self] in
            self?.notice = "Notification permission was denied. Enable it in System "
                + "Settings → Notifications → PC Tunes, then turn notifications back on "
                + "in PC Tunes' settings."
            self?.noticeReceivedAt = Date()
        }
        Hotkeys.shared.start(model: self)

        server.onPeerCountChanged = { [weak self] count in
            Task { @MainActor in self?.extensionConnected = count > 0 }
        }
        do {
            try server.start { [weak self] message in
                Task { @MainActor in self?.ingest(message) }
            }
            boundPort = server.boundPort
        } catch {
            NSLog("[PC Tunes] could not bind a port in 8787-8791: \(error)")
            startupFailure = "Could not open a local port in the range 8787-8791. "
                + "Another app may be using them — quit it and restart PC Tunes."
        }
        // Ticks once a second — needed so `displayPosition` redraws smoothly while
        // playing — and doubles as the sweep for stale sources, an expired notice and
        // the login-item state, rather than running a second timer alongside it.
        staleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.expireStaleSources()
                self?.refreshLoginItemState()
                self?.expireNoticeIfNeeded()
                if self?.track?.playing == true {
                    self?.objectWillChange.send()
                }
            }
        }
    }

    func playPause() {
        guard let tabId = activeTabId else {
            // Nothing is connected. Ask the extension to start playback as soon as a
            // YouTube Music page appears, then open the PWA to make one appear.
            dispatch(OutboundCommand(action: .startPlayback, tabId: Self.noTab))
            YouTubeMusicLauncher.open(activating: false)
            return
        }
        dispatch(OutboundCommand(action: .playPause, tabId: tabId))
    }
    func next() { send(.next) }
    func previous() { send(.prev) }
    func like() { send(.like) }
    func dislike() { send(.dislike) }
    func shuffle() { send(.shuffle) }
    func cycleRepeat() { send(.cycleRepeat) }

    /// Moves playback to `seconds` and moves the local anchor immediately, so the bar
    /// responds without waiting for the round trip to the extension and back.
    func seek(to seconds: Double) {
        guard let tabId = activeTabId else { return }
        anchorPosition = seconds
        anchoredAt = Date()
        dispatch(OutboundCommand(action: .seek, tabId: tabId, value: seconds))
    }

    func setVolume(_ level: Double) {
        guard let tabId = activeTabId else { return }
        dispatch(OutboundCommand(action: .volume, tabId: tabId, value: min(1, max(0, level))))
    }

    func refreshQueue() {
        guard let tabId = activeTabId else { return }
        dispatch(OutboundCommand(action: .requestQueue, tabId: tabId))
    }

    /// Focuses the existing YouTube Music window when one is connected, otherwise
    /// launches the PWA.
    func openYouTubeMusic() {
        if let tabId = activeTabId {
            dispatch(OutboundCommand(action: .focusTab, tabId: tabId))
        } else {
            YouTubeMusicLauncher.open()
        }
    }

    private func send(_ action: OutboundCommand.Action) {
        guard let tabId = activeTabId else { return }
        dispatch(OutboundCommand(action: action, tabId: tabId))
    }

    /// Every outbound command goes through here so a successful send always clears a
    /// stale notice — the extension gets another chance to prove the thing it
    /// complained about now works.
    private func dispatch(_ command: OutboundCommand) {
        server.send(command)
        notice = nil
        noticeReceivedAt = nil
    }

    private func ingest(_ message: InboundMessage) {
        switch message {
        case .state(let tabId, _, let track):
            arbiter.apply(message, at: Date())
            publishActive()
            // Only reset the anchor for the source that actually won arbitration, and
            // only when this message carried a real position — the keepalive re-send
            // omits it on purpose, and the anchor should keep running through that.
            if tabId == activeTabId, let position = track.position {
                anchorPosition = position
                anchoredAt = Date()
            }
        case .gone:
            arbiter.apply(message, at: Date())
            publishActive()
        case .notice(let tabId, let text):
            // A background tab cannot put text in the user's menu.
            guard tabId == activeTabId else { return }
            notice = text
            noticeReceivedAt = Date()
        case .queue(let tabId, let items):
            guard tabId == activeTabId else { return }
            queue = items
        }
    }

    private func expireStaleSources() {
        arbiter.dropStale(olderThan: Date().addingTimeInterval(-Self.staleAfter))
        publishActive()
    }

    private func expireNoticeIfNeeded() {
        guard let noticeReceivedAt,
              Date().timeIntervalSince(noticeReceivedAt) >= Self.noticeLifetime
        else { return }
        notice = nil
        self.noticeReceivedAt = nil
    }

    /// The user can approve or revoke the login item in System Settings at any time,
    /// and `SMAppService` has no change notification, so re-read it on the same tick
    /// that sweeps stale sources.
    private func refreshLoginItemState() {
        let actual = LoginItem.isEnabled
        if actual != launchAtLogin {
            isReconcilingLoginItem = true
            launchAtLogin = actual
            isReconcilingLoginItem = false
        }
        loginItemNeedsApproval = LoginItem.needsApproval
    }

    private func publishActive() {
        let active = arbiter.active
        let previousTabId = activeTabId
        activeTabId = active?.tabId
        track = active?.track
        // The list belongs to the source it came from. Once that source is gone — or
        // replaced by a different one — it describes nothing, and left alone it would
        // sit under "Up next" beside "Not playing".
        if active == nil || active?.tabId != previousTabId {
            queue = []
        }
    }
}
