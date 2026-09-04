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

    private static let helloFrame = Data(#"{"type":"hello","app":"PC Tunes"}"#.utf8)
    private static let queueKey = DispatchSpecificKey<Void>()

    public private(set) var boundPort: UInt16?

    /// Called on the server's queue whenever a peer attaches or drops.
    public var onPeerCountChanged: ((Int) -> Void)?

    /// Number of live peer connections.
    ///
    /// Safe from any thread, including from inside an `onMessage` handler — those run
    /// on `queue` already, and a `sync` hop onto a queue the caller owns deadlocks.
    public var connectionCount: Int {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return connections.count
        }
        return queue.sync { connections.count }
    }

    public init(portRange: ClosedRange<UInt16> = 8787...8791) {
        self.portRange = portRange
        queue.setSpecific(key: Self.queueKey, value: ())
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

            // NWListener binds asynchronously: a port conflict only shows up as a
            // `.failed` state after `start`, so wait for the outcome before deciding
            // whether this port is really ours.
            // A loopback bind settles in milliseconds. The timeout is a safety net,
            // kept short because the app starts the server from its main actor:
            // the whole port range costs at most 2.5s in the worst case.
            let settled = DispatchSemaphore(value: 0)
            var didBind = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    didBind = true
                    settled.signal()
                case .failed, .cancelled:
                    settled.signal()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)

            guard settled.wait(timeout: .now() + 0.5) == .success, didBind else {
                listener.cancel()
                continue
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("[PC Tunes] listener on port \(port) failed: \(error)")
                }
            }

            self.listener = listener
            self.boundPort = port
            return
        }
        throw StartError.noFreePort
    }

    public func send(_ command: OutboundCommand) {
        let data = command.encoded()
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.connections.values {
                self.send(data, on: connection)
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        connection.send(
            content: data, contentContext: context,
            isComplete: true, completion: .contentProcessed { _ in }
        )
    }

    public func stop() {
        listener?.cancel()
        // Deliberately async: `stop()` is reachable from a message handler, which
        // already owns `queue`, and a `sync` hop there aborts the process.
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
            self.listener = nil
            self.boundPort = nil
            self.onPeerCountChanged?(self.connections.count)
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        queue.async {
            self.connections[key] = connection
            self.onPeerCountChanged?(self.connections.count)
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.queue.async {
                    guard let self else { return }
                    self.connections.removeValue(forKey: key)
                    self.onPeerCountChanged?(self.connections.count)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        // Identify ourselves so the extension can tell PC Tunes apart from an
        // unrelated process squatting on the same port.
        send(Self.helloFrame, on: connection)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self else { return }

            let websocket = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata
            if websocket?.opcode == .close {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            // A completed receive carrying no payload is the peer's EOF.
            if data == nil && isComplete {
                connection.cancel()
                return
            }

            // Anything that fails to decode — including the extension's `ping`
            // keepalive — is dropped without disturbing the connection.
            if let data, let message = try? MessageDecoder.decode(data) {
                self.onMessage?(message)
            }
            self.receive(on: connection)
        }
    }
}
