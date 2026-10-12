import Foundation
import MQTTNIO
import NIOCore

public actor MQTTConnection {
    public enum Event: Sendable {
        case connected
        case disconnected(String?)
        case message(topic: String, payload: Data)
    }

    private var client: MQTTClient?
    private var publishTask: Task<Void, Never>?
    private var continuation: AsyncStream<Event>.Continuation?
    private let publishListenerName = UUID().uuidString

    public init() {}

    public func events() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        self.continuation = continuation
        return stream
    }

    public func start(
        host: String,
        port: Int,
        username: String,
        password: String,
        topics: [String]
    ) async throws {
        await stop()

        let configuration = MQTTClient.Configuration(
            version: .v3_1_1,
            keepAliveInterval: .seconds(60),
            connectTimeout: .seconds(15),
            userName: username,
            password: password,
            useSSL: true,
            tlsConfiguration: .ts(TSTLSConfiguration()),
            sniServerName: host
        )
        let client = MQTTClient(
            host: host,
            port: port,
            identifier: "openmiraie-\(UUID().uuidString.prefix(12))",
            eventLoopGroupProvider: .createNew,
            configuration: configuration
        )
        self.client = client

        try await client.connect(cleanSession: true)

        let subscriptions = topics.map { MQTTSubscribeInfo(topicFilter: $0, qos: .atMostOnce) }
        _ = try await client.subscribe(to: subscriptions)
        continuation?.yield(.connected)

        let listener = client.createPublishListener()
        publishTask = Task { [weak self] in
            for await result in listener {
                guard let self else { break }
                switch result {
                case .success(let info):
                    let buffer = info.payload
                    let data = buffer.getData(
                        at: buffer.readerIndex,
                        length: buffer.readableBytes
                    ) ?? Data()
                    await self.yield(.message(topic: info.topicName, payload: data))
                case .failure(let error):
                    await self.yield(.disconnected(error.localizedDescription))
                    return
                }
            }
            await self?.yield(.disconnected(nil))
        }

        client.addCloseListener(named: publishListenerName) { [weak self] _ in
            Task { await self?.yield(.disconnected("connection closed")) }
        }
    }

    public func publish(topic: String, payload: Data) async throws {
        guard let client else {
            throw MQTTConnectionError.notConnected
        }
        var buffer = ByteBufferAllocator().buffer(capacity: payload.count)
        buffer.writeBytes(payload)
        try await client.publish(to: topic, payload: buffer, qos: .atLeastOnce, retain: false)
    }

    public func stop() async {
        publishTask?.cancel()
        publishTask = nil
        if let client {
            client.removeCloseListener(named: publishListenerName)
            try? await client.shutdown()
        }
        client = nil
    }

    private func yield(_ event: Event) {
        continuation?.yield(event)
    }
}

public enum MQTTConnectionError: Error, LocalizedError {
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "mqtt not connected"
        }
    }
}
