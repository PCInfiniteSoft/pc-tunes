# PC Tunes — YouTube Music Menu Bar Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar widget that displays the currently playing YouTube Music track and provides play/pause, next, and previous controls.

**Architecture:** A Chrome MV3 extension reads playback state from the YouTube Music page and pushes it over a loopback WebSocket to a native Swift menu bar app. The app owns arbitration between the PWA window and regular tabs, and sends transport commands back over the same socket.

**Tech Stack:** Swift 6.3 (SwiftPM, SwiftUI `MenuBarExtra`, `Network.framework`, `ServiceManagement`), Chrome Manifest V3. Zero third-party dependencies.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-09-03-ytmusic-menubar-widget-design.md`. Read it before starting.
- **No third-party dependencies.** Not in `Package.swift`, not in the extension. `Network.framework` provides the WebSocket server; the extension uses only built-in browser APIs.
- **This machine has Command Line Tools only — no full Xcode.** `XCTest` and `swift-testing` are both unavailable (verified). Tests are written against the hand-rolled harness in `Sources/PCTunesTests/TestKit.swift` and run with `swift run PCTunesTests`. Never add `import XCTest` or `import Testing`.
- **Swift language mode v5** on every target (`swiftSettings: [.swiftLanguageMode(.v5)]`). Strict Swift 6 concurrency is not worth the friction here.
- **Deployment target:** macOS 14.
- **The WebSocket server binds `127.0.0.1` only** via `NWParameters.requiredLocalEndpoint`. Never `0.0.0.0`, never `NWListener(using:on:)` which binds all interfaces.
- **Port range:** 8787 through 8791 inclusive, tried in ascending order, first free port wins.
- **Extension content script matches:** `https://music.youtube.com/*` and nothing else.
- **Inbound message types the app accepts:** `state` and `gone`. Everything else is dropped silently.
- **The PWA wins arbitration.** The app prefers the most recently updated `"app"` source; only when none exists does it use the most recently updated `"tab"` source.
- **Heartbeat 5s, disconnect timeout 15s, extension keepalive ping 20s, reconnect backoff 1s → 2s → 4s → 8s → 30s.**
- Commit after every task using conventional commit messages.

## File Structure

```
PC Tunes/
├── app/
│   ├── Package.swift                             Package manifest, three targets
│   ├── build.sh                                  Assembles and ad-hoc signs PC Tunes.app
│   └── Sources/
│       ├── PCTunesCore/                          Pure logic — no UI, no AppKit
│       │   ├── Messages.swift                    Wire types + decoding + command encoding
│       │   ├── SourceArbiter.swift               PWA-wins arbitration + staleness
│       │   └── WSServer.swift                    Loopback WebSocket server
│       ├── PCTunes/                              The app itself
│       │   ├── App.swift                         @main, MenuBarExtra scene
│       │   ├── MenuContent.swift                 Dropdown view
│       │   ├── PlayerModel.swift                 ObservableObject wiring server → arbiter → UI
│       │   ├── LoginItem.swift                   SMAppService wrapper
│       │   └── YouTubeMusicLauncher.swift        Opens the PWA, falls back to a Chrome tab
│       └── PCTunesTests/                         Executable test runner
│           ├── TestKit.swift                     expect/expectEqual/finish
│           └── main.swift                        Calls each suite
├── extension/
│   ├── manifest.json
│   ├── inject.js                                 MAIN world — reads state, clicks controls
│   ├── content.js                                Isolated world — postMessage bridge
│   └── sw.js                                     Service worker — WebSocket, labelling, routing
├── docs/
└── README.md
```

`PCTunesCore` holds everything testable and nothing that touches AppKit or SwiftUI, so the test runner can link it without dragging in UI.

---

### Task 1: Package scaffold and test harness

