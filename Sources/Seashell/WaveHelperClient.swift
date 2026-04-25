// WaveHelperClient.swift

// Pineapple 🍍
//
// NIO-based TCP client that communicates with the seashell-helper script
// running inside a Wave Terminal block. The helper has access to WAVETERM_JWT
// and proxies wsh RPC calls back over a simple newline-delimited JSON-RPC protocol.
//
// Connection is optional — direct-config tools work without it. Helper-block tools check
// `isConnected()` and return a clear error if the helper isn't running.

import Foundation
import NIO
import NIOFoundationCompat
import Logging

// MARK: - JSON-RPC types

struct HelperRequest: Codable {
    let id: Int
    let method: String
    let params: [String: AnyCodableValue]
}

struct HelperResponse: Codable {
    let id: Int
    let result: AnyCodableValue?
    let error: HelperError?
}

struct HelperError: Codable {
    let code: Int
    let message: String
}

// MARK: - WaveHelperClient

/// Actor that manages a persistent TCP connection to the seashell-helper block.
actor WaveHelperClient {
    // MARK: Configuration
    private let host: String
    private let port: Int
    private let logger: Logger

    // MARK: State
    private var channel: Channel?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var nextId: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<AnyCodableValue, Error>] = [:]
    private var _isConnected: Bool = false
    private var reconnectTask: Task<Void, Never>?

    // MARK: Init

    init(host: String = "127.0.0.1", port: Int = 9877, logger: Logger = Logger(label: "seashell.wave-helper")) {
        self.host = host
        self.port = port
        self.logger = logger
    }

    // MARK: Public API

    func isConnected() -> Bool {
        return _isConnected
    }

    /// Connect to the helper block. Does not throw — failures set isConnected = false.
    func connect() async {
        guard !_isConnected else { return }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group

        do {
            let handler = HelperChannelHandler(client: self, logger: logger)
            let bootstrap = ClientBootstrap(group: group)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelOption(ChannelOptions.connectTimeout, value: .seconds(5))
                .channelInitializer { channel in
                    channel.pipeline.addHandlers([
                        ByteToMessageHandler(LineBasedFrameDecoder()),
                        MessageToByteHandler(WaveHelperLineEncoder()),
                        handler,
                    ])
                }

            let ch = try await bootstrap.connect(host: host, port: port).get()
            self.channel = ch
            _isConnected = true
            logger.info("Connected to Wave helper at \(host):\(port)")

            // Verify with ping
            do {
                let pong = try await sendRequest(method: "wave.ping", params: [:])
                logger.debug("Wave helper ping OK: \(pong)")
            } catch {
                logger.warning("Wave helper ping failed: \(error)")
            }
        } catch {
            logger.warning("Could not connect to Wave helper at \(host):\(port) — \(error)")
            _isConnected = false
            try? await group.shutdownGracefully()
            self.eventLoopGroup = nil
        }
    }

    /// Disconnect and clean up.
    func disconnect() async {
        _isConnected = false
        reconnectTask?.cancel()
        reconnectTask = nil

        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: WaveHelperError.disconnected)
        }
        pendingRequests = [:]

        if let ch = channel {
            try? await ch.close().get()
            self.channel = nil
        }
        if let group = eventLoopGroup {
            try? await group.shutdownGracefully()
            self.eventLoopGroup = nil
        }
        logger.info("Disconnected from Wave helper")
    }

    // MARK: RPC methods

    func listWorkspaces() async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.listWorkspaces", params: [:])
    }

    func listBlocks(workspaceId: String? = nil, tabId: String? = nil, view: String? = nil) async throws -> AnyCodableValue {
        var params: [String: AnyCodableValue] = [:]
        if let w = workspaceId { params["workspace_id"] = .string(w) }
        if let t = tabId       { params["tab_id"]       = .string(t) }
        if let v = view        { params["view"]          = .string(v) }
        return try await sendRequest(method: "wave.listBlocks", params: params)
    }

    func createBlock(tabId: String, meta: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let params: [String: AnyCodableValue] = [
            "tab_id": .string(tabId),
            "meta":   .dict(meta),
        ]
        return try await sendRequest(method: "wave.createBlock", params: params)
    }

    func deleteBlock(blockId: String) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.deleteBlock", params: ["block_id": .string(blockId)])
    }

    func getScrollback(blockId: String, lastCommandOnly: Bool = false) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.getScrollback", params: [
            "block_id":          .string(blockId),
            "last_command_only": .bool(lastCommandOnly),
        ])
    }

    func getBlockMeta(blockId: String) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.getBlockMeta", params: ["block_id": .string(blockId)])
    }

    func setBlockMeta(blockId: String, meta: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.setBlockMeta", params: [
            "block_id": .string(blockId),
            "meta":     .dict(meta),
        ])
    }

    func runCommand(tabId: String, command: String, cwd: String? = nil, env: [String: AnyCodableValue]? = nil, closeOnExit: Bool = true) async throws -> AnyCodableValue {
        var params: [String: AnyCodableValue] = [
            "tab_id":        .string(tabId),
            "command":       .string(command),
            "close_on_exit": .bool(closeOnExit),
        ]
        if let c = cwd { params["cwd"] = .string(c) }
        if let e = env { params["env"] = .dict(e) }
        return try await sendRequest(method: "wave.runCommand", params: params)
    }

    // MARK: Secret management

    func secretList() async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.secretList", params: [:])
    }

    func secretSet(key: String, value: String) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.secretSet", params: [
            "key":   .string(key),
            "value": .string(value),
        ])
    }

    func secretGet(key: String) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.secretGet", params: ["key": .string(key)])
    }

    func secretDelete(key: String) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.secretDelete", params: ["key": .string(key)])
    }

    func viewFile(tabId: String, file: String) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.viewFile", params: [
            "tab_id": .string(tabId),
            "file":   .string(file),
        ])
    }

    func editFile(tabId: String, file: String) async throws -> AnyCodableValue {
        return try await sendRequest(method: "wave.editFile", params: [
            "tab_id": .string(tabId),
            "file":   .string(file),
        ])
    }

    // MARK: Internal: send a request and await the response

    func sendRequest(method: String, params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        guard _isConnected, let ch = channel else {
            throw WaveHelperError.notConnected
        }

        let id = nextId
        nextId += 1

        let request = HelperRequest(id: id, method: method, params: params)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(request),
              let line = String(data: data, encoding: .utf8) else {
            throw WaveHelperError.encodingFailed
        }

        // Await response via continuation registered before sending.
        // A timeout task races against the real response to prevent leaked continuations
        // if the helper crashes after the request is sent but before it responds.
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation

            // 30-second timeout — fires if no response arrives
            let requestId = id
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                // Only resume if this request is still pending (not already resolved)
                if let timedOut = self.pendingRequests.removeValue(forKey: requestId) {
                    timedOut.resume(throwing: WaveHelperError.timeout)
                }
            }

            // Write to channel on event loop
            ch.eventLoop.execute {
                var buf = ch.allocator.buffer(capacity: line.utf8.count + 1)
                buf.writeString(line)
                buf.writeString("\n")
                ch.writeAndFlush(buf, promise: nil)
            }
        }
    }

    // MARK: Internal: called by HelperChannelHandler

    func handleResponse(_ data: Data) {
        guard let response = try? JSONDecoder().decode(HelperResponse.self, from: data) else {
            logger.warning("Could not decode helper response: \(String(decoding: data, as: UTF8.self).prefix(200))")
            return
        }

        guard let continuation = pendingRequests.removeValue(forKey: response.id) else {
            logger.warning("No pending request for id \(response.id)")
            return
        }

        if let err = response.error {
            continuation.resume(throwing: WaveHelperError.rpcError(code: err.code, message: err.message))
        } else if let result = response.result {
            continuation.resume(returning: result)
        } else {
            continuation.resume(returning: .null)
        }
    }

    func handleDisconnect() {
        logger.warning("Wave helper disconnected unexpectedly")
        _isConnected = false
        channel = nil

        // Fail pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: WaveHelperError.disconnected)
        }
        pendingRequests = [:]
    }
}

