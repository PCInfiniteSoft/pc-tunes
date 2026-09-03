import Foundation

/// Decides which YouTube Music source drives the widget.
///
/// The installed PWA always beats a regular browser tab. Within a kind, the most
/// recently updated source wins. Sources that stop sending heartbeats are dropped
/// by `dropStale(olderThan:)`.
public struct SourceArbiter: Sendable {
    private struct Entry: Sendable {
        var source: SourceKind
        var track: TrackState
        var updatedAt: Date
    }

    private var entries: [Int: Entry] = [:]

    public init() {}

    public mutating func apply(_ message: InboundMessage, at now: Date) {
        switch message {
        case .state(let tabId, let source, let track):
            entries[tabId] = Entry(source: source, track: track, updatedAt: now)
        case .gone(let tabId):
            entries.removeValue(forKey: tabId)
        }
    }

    /// Removes every source whose last update is at or before `cutoff`.
    public mutating func dropStale(olderThan cutoff: Date) {
        entries = entries.filter { $0.value.updatedAt > cutoff }
    }

    public var active: (tabId: Int, track: TrackState)? {
        let winner = newest(ofKind: .app) ?? newest(ofKind: .tab)
        guard let winner else { return nil }
        return (tabId: winner.key, track: winner.value.track)
    }

    private func newest(ofKind kind: SourceKind) -> (key: Int, value: Entry)? {
        entries
            .filter { $0.value.source == kind }
            .max { $0.value.updatedAt < $1.value.updatedAt }
    }
}
