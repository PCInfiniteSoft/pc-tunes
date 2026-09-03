import Foundation

/// Which kind of Chrome window a state update came from.
/// `app` is the installed YouTube Music PWA; `tab` is a regular browser tab.
public enum SourceKind: String, Codable, Equatable, Sendable {
    case app
    case tab
}

/// A snapshot of what YouTube Music is playing.
public struct TrackState: Equatable, Sendable {
    public var playing: Bool
    public var title: String
    public var artist: String
    public var album: String
    public var artwork: URL?
    public var position: Double
    public var duration: Double

    public init(
        playing: Bool, title: String, artist: String, album: String,
        artwork: URL?, position: Double, duration: Double
    ) {
        self.playing = playing
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.position = position
        self.duration = duration
    }
}

/// The only two message types the app accepts from the extension.
public enum InboundMessage: Equatable, Sendable {
    case state(tabId: Int, source: SourceKind, track: TrackState)
    case gone(tabId: Int)
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
                position: raw.position ?? 0,
                duration: raw.duration ?? 0
            )
            return .state(tabId: tabId, source: source, track: track)
        case "gone":
            guard let tabId = raw.tabId else { throw MessageDecodeError.missingField("tabId") }
            return .gone(tabId: tabId)
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
    }

    public let type = "cmd"
    public let action: Action
    public let tabId: Int

    public init(action: Action, tabId: Int) {
        self.action = action
        self.tabId = tabId
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}
