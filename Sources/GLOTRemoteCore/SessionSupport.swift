import Foundation

public struct SessionSnapshot: Sendable, Equatable {
    public var state: LinkState
    public var note: String

    public init(state: LinkState, note: String = "") {
        self.state = state
        self.note = note
    }
}

public enum LinkState: Sendable, Equatable {
    case idle
    case listening
    case connecting
    case pairing(code: String, expires: Date)
    case authenticating
    case ready(peerName: String)
    case reconnecting(attempt: Int)
    case failed(String)
}

public struct MessageDeduper: Sendable {
    private var order: [UUID] = []
    private var seen = Set<UUID>()
    private let capacity: Int

    public init(capacity: Int = 512) {
        self.capacity = capacity
    }

    /// Returns false when the identifier was already accepted.
    public mutating func insert(_ id: UUID) -> Bool {
        if seen.contains(id) {
            return false
        }
        seen.insert(id)
        order.append(id)
        if order.count > capacity, let removed = order.first {
            order.removeFirst()
            seen.remove(removed)
        }
        return true
    }
}

public struct RateLimiter: Sendable {
    private var windowStart: ContinuousClock.Instant?
    private var count = 0

    public init() {}

    public mutating func allow(now: ContinuousClock.Instant, limit: Int, window: Duration) -> Bool {
        if let windowStart, now < windowStart.advanced(by: window) {
            if count >= limit {
                return false
            }
            count += 1
            return true
        }
        windowStart = now
        count = 1
        return true
    }
}

enum Inbound: Sendable {
    case message(Envelope)
    case decision(Bool)
    case timeout(UUID)
    case closed(String)
}

final class SessionQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Inbound] = []
    private var waiters: [CheckedContinuation<Inbound, Never>] = []
    private var finished = false

    func push(_ event: Inbound) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        if buffer.count > 64 {
            finished = true
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            for waiter in pending {
                waiter.resume(returning: .closed("Too many queued messages."))
            }
            return
        }
        let waiter = waiters.isEmpty ? nil : waiters.removeFirst()
        if waiter == nil {
            buffer.append(event)
        }
        lock.unlock()
        waiter?.resume(returning: event)
    }

    func next() async -> Inbound {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume(returning: .closed("The connection closed."))
                return
            }
            if buffer.isEmpty {
                waiters.append(continuation)
                lock.unlock()
            } else {
                let item = buffer.removeFirst()
                lock.unlock()
                continuation.resume(returning: item)
            }
        }
    }

    func finish(_ reason: String) {
        lock.lock()
        finished = true
        let pending = waiters
        waiters.removeAll()
        buffer.removeAll()
        lock.unlock()
        for waiter in pending {
            waiter.resume(returning: .closed(reason))
        }
    }
}

final class OnceGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func finish(_ continuation: CheckedContinuation<Value, Error>, result: sending Result<Value, Error>) {
        let resume: Bool = {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }()
        guard resume else { return }
        continuation.resume(with: result)
    }
}
