import Foundation
import PCTunesCore
import SwiftUI

/// Wires the WebSocket server to the arbiter and republishes the winner for the UI.
@MainActor
final class PlayerModel: ObservableObject {
    /// A source is considered gone this many seconds after its last heartbeat.
    private static let staleAfter: TimeInterval = 15
    private static let maxMenuBarTitleLength = 35

    @Published private(set) var track: TrackState?
    @Published private(set) var activeTabId: Int?
    /// Non-nil when the widget cannot function at all. The dropdown surfaces this
    /// instead of the usual "Not playing" state.
    @Published private(set) var startupFailure: String?
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

    private var arbiter = SourceArbiter()
    private let server = WSServer()
    private var staleTimer: Timer?
    private var isReconcilingLoginItem = false

    var isConnected: Bool { track != nil }

    /// `nil` renders the icon on its own, with no text beside it.
    var menuBarTitle: String? {
        guard let track else { return nil }
        let full = track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
        guard full.count > Self.maxMenuBarTitleLength else { return full }
        return String(full.prefix(Self.maxMenuBarTitleLength - 1)) + "…"
    }

    /// The server must be listening from launch, not from the first time the dropdown
    /// opens, so it starts here rather than in a SwiftUI lifecycle hook.
    init() {
        start()
    }

    private func start() {
        do {
            try server.start { [weak self] message in
                Task { @MainActor in self?.ingest(message) }
            }
        } catch {
            NSLog("[PC Tunes] could not bind a port in 8787-8791: \(error)")
            startupFailure = "Could not open a local port in the range 8787-8791. "
                + "Another app may be using them — quit it and restart PC Tunes."
        }
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expireStaleSources() }
        }
    }

    func playPause() { send(.playPause) }
    func next() { send(.next) }
    func previous() { send(.prev) }

    /// Focuses the existing YouTube Music window when one is connected, otherwise
    /// launches the PWA.
    func openYouTubeMusic() {
        if let tabId = activeTabId {
            server.send(OutboundCommand(action: .focusTab, tabId: tabId))
        } else {
            YouTubeMusicLauncher.open()
        }
    }

    private func send(_ action: OutboundCommand.Action) {
        guard let tabId = activeTabId else { return }
        server.send(OutboundCommand(action: action, tabId: tabId))
    }

    private func ingest(_ message: InboundMessage) {
        arbiter.apply(message, at: Date())
        publishActive()
    }

    private func expireStaleSources() {
        arbiter.dropStale(olderThan: Date().addingTimeInterval(-Self.staleAfter))
        publishActive()
    }

    private func publishActive() {
        let active = arbiter.active
        activeTabId = active?.tabId
        track = active?.track
    }
}
