import XCTest
@testable import LoggingLoki
import struct Logging.Logger

class TestSession: LokiSession {
    var logs: [LokiLog]?
    var labels: LokiLabels?
    var headers: [String: String]?

    func send(_ logs: [LokiLog], with labels: LokiLabels, url: URL, headers: [String: String], completion: @escaping (Result<StatusCode, Error>) -> ()) {
        self.logs = logs
        self.labels = labels
        self.headers = headers
    }
}

final class LoggingLokiTests: XCTestCase {
    func testLog() throws {
        let expectedLogMessage = "Testing swift-log-loki"
        let expectedSource = "swift-log"
        let expectedFile = "TestFile.swift"
        let expectedFunction = "testFunction(_:)"
        let expectedLine: UInt = 42
        let expectedService = "test.swift-log"

        let handler = LokiLogHandler(label: expectedService, lokiURL: URL(string: "http://localhost:3100")!, session: TestSession())
        handler.log(level: .error, message: "\(expectedLogMessage)", metadata: ["log": "swift"], source: expectedSource, file: expectedFile, function: expectedFunction, line: expectedLine)

        guard let session = handler.session as? TestSession else {
            XCTFail("Could not cast the Handler's Session to TestSession")
            return
        }

        guard let firstLog = session.logs?.first else {
            XCTFail("Could not get first log from Session")
            return
        }

        XCTAssert(firstLog.message.contains(expectedLogMessage))
        XCTAssert(firstLog.message.contains(Logger.Level.error.rawValue.uppercased()))
        XCTAssertNotNil(firstLog.timestamp)
        XCTAssert(session.labels?.contains(where: { key, value in
            value == expectedSource && key == "source"
        }) ?? false)
        XCTAssert(session.labels?.contains(where: { key, value in
            value == expectedFile && key == "file"
        }) ?? false)
        XCTAssert(session.labels?.contains(where: { key, value in
            value == expectedFunction && key == "function"
        }) ?? false)
        XCTAssert(session.labels?.contains(where: { key, value in
            value == String(expectedLine) && key == "line"
        }) ?? false)
        XCTAssert(session.labels?.contains(where: { key, value in
            value == expectedService && key == "service"
        }) ?? false)
    }
}