**Files:**
- Create: `app/Package.swift`
- Create: `app/Sources/PCTunesCore/Messages.swift`
- Create: `app/Sources/PCTunesTests/TestKit.swift`
- Create: `app/Sources/PCTunesTests/main.swift`
- Create: `app/.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: `expect(_:_:)`, `expectEqual(_:_:_:)`, `finish()` test helpers; the `PCTunesCore` module; `swift run PCTunesTests` as the project's test command.

- [ ] **Step 1: Create the package manifest**

`app/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PCTunes",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PCTunesCore",
            path: "Sources/PCTunesCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PCTunes",
            dependencies: ["PCTunesCore"],
            path: "Sources/PCTunes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PCTunesTests",
            dependencies: ["PCTunesCore"],
            path: "Sources/PCTunesTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`app/.gitignore`:

```
.build/
*.app/
```

- [ ] **Step 2: Write the test harness**

`app/Sources/PCTunesTests/TestKit.swift`:

```swift
import Foundation

var checkCount = 0
var failures: [String] = []

func expect(_ condition: Bool, _ label: String, file: StaticString = #file, line: UInt = #line) {
    checkCount += 1
    if !condition {
        failures.append("FAIL \(label) — expected true (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ label: String,
    file: StaticString = #file, line: UInt = #line
) {
    checkCount += 1
    if actual != expected {
        failures.append("FAIL \(label) — got \(actual), expected \(expected) (\(file):\(line))")
    }
}

func expectNil<T>(_ value: T?, _ label: String, file: StaticString = #file, line: UInt = #line) {
    checkCount += 1
    if value != nil {
        failures.append("FAIL \(label) — expected nil, got \(value!) (\(file):\(line))")
    }
}

func finish() -> Never {
    if failures.isEmpty {
        print("✅ \(checkCount) checks passed")
        exit(0)
    }
    for failure in failures { print(failure) }
    print("❌ \(failures.count) of \(checkCount) checks failed")
    exit(1)
}
```

- [ ] **Step 3: Write the failing test for message decoding**

`app/Sources/PCTunesTests/main.swift`:

```swift
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

runMessageTests()
finish()
```

- [ ] **Step 4: Run the test and verify it fails to compile**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift run PCTunesTests
```

Expected: build failure, `cannot find 'MessageDecoder' in scope`.

- [ ] **Step 5: Implement the wire types**

`app/Sources/PCTunesCore/Messages.swift`:

```swift
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
```

- [ ] **Step 6: Run the tests and verify they pass**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift run PCTunesTests
```

Expected: `✅ 18 checks passed`, exit code 0.

- [ ] **Step 7: Commit**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes" && git add app && git commit -m "feat: add SwiftPM scaffold, test harness and wire message types"
```

---

### Task 2: Source arbitration

**Files:**
- Create: `app/Sources/PCTunesCore/SourceArbiter.swift`
- Modify: `app/Sources/PCTunesTests/main.swift`

**Interfaces:**
- Consumes: `InboundMessage`, `SourceKind`, `TrackState` from Task 1.
- Produces: `SourceArbiter` with `mutating func apply(_ message: InboundMessage, at now: Date)`, `mutating func dropStale(olderThan cutoff: Date)`, `var active: (tabId: Int, track: TrackState)?`.

- [ ] **Step 1: Write the failing test**

Add to `app/Sources/PCTunesTests/main.swift`, above the `runMessageTests()` call:

```swift
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
    stale.dropStale(olderThan: t0 + 14)
    expectEqual(stale.active?.tabId, 9, "source within the timeout survives")
    stale.dropStale(olderThan: t0 + 16)
    expectNil(stale.active, "source past the timeout is dropped")
}
```

And change the bottom of the file to:

```swift
runMessageTests()
runArbiterTests()
finish()
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift run PCTunesTests
```

Expected: build failure, `cannot find 'SourceArbiter' in scope`.

- [ ] **Step 3: Implement the arbiter**

`app/Sources/PCTunesCore/SourceArbiter.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift run PCTunesTests
```

Expected: `✅ 28 checks passed`, exit code 0.

- [ ] **Step 5: Commit**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes" && git add app && git commit -m "feat: add PWA-wins source arbitration"
```

---

### Task 3: Loopback WebSocket server

**Files:**
- Create: `app/Sources/PCTunesCore/WSServer.swift`
- Modify: `app/Sources/PCTunesTests/main.swift`

