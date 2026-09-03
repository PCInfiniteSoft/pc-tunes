import Foundation
import Network
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

    // Only the stale source is swept, not every source.
    var mixed = SourceArbiter()
    mixed.apply(.state(tabId: 20, source: .tab, track: track("old")), at: t0)
    mixed.apply(.state(tabId: 21, source: .tab, track: track("fresh")), at: t0 + 20)
    mixed.dropStale(olderThan: (t0 + 20).addingTimeInterval(-staleAfter))
    expectEqual(mixed.active?.tabId, 21, "fresh source survives the sweep")
    mixed.apply(.gone(tabId: 21), at: t0 + 21)
    expectNil(mixed.active, "the stale source was removed, not merely outranked")
}

func runServerTests() {
    let server = WSServer(portRange: 8787...8791)
    let received = DispatchSemaphore(value: 0)
    let commandReceived = DispatchSemaphore(value: 0)
    var got: InboundMessage?

    do {
        try server.start { message in
            got = message
            received.signal()
        }
    } catch {
        failures.append("FAIL server start — threw \(error)")
        checkCount += 1
        return
    }

    guard let port = server.boundPort else {
        failures.append("FAIL server start — no bound port")
        checkCount += 1
        return
    }
    expect((8787...8791).contains(port), "bound port is inside the allowed range")

    let client = NWConnection(
        to: .url(URL(string: "ws://127.0.0.1:\(port)/")!),
        using: WSServer.clientParameters()
    )
    var commandJSON = ""

    func receiveOnClient() {
        client.receiveMessage { data, _, _, _ in
            if let data, let text = String(data: data, encoding: .utf8) {
                commandJSON = text
                commandReceived.signal()
            }
        }
    }

    client.stateUpdateHandler = { state in
        guard case .ready = state else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        let payload = #"{"type":"state","tabId":5,"source":"app","title":"Hi","playing":true}"#
        client.send(
            content: Data(payload.utf8), contentContext: context,
            isComplete: true, completion: .contentProcessed { _ in }
        )
        receiveOnClient()
    }
    client.start(queue: .global())

    expectEqual(received.wait(timeout: .now() + 5), .success, "server received a message")
    if case .state(let tabId, let source, let track)? = got {
        expectEqual(tabId, 5, "received tabId")
        expectEqual(source, .app, "received source")
        expectEqual(track.title, "Hi", "received title")
    } else {
        failures.append("FAIL server receive — expected a .state message, got \(String(describing: got))")
        checkCount += 1
    }

    server.send(OutboundCommand(action: .next, tabId: 5))
    expectEqual(commandReceived.wait(timeout: .now() + 5), .success, "client received a command")
    expect(commandJSON.contains("\"action\":\"next\""), "command carries the action")
    expect(commandJSON.contains("\"tabId\":5"), "command carries the tabId")

    client.cancel()
    server.stop()
}

runMessageTests()
runArbiterTests()
runServerTests()
finish()
