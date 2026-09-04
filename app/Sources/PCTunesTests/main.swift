import Foundation
import Network
import PCTunesCore

/// The suite binds its own range so it never fights the running app for 8787-8791.
let testPorts: ClosedRange<UInt16> = 8880...8884

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

    let cold = OutboundCommand(action: .startPlayback, tabId: -1)
    let coldEncoded = try! JSONSerialization.jsonObject(with: cold.encoded()) as! [String: Any]
    expectEqual(coldEncoded["action"] as? String, "startPlayback", "cold-start command action")
    expectEqual(coldEncoded["tabId"] as? Int, -1, "cold-start command carries the no-tab sentinel")
}

func runProtocolTests() {
    // A state message carrying liked and volume decodes both.
    let ratedJSON = """
    {"type":"state","tabId":42,"source":"app","title":"Kalapapruek",
     "liked":"dislike","volume":0.25}
    """.data(using: .utf8)!
    guard case .state(_, _, let rated)? = try? MessageDecoder.decode(ratedJSON) else {
        failures.append("FAIL decode rated state — did not produce a .state message")
        checkCount += 1
        return
    }
    expectEqual(rated.liked, .dislike, "state liked decodes")
    expectEqual(rated.volume, 0.25, "state volume decodes")

    // A state message with neither leaves both nil — absence is meaningful, not a default.
    let unratedJSON = """
    {"type":"state","tabId":42,"source":"app","title":"Kalapapruek"}
    """.data(using: .utf8)!
    guard case .state(_, _, let unrated)? = try? MessageDecoder.decode(unratedJSON) else {
        failures.append("FAIL decode unrated state — did not produce a .state message")
        checkCount += 1
        return
    }
    expectNil(unrated.liked, "state liked absent stays nil")
    expectNil(unrated.volume, "state volume absent stays nil")
    expectNil(unrated.position, "state position absent stays nil, not zero")

    // An explicit zero position is preserved — distinct from an absent one, which is
    // what the keepalive re-send relies on to mean "unknown" rather than "just started".
    let zeroPositionJSON = """
    {"type":"state","tabId":42,"source":"app","title":"Kalapapruek","position":0}
    """.data(using: .utf8)!
    guard case .state(_, _, let zeroPosition)? = try? MessageDecoder.decode(zeroPositionJSON) else {
        failures.append("FAIL decode zero-position state — did not produce a .state message")
        checkCount += 1
        return
    }
    expectEqual(zeroPosition.position, 0, "state position explicit zero is preserved, not treated as absent")

    // An invalid liked value fails the whole message rather than silently dropping it.
    let badLikedJSON = """
    {"type":"state","tabId":42,"source":"app","title":"Kalapapruek","liked":"meh"}
    """.data(using: .utf8)!
    expectNil(try? MessageDecoder.decode(badLikedJSON), "invalid liked value rejects the message")

    // notice decodes its tabId and text.
    let noticeJSON = """
    {"type":"notice","tabId":42,"text":"Next and previous are unavailable"}
    """.data(using: .utf8)!
    expectEqual(
        try? MessageDecoder.decode(noticeJSON),
        InboundMessage.notice(tabId: 42, text: "Next and previous are unavailable"),
        "decode notice"
    )

    // A notice with no text is rejected.
    let noTextNoticeJSON = #"{"type":"notice","tabId":42}"#.data(using: .utf8)!
    expectNil(try? MessageDecoder.decode(noTextNoticeJSON), "notice without text rejected")

    // queue decodes two items in order.
    let queueJSON = """
    {"type":"queue","tabId":42,"items":[
        {"title":"Song A","artist":"Artist A"},
        {"title":"Song B","artist":"Artist B"}
    ]}
    """.data(using: .utf8)!
    expectEqual(
        try? MessageDecoder.decode(queueJSON),
        InboundMessage.queue(tabId: 42, items: [
            QueueItem(title: "Song A", artist: "Artist A"),
            QueueItem(title: "Song B", artist: "Artist B"),
        ]),
        "decode queue with two items in order"
    )

    // A queue with no items key decodes as empty.
    let emptyQueueJSON = #"{"type":"queue","tabId":42}"#.data(using: .utf8)!
    expectEqual(
        try? MessageDecoder.decode(emptyQueueJSON),
        InboundMessage.queue(tabId: 42, items: []),
        "queue without items key decodes as empty"
    )

    // seek encodes action, tabId and value, and omits text entirely.
    let seekCmd = OutboundCommand(action: .seek, tabId: 7, value: 91.5)
    let seekEncoded = try! JSONSerialization.jsonObject(with: seekCmd.encoded()) as! [String: Any]
    expectEqual(seekEncoded["action"] as? String, "seek", "seek command action")
    expectEqual(seekEncoded["tabId"] as? Int, 7, "seek command tabId")
    expectEqual(seekEncoded["value"] as? Double, 91.5, "seek command value")
    expectNil(seekEncoded["text"], "seek command omits text key entirely")

    // search encodes the query intact and omits value.
    let searchCmd = OutboundCommand(action: .search, tabId: 7, text: "ครึ่งหนึ่ง")
    let searchEncoded = try! JSONSerialization.jsonObject(with: searchCmd.encoded()) as! [String: Any]
    expectEqual(searchEncoded["action"] as? String, "search", "search command action")
    expectEqual(searchEncoded["text"] as? String, "ครึ่งหนึ่ง", "search command text intact")
    expectNil(searchEncoded["value"], "search command omits value key entirely")
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

func runMenuBarTitleTests() {
    expectEqual(
        MenuBarTitle.format(title: "Short", artist: "Band"),
        "Short — Band",
        "a short title is untouched"
    )
    expectEqual(
        MenuBarTitle.format(title: "Solo", artist: ""),
        "Solo",
        "an empty artist drops the separator"
    )
    // Exactly at the limit: 35 characters, no ellipsis.
    let exact = String(repeating: "a", count: 35)
    expectEqual(MenuBarTitle.format(title: exact, artist: ""), exact, "a title at the limit is kept whole")
    expectEqual(MenuBarTitle.format(title: exact, artist: "").count, 35, "a title at the limit stays 35 characters")
    // One over: trimmed to 34 characters plus the ellipsis, still 35 total.
    let over = String(repeating: "b", count: 36)
    let trimmed = MenuBarTitle.format(title: over, artist: "")
    expectEqual(trimmed.count, 35, "an over-long title is trimmed to the limit")
    expect(trimmed.hasSuffix("…"), "an over-long title ends in an ellipsis")
    expectEqual(
        MenuBarTitle.format(title: "abc", artist: "", limit: 0),
        "…",
        "a zero limit degrades instead of trapping"
    )
}

func runMenuBarTitleLengthClampTests() {
    expectEqual(MenuBarTitle.clampLength(35), 35, "a value already in range is untouched")
    expectEqual(MenuBarTitle.clampLength(10), 10, "the minimum bound is kept as-is")
    expectEqual(MenuBarTitle.clampLength(80), 80, "the maximum bound is kept as-is")
    expectEqual(MenuBarTitle.clampLength(1), 10, "a value below range clamps up to the minimum")
    expectEqual(MenuBarTitle.clampLength(999), 80, "a value above range clamps down to the maximum")
    expectEqual(
        MenuBarTitle.clampLength(0), 10,
        "UserDefaults' zero-for-unset value clamps up rather than collapsing the title"
    )
    expectEqual(MenuBarTitle.clampLength(-5), 10, "a negative value clamps up to the minimum")
}

func runWebAppTests() {
    let candidates = [
        WebAppCandidate(path: "/Apps/Slack.app", shortcutURL: nil),
        WebAppCandidate(path: "/Apps/YouTube.app", shortcutURL: "https://www.youtube.com/"),
        // Localized name, different browser, query string — none of it should matter.
        WebAppCandidate(
            path: "/Apps/Brave Apps.localized/ยูทูบ มิวสิก.app",
            shortcutURL: "https://music.youtube.com/?source=pwa"
        ),
    ]
    expectEqual(
        ChromiumWebApp.pick(host: "music.youtube.com", from: candidates),
        "/Apps/Brave Apps.localized/ยูทูบ มิวสิก.app",
        "matches on the shortcut URL, not the bundle name"
    )
    expectEqual(
        ChromiumWebApp.pick(host: "MUSIC.YouTube.COM", from: candidates),
        "/Apps/Brave Apps.localized/ยูทูบ มิวสิก.app",
        "host matching is case-insensitive"
    )
    expectNil(
        ChromiumWebApp.pick(host: "open.spotify.com", from: candidates),
        "an absent web app is not matched"
    )
    expectNil(
        ChromiumWebApp.pick(host: "music.youtube.com", from: []),
        "an empty candidate list yields nothing"
    )
}

/// Polls `condition` until it holds or the timeout expires, recording one check.
func expectEventually(
    _ label: String, timeout: TimeInterval = 5, _ condition: () -> Bool
) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            expect(true, label)
            return
        }
        usleep(50_000)
    }
    expect(false, label)
}