**Interfaces:**
- Consumes: `InboundMessage`, `MessageDecoder`, `OutboundCommand` from Task 1.
- Produces: `WSServer` with `init(portRange:)`, `func start(onMessage:) throws`, `var boundPort: UInt16?`, `func send(_ command: OutboundCommand)`, `func stop()`, and `static func clientParameters()` for tests.

**Verified facts to rely on** (spiked before this plan was written, do not re-litigate):

- A `NWListener` with `NWProtocolWebSocket.Options` inserted at index 0 of `defaultProtocolStack.applicationProtocols` accepts browser WebSocket clients and supports bidirectional text frames.
- Restricting the bind to loopback requires `params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)` plus `params.allowLocalEndpointReuse = true`. Do **not** use `requiredInterfaceType = .loopback` — it silently prevents connections.
- A Swift `NWConnection` test client must target `.url(URL(string: "ws://127.0.0.1:<port>/")!)`, not `.hostPort`, or the WebSocket handshake never completes.
- Sending requires an explicit `NWConnection.ContentContext` carrying `NWProtocolWebSocket.Metadata(opcode: .text)`.

- [ ] **Step 1: Write the failing test**

Add `import Network` to the imports at the top of
`app/Sources/PCTunesTests/main.swift`, then add this function above the run calls at the
bottom of the file:

```swift
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
```

Change the bottom of the file to:

```swift
runMessageTests()
runArbiterTests()
runServerTests()
finish()
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift run PCTunesTests
```

Expected: build failure, `cannot find 'WSServer' in scope`.

- [ ] **Step 3: Implement the server**

`app/Sources/PCTunesCore/WSServer.swift`:

```swift
import Foundation
import Network

/// A WebSocket server bound to loopback only, spoken to by the Chrome extension.
///
/// Binding is restricted with `requiredLocalEndpoint` so the socket is never reachable
/// from another machine. Ports are tried in ascending order and the first free one wins.
public final class WSServer {
    public typealias MessageHandler = (InboundMessage) -> Void

    private let portRange: ClosedRange<UInt16>
    private let queue = DispatchQueue(label: "com.pcinfinity.pctunes.wsserver")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var onMessage: MessageHandler?

    public private(set) var boundPort: UInt16?

    public init(portRange: ClosedRange<UInt16> = 8787...8791) {
        self.portRange = portRange
    }

    /// Parameters for a WebSocket peer. Exposed so tests can build a matching client.
    public static func clientParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        return parameters
    }

    public enum StartError: Error {
        case noFreePort
    }

    public func start(onMessage: @escaping MessageHandler) throws {
        self.onMessage = onMessage

        for port in portRange {
            let parameters = Self.clientParameters()
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: "127.0.0.1",
                port: NWEndpoint.Port(rawValue: port)!
            )
            guard let listener = try? NWListener(using: parameters) else { continue }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)

            self.listener = listener
            self.boundPort = port
            return
        }
        throw StartError.noFreePort
    }

    public func send(_ command: OutboundCommand) {
        let data = command.encoded()
        guard !data.isEmpty else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "command", metadata: [metadata])
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.connections.values {
                connection.send(
                    content: data, contentContext: context,
                    isComplete: true, completion: .contentProcessed { _ in }
                )
            }
        }
    }

    public func stop() {
        queue.sync {
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
        }
        listener?.cancel()
        listener = nil
        boundPort = nil
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        queue.async { self.connections[key] = connection }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.queue.async { self?.connections.removeValue(forKey: key) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let message = try? MessageDecoder.decode(data) {
                self.onMessage?(message)
            }
            // Anything that fails to decode — including unknown message types — is dropped.
            guard error == nil else {
                connection.cancel()
                return
            }
            self.receive(on: connection)
        }
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift run PCTunesTests
```

Expected: `✅ 36 checks passed`, exit code 0. If the run hangs past ten seconds, the loopback bind is misconfigured — re-check `requiredLocalEndpoint`.

