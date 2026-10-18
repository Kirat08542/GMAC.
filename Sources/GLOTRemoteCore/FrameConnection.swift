import Foundation
import Network

actor FrameConnection {
    private let connection: NWConnection
    private let maxFrame: Int
    private var buffer = FrameBuffer()
    private var pending: [Envelope] = []
    private var closed = false
    private var didStart = false

    init(connection: NWConnection, maxFrame: Int) {
        self.connection = connection
        self.maxFrame = maxFrame
    }

    func ready(timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.waitReady() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw RemoteError.timeout
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    func nextEnvelope() async throws -> Envelope {
        if closed {
            throw RemoteError.closed
        }
        if !pending.isEmpty {
            return pending.removeFirst()
        }
        while pending.isEmpty {
            let chunk = try await receiveChunk()
            if chunk.isEmpty {
                continue
            }
            let frames = try buffer.append(chunk, maxFrame: maxFrame)
            for frame in frames {
                pending.append(try FrameCodec.decode(frame, maxFrame: maxFrame))
            }
        }
        return pending.removeFirst()
    }

    func send(_ envelope: Envelope) async throws {
        if closed {
            throw RemoteError.closed
        }
        let frame = try FrameCodec.encode(envelope, maxFrame: maxFrame)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = OnceGate<Void>()
                connection.send(content: frame, completion: .contentProcessed { error in
                    if let error {
                        gate.finish(continuation, result: .failure(error))
                    } else {
                        gate.finish(continuation, result: .success(()))
                    }
                })
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func cancel() {
        closed = true
        connection.cancel()
    }

    private func waitReady() async throws {
        if didStart {
            throw RemoteError.invalid("The connection already started.")
        }
        didStart = true
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = OnceGate<Void>()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.finish(continuation, result: .success(()))
                    case .failed(let error):
                        gate.finish(continuation, result: .failure(RemoteError.invalid(String(describing: error))))
                    case .cancelled:
                        gate.finish(continuation, result: .failure(RemoteError.closed))
                    case .setup, .preparing, .waiting:
                        break
                    @unknown default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private func receiveChunk() async throws -> Data {
        if closed {
            throw RemoteError.closed
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let gate = OnceGate<Data>()
                connection.receive(minimumIncompleteLength: 1, maximumLength: maxFrame) { data, _, isComplete, error in
                    if let error {
                        gate.finish(continuation, result: .failure(error))
                        return
                    }
                    if let data, !data.isEmpty {
                        gate.finish(continuation, result: .success(data))
                        return
                    }
                    if isComplete {
                        gate.finish(continuation, result: .failure(RemoteError.closed))
                        return
                    }
                    gate.finish(continuation, result: .success(Data()))
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
