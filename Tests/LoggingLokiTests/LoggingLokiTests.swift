import XCTest
@testable import LoggingLoki
import struct Logging.Logger

final class TestSession: LokiSession, @unchecked Sendable {
    private let lock = NSLock()
    private var _batches: [Batch] = []

    var logs: [LokiLog]? {
        lock.lock(); defer { lock.unlock() }
        return _batches.first?.entries.first?.logEntries
    }

    var labels: LokiLabels? {
        lock.lock(); defer { lock.unlock() }
        return _batches.first?.entries.first?.labels
    }

    func send(_ batch: Batch,
              url: URL,
              headers: [String: String],
              auth: LokiAuth,
              sendAsJSON: Bool = false,
              completion: @escaping (Result<StatusCode, Error>) -> Void) {
        lock.lock()
        _batches.append(batch)
        lock.unlock()
        completion(.success(204))
    }
}

final class LoggingLokiTests: XCTestCase {
    let expectedLogMessage = "Testing swift-log-loki"
    let expectedSource = "swift-log"
    let expectedFile = "TestFile.swift"
    let expectedFunction = "testFunction(_:)"
    let expectedLine: UInt = 42

    /// Batchers are cached per label, so every test needs its own.
    private func uniqueLabel(_ function: String = #function) -> String {
        "test.\(function).\(UUID().uuidString)"
    }

    private func log(_ handler: LokiLogHandler) {
        handler.log(level: .error, message: "\(expectedLogMessage)", metadata: ["log": "swift"], source: expectedSource, file: expectedFile, function: expectedFunction, line: expectedLine)
    }

    /// `log` hands entries to the batcher asynchronously.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    func testLog() async throws {
        let session = TestSession()
        let handler = LokiLogHandler(label: uniqueLabel(), lokiURL: URL(string: "http://localhost:3100")!, batchSize: 1, session: session)
        log(handler)
        try await settle()
        checkIfLogExists(in: session)
    }

    func testLogWithBiggerBatchSize() async throws {
        let session = TestSession()
        let handler = LokiLogHandler(label: uniqueLabel(), lokiURL: URL(string: "http://localhost:3100")!, batchSize: 3, session: session)
        log(handler)
        log(handler)
        try await settle()
        XCTAssertNil(session.logs?.first)
        log(handler)
        try await settle()
        checkIfLogExists(in: session)
    }

    func testLogWithMaxInterval() async throws {
        let session = TestSession()
        let handler = LokiLogHandler(label: uniqueLabel(), lokiURL: URL(string: "http://localhost:3100")!, maxBatchTimeInterval: 1, session: session)
        log(handler)
        try await settle()
        XCTAssertNil(session.logs?.first)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        checkIfLogExists(in: session)
    }

    func testPublicInitPassesMaxBatchTimeInterval() async {
        let handler = LokiLogHandler(label: uniqueLabel(), lokiURL: URL(string: "http://localhost:3100")!, maxBatchTimeInterval: 5)
        let interval = await handler.batcher.maxBatchTimeInterval
        XCTAssertEqual(interval, 5)
    }

    func testFlushSendsPendingBatch() async throws {
        let session = TestSession()
        let handler = LokiLogHandler(label: uniqueLabel(), lokiURL: URL(string: "http://localhost:3100")!, maxBatchTimeInterval: nil, session: session)
        log(handler)
        try await settle()
        XCTAssertNil(session.logs?.first)
        await LokiLogHandler.flush()
        checkIfLogExists(in: session)
    }

    func checkIfLogExists(in session: TestSession) {
        guard let firstLog = session.logs?.first else {
            XCTFail("Could not get first log from Session")
            return
        }

        XCTAssert(firstLog.message.contains(expectedLogMessage))
        XCTAssert(firstLog.message.contains(Logger.Level.error.rawValue.uppercased()))
        XCTAssertNotNil(firstLog.timestamp)
        XCTAssertEqual(session.labels?["source"], expectedSource)
        XCTAssertEqual(session.labels?["file"], expectedFile)
        XCTAssertEqual(session.labels?["function"], expectedFunction)
        XCTAssertEqual(session.labels?["line"], String(expectedLine))
    }
}