// MARK: - WaveHelperError

enum WaveHelperError: LocalizedError {
    case notConnected
    case disconnected
    case encodingFailed
    case rpcError(code: Int, message: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Wave helper is not connected. Open the 'Seashell Helper' widget in Wave Terminal to enable helper-block tools."
        case .disconnected:
            return "Wave helper disconnected during request."
        case .encodingFailed:
            return "Failed to encode JSON-RPC request."
        case .rpcError(let code, let message):
            return "Wave helper RPC error \(code): \(message)"
        case .timeout:
            return "Wave helper request timed out."
        }
    }
}

// MARK: - NIO channel handler (receives responses from helper)

/// Receives newline-delimited JSON responses and forwards them to the actor.
final class HelperChannelHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    // nonisolated(unsafe) is safe here: every access to `client` goes through
    // `Task { await client.someMethod() }`, which hops to the actor's executor
    // before touching any mutable state. The NIO channel callbacks never read
    // or write actor-isolated properties directly.
    nonisolated(unsafe) private let client: WaveHelperClient
    private let logger: Logger

    init(client: WaveHelperClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        guard let bytes = buf.readBytes(length: buf.readableBytes) else { return }
        let responseData = Data(bytes)
        Task {
            await client.handleResponse(responseData)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        Task {
            await client.handleDisconnect()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("Wave helper channel error: \(error)")
        context.close(promise: nil)
    }
}

// MARK: - Helper line encoder (for outbound messages to Wave helper)

private final class WaveHelperLineEncoder: MessageToByteEncoder {
    typealias OutboundIn = ByteBuffer

    func encode(data: ByteBuffer, out: inout ByteBuffer) throws {
        out.writeImmutableBuffer(data)
    }
}

// MARK: - Global shared helper client instance

/// Lazily initialised shared client. Handlers access it via `sharedWaveHelperClient`.
let sharedWaveHelperClient = WaveHelperClient()

/// Attempts to connect to the Wave helper, retrying up to `maxAttempts` times
/// with `delaySeconds` between each attempt. Returns true if connected.
func connectHelperWithRetry(maxAttempts: Int = 3, delaySeconds: UInt64 = 2) async -> Bool {
    for attempt in 1...maxAttempts {
        if await sharedWaveHelperClient.isConnected() { return true }
        await sharedWaveHelperClient.connect()
        if await sharedWaveHelperClient.isConnected() { return true }
        if attempt < maxAttempts {
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
        }
    }
    return await sharedWaveHelperClient.isConnected()
}