- [ ] **Step 5: Verify the socket is loopback-only**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift run PCTunesTests & sleep 2; lsof -nP -iTCP -sTCP:LISTEN | grep 878 || echo "no listener visible"; wait
```

Expected: any line printed shows `127.0.0.1:87xx`, never `*:87xx`.

- [ ] **Step 6: Commit**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes" && git add app && git commit -m "feat: add loopback WebSocket server on ports 8787-8791"
```

---

### Task 4: Player model, launcher and login item

**Files:**
- Create: `app/Sources/PCTunes/PlayerModel.swift`
- Create: `app/Sources/PCTunes/YouTubeMusicLauncher.swift`
- Create: `app/Sources/PCTunes/LoginItem.swift`

**Interfaces:**
- Consumes: `WSServer`, `SourceArbiter`, `OutboundCommand`, `TrackState` from Tasks 1-3.
- Produces: `PlayerModel` (`@MainActor final class ... ObservableObject`) with published `track: TrackState?`, `menuBarTitle: String?`, and methods `playPause()`, `next()`, `previous()`, `openYouTubeMusic()`; `LoginItem.isEnabled` / `LoginItem.set(_:)`; `YouTubeMusicLauncher.open()`.

- [ ] **Step 1: Implement the launcher**

`app/Sources/PCTunes/YouTubeMusicLauncher.swift`:

```swift
import AppKit

/// Opens YouTube Music, preferring the installed Chrome PWA over a browser tab.
enum YouTubeMusicLauncher {
    /// Chrome installs PWAs here. Constant on purpose — never built from wire data.
    static let pwaPath = NSString(string: "~/Applications/Chrome Apps.localized/YouTube Music.app")
        .expandingTildeInPath

    static func open() {
        if FileManager.default.fileExists(atPath: pwaPath) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: pwaPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
        guard
            let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
            let url = URL(string: "https://music.youtube.com")
        else { return }
        NSWorkspace.shared.open(
            [url], withApplicationAt: chrome,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
```

- [ ] **Step 2: Implement the login item wrapper**

`app/Sources/PCTunes/LoginItem.swift`:

```swift
import ServiceManagement

/// Wraps `SMAppService.mainApp`, which requires the app to run from a signed bundle.
/// `build.sh` ad-hoc signs `PC Tunes.app` so this works for a locally built copy.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[PC Tunes] login item toggle failed: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 3: Implement the player model**

`app/Sources/PCTunes/PlayerModel.swift`:

```swift
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
    @Published var launchAtLogin: Bool = LoginItem.isEnabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            LoginItem.set(launchAtLogin)
        }
    }

    private var arbiter = SourceArbiter()
    private let server = WSServer()
    private var staleTimer: Timer?

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
```

- [ ] **Step 4: Verify it builds**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift build 2>&1 | tail -5
```

Expected: `Build complete!`. The `PCTunes` executable has no entry point yet, which is fine — `App.swift` arrives in Task 5.

- [ ] **Step 5: Commit**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes" && git add app && git commit -m "feat: add player model, PWA launcher and login item"
```

---

### Task 5: Menu bar UI and app bundle

**Files:**
- Create: `app/Sources/PCTunes/App.swift`
- Create: `app/Sources/PCTunes/MenuContent.swift`
- Create: `app/build.sh`

**Interfaces:**
- Consumes: `PlayerModel` from Task 4.
- Produces: a runnable `PC Tunes.app` bundle at `app/PC Tunes.app`.

- [ ] **Step 1: Write the app entry point**

`app/Sources/PCTunes/App.swift`. The file must **not** be named `main.swift` — `@main`
and a `main.swift` in the same target is a compile error.

The scene holds no startup logic: `PlayerModel.init()` already starts the WebSocket
server, which is the only place guaranteed to run at launch rather than when the
dropdown is first opened.

```swift
import SwiftUI

