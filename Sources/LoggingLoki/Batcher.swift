import Foundation

final actor Batcher {
    private let session: LokiSession
    private let headers: [String: String]
    private let auth: LokiAuth

    private let lokiURL: URL
    private let sendDataAsJSON: Bool

    private let batchSize: Int
    let maxBatchTimeInterval: TimeInterval?

    private var timer: Task<Void, Error>?

    var batch: Batch?

    init(session: LokiSession,
         auth: LokiAuth,
         headers: [String: String],
         lokiURL: URL,
         sendDataAsJSON: Bool,
         batchSize: Int,
         maxBatchTimeInterval: TimeInterval?)
    {
        self.session = session
        self.auth = auth
        self.headers = headers
        self.lokiURL = lokiURL
        self.sendDataAsJSON = sendDataAsJSON
        self.batchSize = batchSize
        self.maxBatchTimeInterval = maxBatchTimeInterval
    }

    func addEntryToBatch(_ log: LokiLog, with labels: LokiLabels) {
        if var batch {
            batch.addEntry(log, with: labels)
            self.batch = batch
        } else {
            var batch = Batch(entries: [])
            batch.addEntry(log, with: labels)
            self.batch = batch
        }
        if let batch, batch.totalLogEntries >= batchSize {
            sendBatch()
        } else if timer == nil, let maxBatchTimeInterval {
            timer = Task { [weak self] in
                try await Task.sleep(nanoseconds: UInt64(maxBatchTimeInterval * 1_000_000_000))
                await self?.sendBatch()
            }
        }
    }

    /// Sends the pending batch, if any, and waits until the request completes.
    func flush() async {
        guard let batch = takeBatch() else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            send(batch) { continuation.resume() }
        }
    }

    private func sendBatch() {
        guard let batch = takeBatch() else { return }
        send(batch) {}
    }

    private func takeBatch() -> Batch? {
        guard let batch else { return nil }
        // a stale timer would otherwise cut the next batch short
        timer?.cancel()
        timer = nil
        self.batch = nil
        return batch
    }

    private func send(_ batch: Batch, completion: @escaping () -> Void) {
        session.send(batch, url: lokiURL, headers: headers, auth: auth, sendAsJSON: sendDataAsJSON) { result in
            if case let .failure(failure) = result {
                debugPrint(failure)
            }
            completion()
        }
    }
}
