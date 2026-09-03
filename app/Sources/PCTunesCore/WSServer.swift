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