@main
struct PCTunesApp: App {
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if let title = model.menuBarTitle {
                Label(title, systemImage: "music.note")
            } else {
                Image(systemName: "music.note")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 2: Write the dropdown view**

`app/Sources/PCTunes/MenuContent.swift`:

```swift
import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let track = model.track {
                HStack(alignment: .top, spacing: 12) {
                    artwork(for: track.artwork)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !track.album.isEmpty {
                            Text(track.album)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Not playing")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 20) {
                controlButton("backward.fill", action: model.previous)
                controlButton(
                    model.track?.playing == true ? "pause.fill" : "play.fill",
                    action: model.playPause
                )
                controlButton("forward.fill", action: model.next)
            }
            .frame(maxWidth: .infinity)
            .disabled(!model.isConnected)

            Divider()

            Button(model.isConnected ? "Go to YouTube Music" : "Open YouTube Music") {
                model.openYouTubeMusic()
            }
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Button("Quit PC Tunes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 280)
    }

    @ViewBuilder
    private func artwork(for url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: "music.note").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 40, height: 30)
                .contentShape(Rectangle())
        }
    }
}
```

- [ ] **Step 3: Write the bundle build script**

`app/build.sh`:

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="PC Tunes"
BUNDLE="$APP_NAME.app"

swift build -c release --product PCTunes

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$(swift build -c release --product PCTunes --show-bin-path)/PCTunes" \
   "$BUNDLE/Contents/MacOS/PCTunes"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PC Tunes</string>
    <key>CFBundleDisplayName</key>
    <string>PC Tunes</string>
    <key>CFBundleIdentifier</key>
    <string>com.pcinfinity.pctunes</string>
    <key>CFBundleExecutable</key>
    <string>PCTunes</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. SMAppService refuses to register an unsigned bundle.
codesign --force --sign - "$BUNDLE"

echo "Built $PWD/$BUNDLE"
```

Make it executable:

```bash
chmod +x "/Users/pcinfinity/Dev/PC Tunes/app/build.sh"
```

- [ ] **Step 4: Build the bundle and verify it launches**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && ./build.sh && open "PC Tunes.app"
```

Expected: `Built .../PC Tunes.app`, and a `♪` icon appears in the menu bar with no Dock icon. Clicking it shows "Not playing" with disabled transport buttons and an enabled "Open YouTube Music".

- [ ] **Step 5: Verify the port is bound and loopback-only**

```bash
lsof -nP -iTCP -sTCP:LISTEN | grep PCTunes
```

Expected: one line showing `127.0.0.1:8787`.

- [ ] **Step 6: Verify "Open YouTube Music" launches the PWA**

Click the menu bar icon, then click "Open YouTube Music". Expected: the YouTube Music PWA window opens.

- [ ] **Step 7: Quit the app and commit**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes" && git add app && git commit -m "feat: add menu bar UI and app bundle build script"
```

---

### Task 6: Extension manifest and page reader

**Files:**
- Create: `extension/manifest.json`
- Create: `extension/inject.js`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `window.postMessage({__pcTunes: true, dir: "out", payload})` emitted from the page, and a listener for `{__pcTunes: true, dir: "in", action}`. Task 7's `content.js` is the only consumer.

- [ ] **Step 1: Write the manifest**

`extension/manifest.json`:

```json
{
  "manifest_version": 3,
  "name": "PC Tunes Bridge",
  "version": "1.0.0",
  "description": "Bridges YouTube Music playback state to the PC Tunes menu bar app.",
  "permissions": ["tabs"],
  "background": {
    "service_worker": "sw.js"
  },
  "content_scripts": [
    {
      "matches": ["https://music.youtube.com/*"],
      "js": ["inject.js"],
      "world": "MAIN",
      "run_at": "document_idle"
    },
    {
      "matches": ["https://music.youtube.com/*"],
      "js": ["content.js"],
      "run_at": "document_idle"
    }
  ]
}
```

- [ ] **Step 2: Write the page reader**

`extension/inject.js` runs in the page's own JavaScript world, which is the only place
`navigator.mediaSession.metadata` is readable.

```js
(() => {
  "use strict";

  const HEARTBEAT_MS = 5000;
  const COALESCE_MS = 500;
  const CONTROL_SELECTORS = {
    playPause: "#play-pause-button",
    next: ".next-button",
    prev: ".previous-button",
  };

  const playerBar = () => document.querySelector("ytmusic-player-bar");
  const videoEl = () => document.querySelector("video");

  function readState() {
    const video = videoEl();
    const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
    if (!video || !metadata) return null;

    const artworkList = metadata.artwork || [];
    const artwork = artworkList.length ? artworkList[artworkList.length - 1].src : null;

    return {
      playing: !video.paused,
      title: metadata.title || "",
      artist: metadata.artist || "",
      album: metadata.album || "",
      artwork,
      position: video.currentTime || 0,
      duration: Number.isFinite(video.duration) ? video.duration : 0,
    };
  }

  let lastKey = "";
  let coalesceTimer = null;

  function push(force) {
    const state = readState();
    if (!state) return;
    const key = JSON.stringify([
      state.playing, state.title, state.artist, state.album, state.artwork,
    ]);
    if (!force && key === lastKey) return;
    lastKey = key;
    window.postMessage({ __pcTunes: true, dir: "out", payload: state }, "*");
  }

  function schedulePush() {
    if (coalesceTimer) return;
    coalesceTimer = setTimeout(() => {
      coalesceTimer = null;
      push(false);
    }, COALESCE_MS);
  }

  function runCommand(action) {
    // focusTab is handled entirely by the service worker.
    if (action === "focusTab") return;

    const selector = CONTROL_SELECTORS[action];
    const bar = playerBar();
    const button = selector && bar ? bar.querySelector(selector) : null;
    if (button) {
      button.click();
      setTimeout(() => push(true), 300);
      return;
    }

    // Fallback for play/pause only. Next and previous have no equivalent.
    if (action === "playPause") {
      const video = videoEl();
      if (video) {
        if (video.paused) { video.play(); } else { video.pause(); }
        setTimeout(() => push(true), 300);
        return;
      }
    }
    console.warn("[PC Tunes] control not found for action:", action);
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.__pcTunes !== true || data.dir !== "in") return;
    runCommand(data.action);
  });

  function attach() {
    const video = videoEl();
    if (!video) {
      setTimeout(attach, 500);
      return;
    }
    video.addEventListener("play", () => push(true));
    video.addEventListener("pause", () => push(true));
    video.addEventListener("loadedmetadata", () => push(true));

    const bar = playerBar();
    if (bar) {
      new MutationObserver(schedulePush).observe(bar, {
        subtree: true,
        childList: true,
        characterData: true,
      });
    }

    setInterval(() => push(true), HEARTBEAT_MS);
    push(true);
  }

  attach();
})();
```

- [ ] **Step 3: Verify the reader works in the page**

Open the YouTube Music PWA, play a track, then open its DevTools (right-click → Inspect,
or `chrome://inspect` → the YouTube Music target) and run in the Console:

