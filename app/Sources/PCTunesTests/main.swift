import Foundation
import PCTunesCore

func runMessageTests() {
    let stateJSON = """
    {"type":"state","tabId":42,"source":"app","playing":true,"title":"Kalapapruek",
     "artist":"Bodyslam","album":"Save My Life",
     "artwork":"https://example.com/art.jpg","position":42.5,"duration":215}
    """.data(using: .utf8)!

    guard case .state(let tabId, let source, let track)? = try? MessageDecoder.decode(stateJSON) else {
        failures.append("FAIL decode state — did not produce a .state message")
        checkCount += 1
        return
    }
    expectEqual(tabId, 42, "state tabId")
    expectEqual(source, .app, "state source")
    expectEqual(track.title, "Kalapapruek", "state title")
    expectEqual(track.artist, "Bodyslam", "state artist")
    expectEqual(track.album, "Save My Life", "state album")
    expectEqual(track.playing, true, "state playing")
    expectEqual(track.duration, 215, "state duration")
    expectEqual(track.position, 42.5, "state position")
    expectEqual(track.artwork?.absoluteString, "https://example.com/art.jpg", "state artwork")

    // Optional fields may be absent; only type, tabId, source and title are required.
    let sparseJSON = """
    {"type":"state","tabId":7,"source":"tab","title":"Untitled"}
    """.data(using: .utf8)!
    guard case .state(_, _, let sparse)? = try? MessageDecoder.decode(sparseJSON) else {
        failures.append("FAIL decode sparse state — did not produce a .state message")
        checkCount += 1
        return
    }
    expectEqual(sparse.artist, "", "sparse artist defaults to empty")
    expectEqual(sparse.playing, false, "sparse playing defaults to false")
    expectEqual(sparse.duration, 0, "sparse duration defaults to zero")
    expectNil(sparse.artwork, "sparse artwork is nil")

    let goneJSON = #"{"type":"gone","tabId":42}"#.data(using: .utf8)!
    expectEqual(try? MessageDecoder.decode(goneJSON), InboundMessage.gone(tabId: 42), "decode gone")

    // Unknown types are rejected rather than silently accepted.
    let junkJSON = #"{"type":"exec","cmd":"rm -rf /"}"#.data(using: .utf8)!
    expectNil(try? MessageDecoder.decode(junkJSON), "unknown type rejected")
    expectNil(try? MessageDecoder.decode(Data("not json".utf8)), "malformed JSON rejected")

    // A command encodes exactly the four wire fields.
    let cmd = OutboundCommand(action: .next, tabId: 42)
    let encoded = try! JSONSerialization.jsonObject(with: cmd.encoded()) as! [String: Any]
    expectEqual(encoded["type"] as? String, "cmd", "command type")
    expectEqual(encoded["action"] as? String, "next", "command action")
    expectEqual(encoded["tabId"] as? Int, 42, "command tabId")
}

func runArbiterTests() {
    func track(_ title: String, playing: Bool = true) -> TrackState {
        TrackState(playing: playing, title: title, artist: "A", album: "B",
                   artwork: nil, position: 0, duration: 100)
    }
    let t0 = Date(timeIntervalSince1970: 1_000)

    // A lone tab source is used.
    var arbiter = SourceArbiter()
    arbiter.apply(.state(tabId: 1, source: .tab, track: track("tab song")), at: t0)
    expectEqual(arbiter.active?.tabId, 1, "lone tab is active")
    expectEqual(arbiter.active?.track.title, "tab song", "lone tab track")

    // An app source preempts the tab, even when the tab updated more recently.
    arbiter.apply(.state(tabId: 2, source: .app, track: track("pwa song")), at: t0 + 1)
    arbiter.apply(.state(tabId: 1, source: .tab, track: track("tab song 2")), at: t0 + 2)
    expectEqual(arbiter.active?.tabId, 2, "app source preempts newer tab")
    expectEqual(arbiter.active?.track.title, "pwa song", "app source track wins")

    // Two app windows: the most recent one wins.
    arbiter.apply(.state(tabId: 3, source: .app, track: track("pwa song 2")), at: t0 + 3)
    expectEqual(arbiter.active?.tabId, 3, "newest app source wins")

    // Closing app windows falls back to the tab.
    arbiter.apply(.gone(tabId: 3), at: t0 + 4)
    expectEqual(arbiter.active?.tabId, 2, "falls back to remaining app source")
    arbiter.apply(.gone(tabId: 2), at: t0 + 5)
    expectEqual(arbiter.active?.tabId, 1, "falls back to tab when no app source remains")

    // Closing everything leaves no active source.
    arbiter.apply(.gone(tabId: 1), at: t0 + 6)
    expectNil(arbiter.active, "no active source after all are gone")

    // A source that stops sending heartbeats is dropped.
    var stale = SourceArbiter()
    stale.apply(.state(tabId: 9, source: .app, track: track("x")), at: t0)
    // The caller owns the timeout and passes an absolute cutoff.
    let staleAfter: TimeInterval = 15
    stale.dropStale(olderThan: (t0 + 14).addingTimeInterval(-staleAfter))
    expectEqual(stale.active?.tabId, 9, "source within the timeout survives")
    stale.dropStale(olderThan: (t0 + 16).addingTimeInterval(-staleAfter))
    expectNil(stale.active, "source past the timeout is dropped")
}

runMessageTests()
runArbiterTests()
finish()
