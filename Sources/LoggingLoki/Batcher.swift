import Foundation

final actor Batcher {
    
    private let session: LokiSession
    private let headers: [String: String]
    private let auth: LokiAuth

    private let lokiURL: URL
    private let sendDataAsJSON: Bool

    private let batchSize: Int
    private let maxBatchTimeInterval: TimeInterval

    private var currentTimer: Timer? = nil
    private var timer: Task<Void, Error>?

    var batch: Batch? = nil

    init(session: LokiSession,
         auth: LokiAuth,
         headers: [String: String],
         lokiURL: URL,
         sendDataAsJSON: Bool,
         batchSize: Int,
         maxBatchTimeInterval: TimeInterval
    ) {
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
        } else if timer == nil {
            timer = Task { [weak self, maxBatchTimeInterval] in
                try await Task.sleep(nanoseconds: UInt64(maxBatchTimeInterval * 1_000_000_000))
                await self?.sendBatch()
            }
        }
    }

    private func sendBatch() {
        guard let batch else { return }
        timer = nil
        self.batch = nil
        session.send(batch, url: lokiURL, headers: headers, auth: auth, sendAsJSON: sendDataAsJSON) { result in
            if case .failure(let failure) = result {
                debugPrint(failure)
            }
        }
    }
}