```js
addEventListener("message", (e) => e.data && e.data.__pcTunes && console.log(e.data.payload));
```

Expected: within 5 seconds an object logs with the correct `title`, `artist`, and
`playing: true`.

- [ ] **Step 4: Verify a control works**

In the same Console:

```js
postMessage({ __pcTunes: true, dir: "in", action: "playPause" }, "*");
```

Expected: playback toggles.

- [ ] **Step 5: Commit**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes" && git add extension && git commit -m "feat: add extension manifest and YouTube Music page reader"
```

---

### Task 7: Extension bridge and WebSocket client

**Files:**
- Create: `extension/content.js`
- Create: `extension/sw.js`

**Interfaces:**
- Consumes: the `__pcTunes` postMessage protocol from Task 6; the app's WebSocket server from Task 3.
- Produces: `state` and `gone` messages on the wire; consumes `cmd` messages.

- [ ] **Step 1: Write the isolated-world bridge**

`extension/content.js`:

```js
(() => {
  "use strict";

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.__pcTunes !== true || data.dir !== "out") return;
    chrome.runtime.sendMessage({ kind: "state", payload: data.payload }).catch(() => {
      // The service worker restarts on its own; a dropped message is replaced by
      // the next heartbeat.
    });
  });

  chrome.runtime.onMessage.addListener((message) => {
    if (!message || message.kind !== "cmd") return;
    window.postMessage({ __pcTunes: true, dir: "in", action: message.action }, "*");
  });
})();
```

- [ ] **Step 2: Write the service worker**

`extension/sw.js`:

```js
"use strict";