func runServerTests() {
    let server = WSServer(portRange: testPorts)
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
    expect(testPorts.contains(port), "bound port is inside the allowed range")

    let client = NWConnection(
        to: .url(URL(string: "ws://127.0.0.1:\(port)/")!),
        using: WSServer.clientParameters()
    )
    var commandJSON = ""
    let helloReceived = DispatchSemaphore(value: 0)
    var helloJSON = ""

    func receiveOnClient() {
        client.receiveMessage { data, _, _, _ in
            if let data, let text = String(data: data, encoding: .utf8) {
                commandJSON = text
                commandReceived.signal()
            }
        }
    }

    // The server greets every peer right after accepting it, before it has even
    // seen this client's own message — so the first frame this client receives
    // must be that greeting, not whatever the app sends later.
    func receiveHello() {
        client.receiveMessage { data, _, _, _ in
            if let data, let text = String(data: data, encoding: .utf8) {
                helloJSON = text
                helloReceived.signal()
            }
            receiveOnClient()
        }
    }

    client.stateUpdateHandler = { state in
        guard case .ready = state else { return }
        receiveHello()
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        let payload = #"{"type":"state","tabId":5,"source":"app","title":"Hi","playing":true}"#
        client.send(
            content: Data(payload.utf8), contentContext: context,
            isComplete: true, completion: .contentProcessed { _ in }
        )
    }
    client.start(queue: .global())

    let gotHello = helloReceived.wait(timeout: .now() + 5) == .success
        && helloJSON.contains("\"type\":\"hello\"")
    expect(gotHello, "the first frame from the server is the greeting")
    expect(
        helloJSON.contains("\"app\":\"PC Tunes\""),
        "the greeting identifies the app, which is what the extension gates on"
    )

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

func runServerResilienceTests() {
    // Defect 1: a second server must fall through to the next free port.
    let first = WSServer(portRange: testPorts)
    do {
        try first.start { _ in }
    } catch {
        failures.append("FAIL port fallback — first server did not start: \(error)")
        checkCount += 1
        return
    }
    let second = WSServer(portRange: testPorts)
    do {
        try second.start { _ in }
    } catch {
        failures.append("FAIL port fallback — second server did not start: \(error)")
        checkCount += 1
        first.stop()
        return
    }
    expect(
        first.boundPort != second.boundPort,
        "a second server binds a different port than the first"
    )
    first.stop()
    second.stop()

    // Defect 3 / keepalive: an unknown message type is dropped without closing
    // the connection, so a valid message sent afterwards still arrives.
    let server = WSServer(portRange: testPorts)
    let arrived = DispatchSemaphore(value: 0)
    var afterPing: InboundMessage?
    do {
        try server.start { message in
            afterPing = message
            arrived.signal()
        }
    } catch {
        failures.append("FAIL ping tolerance — server did not start: \(error)")
        checkCount += 1
        return
    }
    guard let port = server.boundPort else {
        failures.append("FAIL ping tolerance — no bound port")
        checkCount += 1
        return
    }

    let client = NWConnection(
        to: .url(URL(string: "ws://127.0.0.1:\(port)/")!),
        using: WSServer.clientParameters()
    )
    func send(_ text: String) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        client.send(
            content: Data(text.utf8), contentContext: context,
            isComplete: true, completion: .contentProcessed { _ in }
        )
    }
    client.stateUpdateHandler = { state in
        guard case .ready = state else { return }
        send(#"{"type":"ping"}"#)
        send(#"{"type":"state","tabId":77,"source":"tab","title":"After ping"}"#)
    }
    client.start(queue: .global())

    expectEqual(arrived.wait(timeout: .now() + 5), .success, "a ping does not close the connection")
    if case .state(let tabId, _, _)? = afterPing {
        expectEqual(tabId, 77, "the message after the ping arrives intact")
    } else {
        failures.append("FAIL ping tolerance — expected a .state message after the ping")
        checkCount += 1
    }
    client.cancel()
    server.stop()

    // Defect 2: stopping from inside the message handler must not deadlock.
    let reentrant = WSServer(portRange: testPorts)
    let stopped = DispatchSemaphore(value: 0)
    do {
        try reentrant.start { _ in
            reentrant.stop()
            stopped.signal()
        }
    } catch {
        failures.append("FAIL reentrant stop — server did not start: \(error)")
        checkCount += 1
        return
    }
    guard let reentrantPort = reentrant.boundPort else {
        failures.append("FAIL reentrant stop — no bound port")
        checkCount += 1
        return
    }
    let poker = NWConnection(
        to: .url(URL(string: "ws://127.0.0.1:\(reentrantPort)/")!),
        using: WSServer.clientParameters()
    )
    poker.stateUpdateHandler = { state in
        guard case .ready = state else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        poker.send(
            content: Data(#"{"type":"gone","tabId":1}"#.utf8), contentContext: context,
            isComplete: true, completion: .contentProcessed { _ in }
        )
    }
    poker.start(queue: .global())
    expectEqual(stopped.wait(timeout: .now() + 5), .success, "stop() from a message handler returns")
    poker.cancel()

    // Defect 3: a peer that closes cleanly is removed from the connection table.
    let closing = WSServer(portRange: testPorts)
    do {
        try closing.start { _ in }
    } catch {
        failures.append("FAIL close cleanup — server did not start: \(error)")
        checkCount += 1
        return
    }
    guard let closingPort = closing.boundPort else {
        failures.append("FAIL close cleanup — no bound port")
        checkCount += 1
        return
    }
    let departing = NWConnection(
        to: .url(URL(string: "ws://127.0.0.1:\(closingPort)/")!),
        using: WSServer.clientParameters()
    )
    departing.start(queue: .global())
    expectEventually("a connected peer is registered") { closing.connectionCount == 1 }
    departing.cancel()
    expectEventually("a closed peer is removed") { closing.connectionCount == 0 }
    closing.stop()
}

runMessageTests()
runProtocolTests()
runArbiterTests()
runMenuBarTitleTests()
runMenuBarTitleLengthClampTests()
runWebAppTests()
runServerTests()
runServerResilienceTests()
finish()
