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