const PORTS = [8787, 8788, 8789, 8790, 8791];
const BACKOFF_MS = [1000, 2000, 4000, 8000, 30000];
const KEEPALIVE_MS = 20000;

let socket = null;
let portIndex = 0;
let attempt = 0;
let reconnectTimer = null;
let keepaliveTimer = null;

/** tabId -> "app" | "tab". Lets us emit a `gone` message when a tab closes. */
const knownTabs = new Map();

async function windowKindFor(tabId) {
  try {
    const tab = await chrome.tabs.get(tabId);
    const win = await chrome.windows.get(tab.windowId);
    return win.type === "app" ? "app" : "tab";
  } catch (error) {
    return "tab";
  }
}

function sendToApp(object) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  socket.send(JSON.stringify(object));
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  const delay = BACKOFF_MS[Math.min(attempt, BACKOFF_MS.length - 1)];
  attempt += 1;
  portIndex = (portIndex + 1) % PORTS.length;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

function connect() {
  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
    return;
  }
  const port = PORTS[portIndex];
  let ws;
  try {
    ws = new WebSocket(`ws://127.0.0.1:${port}/`);
  } catch (error) {
    scheduleReconnect();
    return;
  }
  socket = ws;

  ws.onopen = () => {
    attempt = 0;
    console.log(`[PC Tunes] connected on port ${port}`);
    clearInterval(keepaliveTimer);
    // WebSocket traffic resets the service worker idle timer on Chrome 116+.
    keepaliveTimer = setInterval(() => sendToApp({ type: "ping" }), KEEPALIVE_MS);
  };

  ws.onmessage = async (event) => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch (error) {
      return;
    }
    if (!message || message.type !== "cmd" || typeof message.tabId !== "number") return;

    if (message.action === "focusTab") {
      try {
        const tab = await chrome.tabs.get(message.tabId);
        await chrome.tabs.update(message.tabId, { active: true });
        await chrome.windows.update(tab.windowId, { focused: true });
      } catch (error) {
        // The tab went away; the app will notice via the heartbeat timeout.
      }
      return;
    }

    chrome.tabs
      .sendMessage(message.tabId, { kind: "cmd", action: message.action })
      .catch(() => {});
  };

  ws.onclose = () => {
    clearInterval(keepaliveTimer);
    socket = null;
    scheduleReconnect();
  };

  ws.onerror = () => {
    // onclose always follows, which is where the reconnect is scheduled.
  };
}

chrome.runtime.onMessage.addListener((message, sender) => {
  if (!message || message.kind !== "state") return;
  const tabId = sender.tab && sender.tab.id;
  if (typeof tabId !== "number") return;

  windowKindFor(tabId).then((source) => {
    knownTabs.set(tabId, source);
    sendToApp({ type: "state", tabId, source, ...message.payload });
  });
});

chrome.tabs.onRemoved.addListener((tabId) => {
  if (!knownTabs.has(tabId)) return;
  knownTabs.delete(tabId);
  sendToApp({ type: "gone", tabId });
});

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
```

Note the app ignores `{"type":"ping"}` because it is not `state` or `gone` — that is the
intended behaviour, and the frame still counts as traffic for keepalive purposes.

- [ ] **Step 3: Load the extension**

Open `chrome://extensions`, enable **Developer mode**, click **Load unpacked**, and
select `/Users/pcinfinity/Dev/PC Tunes/extension`.

- [ ] **Step 4: Verify the connection**

Start the app if it is not running:

```bash
open "/Users/pcinfinity/Dev/PC Tunes/app/PC Tunes.app"
```

Open the YouTube Music PWA and play a track. On `chrome://extensions`, click the
extension's **service worker** link to open its console.

Expected: `[PC Tunes] connected on port 8787` in the service worker console, and the
track title and artist appear in the macOS menu bar within 5 seconds.

