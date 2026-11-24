import Foundation

/// Synchronous consent fence shared by enqueue tasks and HTTP requests.
/// Cancels only requests made by this client; never invalidates URLSession.shared.
final class TrackingState: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    private var epoch: UInt64 = 0
    private var requests: [UUID: Task<(Data, URLResponse), Error>] = [:]

    func currentEpoch() -> UInt64? { lock.withLock { enabled ? epoch : nil } }
    func revision() -> UInt64 { lock.withLock { epoch } }
    func accepts(_ value: UInt64) -> Bool { lock.withLock { enabled && epoch == value } }

    func pause() {
        let tasks = lock.withLock { () -> [Task<(Data, URLResponse), Error>] in
            enabled = false
            epoch &+= 1
            let current = Array(requests.values)
            requests.removeAll()
            return current
        }
        tasks.forEach { $0.cancel() }
    }

    @discardableResult
    func resume(ifRevision value: UInt64) -> Bool {
        lock.withLock {
            guard epoch == value else { return false }
            enabled = true
            return true
        }
    }

    func register(id: UUID, epoch value: UInt64,
                  operation: @escaping @Sendable () async throws -> (Data, URLResponse))
        -> Task<(Data, URLResponse), Error>? {
        lock.withLock {
            guard enabled, epoch == value else { return nil }
            let task = Task { try await operation() }
            requests[id] = task
            return task
        }
    }

    func remove(_ id: UUID) { lock.withLock { _ = requests.removeValue(forKey: id) } }
}

final class TrackingSession: URLSessionProtocol, @unchecked Sendable {
    let underlying: URLSessionProtocol
    let state: TrackingState
    init(underlying: URLSessionProtocol, state: TrackingState) {
        self.underlying = underlying
        self.state = state
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard let epoch = state.currentEpoch() else { throw CancellationError() }
        let id = UUID()
        guard let task = state.register(id: id, epoch: epoch, operation: { [underlying] in
            try await underlying.data(for: request)
        }) else { throw CancellationError() }
        defer { state.remove(id) }
        return try await withTaskCancellationHandler(operation: {
            let result = try await task.value
            try Task.checkCancellation()
            guard state.accepts(epoch) else { throw CancellationError() }
            return result
        }, onCancel: { task.cancel() })
    }
}
