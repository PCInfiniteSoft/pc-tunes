import Foundation

/// Which kind of Chrome window a state update came from.
/// `app` is the installed YouTube Music PWA; `tab` is a regular browser tab.
public enum SourceKind: String, Codable, Equatable, Sendable {
    case app
    case tab
}

/// The listener's rating of the current track, as YouTube Music reports it.
public enum LikeState: String, Codable, Equatable, Sendable {
    case like
    case dislike
}

/// A snapshot of what YouTube Music is playing.
public struct TrackState: Equatable, Sendable {
    public var playing: Bool
    public var title: String
    public var artist: String
    public var album: String
    public var artwork: URL?
    /// Seconds into the track, or `nil` when the extension's keepalive re-send omitted
    /// it. Absent means unknown, not zero — a stale position resent alongside fresh
    /// ones would otherwise make a progress bar jump backwards.
    public var position: Double?
    public var duration: Double
    public var liked: LikeState?
    public var volume: Double?

    public init(
        playing: Bool, title: String, artist: String, album: String,
        artwork: URL?, position: Double? = nil, duration: Double,
        liked: LikeState? = nil, volume: Double? = nil
    ) {
        self.playing = playing
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.position = position
        self.duration = duration
        self.liked = liked
        self.volume = volume
    }
}

/// One entry in the up-next list.
public struct QueueItem: Decodable, Equatable, Sendable {
    public let title: String
    public let artist: String

    public init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }
}

/// The message types the app accepts from the extension.
public enum InboundMessage: Equatable, Sendable {
    case state(tabId: Int, source: SourceKind, track: TrackState)
    case gone(tabId: Int)
    /// The extension could not do something — most often a page selector that no
    /// longer matches. Surfaced in the dropdown, because a console warning is not a
    /// place any user will look.
    case notice(tabId: Int, text: String)
    /// The up-next list, sent only in reply to `requestQueue`.
    case queue(tabId: Int, items: [QueueItem])
}

public enum MessageDecodeError: Error, Equatable {
    case malformed
    case unknownType(String)
    case missingField(String)
}

public enum MessageDecoder {
    private struct Raw: Decodable {
        let type: String
        let tabId: Int?
        let source: SourceKind?
        let playing: Bool?
        let title: String?
        let artist: String?
        let album: String?
        let artwork: String?
        let position: Double?
        let duration: Double?
        let liked: LikeState?
        let volume: Double?
        let text: String?
        let items: [QueueItem]?
    }

    public static func decode(_ data: Data) throws -> InboundMessage {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
            throw MessageDecodeError.malformed
        }
        switch raw.type {
        case "state":
            guard let tabId = raw.tabId else { throw MessageDecodeError.missingField("tabId") }
            guard let source = raw.source else { throw MessageDecodeError.missingField("source") }
            guard let title = raw.title else { throw MessageDecodeError.missingField("title") }
            let track = TrackState(
                playing: raw.playing ?? false,
                title: title,
                artist: raw.artist ?? "",
                album: raw.album ?? "",
                artwork: raw.artwork.flatMap(URL.init(string:)),
                position: raw.position,
                duration: raw.duration ?? 0,
                liked: raw.liked,
                volume: raw.volume
            )
            return .state(tabId: tabId, source: source, track: track)
        case "gone":
            guard let tabId = raw.tabId else { throw MessageDecodeError.missingField("tabId") }
            return .gone(tabId: tabId)
        case "notice":
            guard let tabId = raw.tabId else { throw MessageDecodeError.missingField("tabId") }
            guard let text = raw.text else { throw MessageDecodeError.missingField("text") }
            return .notice(tabId: tabId, text: text)
        case "queue":
            guard let tabId = raw.tabId else { throw MessageDecodeError.missingField("tabId") }
            return .queue(tabId: tabId, items: raw.items ?? [])
        default:
            throw MessageDecodeError.unknownType(raw.type)
        }
    }
}

/// A transport command sent back to the extension, addressed to a specific tab.
public struct OutboundCommand: Encodable, Equatable, Sendable {
    public enum Action: String, Encodable, Equatable, Sendable {
        case playPause
        case next
        case prev
        case focusTab
        case startPlayback
        case like
        case dislike
        case seek
        case volume
        case search
        case requestQueue
    }

    public let type = "cmd"
    public let action: Action
    public let tabId: Int
    /// Seek target in seconds, or volume from 0 to 1. Omitted when the action needs no number.
    public let value: Double?
    /// A search query. Omitted for every other action.
    public let text: String?

    public init(action: Action, tabId: Int, value: Double? = nil, text: String? = nil) {
        self.action = action
        self.tabId = tabId
        self.value = value
        self.text = text
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}