- [ ] **Step 5: Commit**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes" && git add extension && git commit -m "feat: add extension bridge and WebSocket client"
```

---

### Task 8: End-to-end verification and README

**Files:**
- Create: `README.md`
- Modify: whichever source file a failing check exposes

**Interfaces:**
- Consumes: everything.
- Produces: a verified, documented build.

- [ ] **Step 1: Run the full manual checklist**

Work through each item and record the result. Every one must pass before the task is
complete. Fix the underlying code — never the checklist — when one fails.

1. Open the YouTube Music PWA and play a track. → Title and artist appear in the menu bar within 5s.
2. Click ⏯ in the dropdown. → Playback toggles; the icon in the dropdown flips within 1s.
3. Click ⏭, then ⏮. → The track changes and the menu bar text follows.
4. Also open `https://music.youtube.com` in a regular Chrome tab and play something there. → The menu bar still shows the PWA's track, and the transport buttons still control the PWA.
5. Close the PWA window. → Within 15s the widget switches to the regular tab's track.
6. Close the regular tab too. → The menu bar shows the bare `♪` icon and "Not playing"; transport buttons are disabled.
7. Click "Open YouTube Music" with nothing open. → The PWA launches.
8. With music playing, quit and relaunch `PC Tunes.app`. → State reappears within 5s without touching Chrome.
9. Enable "Launch at login", reboot. → The icon returns after login. Then disable it again if unwanted.

- [ ] **Step 2: Verify the automated tests still pass**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes/app" && swift run PCTunesTests
```

Expected: `✅ 36 checks passed`, exit code 0.

- [ ] **Step 3: Write the README**

`README.md`:

````markdown
# PC Tunes

A macOS menu bar widget for YouTube Music. Shows the current track and provides
play/pause, next and previous without leaving whatever app you are in.

## How it works

A Chrome MV3 extension reads playback state from the YouTube Music page and pushes it
over a loopback WebSocket to a native Swift menu bar app. The app sends transport
commands back over the same socket.

macOS 15.4 and later block the private MediaRemote framework for third-party apps, so
reading "now playing" from the system is not possible — the state has to come from the
page itself.

When YouTube Music is open both as the installed Chrome PWA and as a regular tab, the
PWA always wins.

## Requirements

- macOS 14 or later
- Google Chrome
- Swift toolchain (Command Line Tools is enough — full Xcode is not required)

## Build and install

```bash
cd app && ./build.sh
open "PC Tunes.app"
```

Then load the extension:

1. Open `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked** and select the `extension/` directory

Enable "Launch at login" from the widget's dropdown to have it start automatically.

## Development

```bash
cd app && swift run PCTunesTests   # run the test suite
cd app && swift build              # build without bundling
```

The project has no third-party dependencies. Tests use a small hand-rolled harness in
`Sources/PCTunesTests/TestKit.swift` because neither XCTest nor swift-testing ships with
the Command Line Tools.

## Troubleshooting

**The menu bar shows `♪` with no text while music is playing.** Open the service worker
console from `chrome://extensions` and look for `[PC Tunes] connected on port 8787`. If
it is absent, the app is not running or every port in 8787-8791 is occupied.

**Next and previous stop working after a YouTube Music update.** The button selectors in
`extension/inject.js` (`CONTROL_SELECTORS`) need updating against the current DOM.
````

- [ ] **Step 4: Commit**

```bash
cd "/Users/pcinfinity/Dev/PC Tunes" && git add -A && git commit -m "docs: add README and record end-to-end verification"
```

---

## Notes for the implementer

- **The WebSocket server starts from `PlayerModel.init()`.** Do not add an
  `NSApplicationDelegateAdaptor`, a `.task`, or an `.onAppear` to start it — those all
  fire when the dropdown first opens, which is far too late.
- **Check counts in the "expected" output are exact.** If `swift run PCTunesTests` reports
  a different number, a check was dropped or duplicated — find out which before moving on.
- **Do not add `import XCTest` or `import Testing`.** Neither module exists on this
  machine; the build will fail.
