import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// ``LokiLogHandler`` is a logging backend for `Logging`.
public struct LokiLogHandler: LogHandler {

    internal let session: LokiSession

    private let lokiURL: URL
    private let sendDataAsJSON: Bool

    private let batchSize: Int
    private let maxBatchTimeInterval: TimeInterval?
    private let colorizeLevel: Bool

    private let batcher: Batcher

    /// The service label for the log handler instance.
    ///
    /// This value will be sent to Grafana Loki as the `service` label.
    public var label: String

    /// This initializer is only used internally and for running Unit Tests.
    internal init(label: String,
                  lokiURL: URL,
                  headers: [String: String] = [:],
                  sendAsJSON: Bool = false,
                  colorizeLevel: Bool = true,
                  batchSize: Int = 10,
                  maxBatchTimeInterval: TimeInterval? = 5 * 60,
                  session: LokiSession) {
        self.label = label
        #if os(Linux) // this needs to be explicitly checked, otherwise the build will fail on linux
        self.lokiURL = lokiURL.appendingPathComponent("/loki/api/v1/push")
        #else
        if #available(macOS 13.0, *) {
            self.lokiURL = lokiURL.appending(path: "/loki/api/v1/push")
        } else {
            self.lokiURL = lokiURL.appendingPathComponent("/loki/api/v1/push")
        }
        #endif
        self.sendDataAsJSON = sendAsJSON
        self.batchSize = batchSize
        self.maxBatchTimeInterval = maxBatchTimeInterval
        self.session = session
        self.colorizeLevel = colorizeLevel
        self.batcher = Batcher(session: self.session,
                               headers: headers,
                               lokiURL: self.lokiURL,
                               sendDataAsJSON: self.sendDataAsJSON,
                               batchSize: self.batchSize,
                               maxBatchTimeInterval: self.maxBatchTimeInterval)
    }

    /// Initializes a ``LokiLogHandler`` with the provided parameters.
    ///
    /// The handler will send all logs it captures to the Grafana Loki instance the client has provided. If a request fails it will send a debugPrint to the the console.
    /// The handler will not send the request again. It's basically fire and forget.
    ///
    /// ```swift
    /// LoggingSystem.bootstrap {
    ///     LokiLogHandler(
    ///         label: $0,
    ///         lokiURL: URL(string: "http://localhost:3100")!
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - label: client supplied string describing the logger. Should be unique but not enforced
    ///   - lokiURL: client supplied Grafana Loki base URL
    ///   - headers: These headers will be added to all requests sent to Grafana Loki.
    ///   - sendAsJSON: Indicates if the logs should be sent to Loki as JSON.
    ///                 This should not be required in most cases. By default this is false.
    ///                 Logs will instead be sent as snappy compressed protobuf,
    ///                 which is much smaller and should therefor use less bandwidth.
    ///                 This is also the recommended way by Loki.
    ///   - batchSize: The size of a single batch of data. Once this limit is exceeded the batch of logs will be sent to Loki.
    ///                This is 10 log entries by default.
    ///   - maxBatchTimeInterval: The maximum amount of time in seconds to elapse until a batch is sent to Loki.
    ///                           This limit is set to 5 minutes by default. If a batch is not "full" after the end of the interval, it will be sent to Loki.
    ///                           The option should prevent leaving logs in memory for too long without sending them.
    public init(label: String,
                lokiURL: URL,
                headers: [String: String] = [:],
                sendAsJSON: Bool = false,
                colorizeLevel: Bool = true,
                batchSize: Int = 10,
                maxBatchTimeInterval: TimeInterval? = 5 * 60) {
        self.init(label: label,
                  lokiURL: lokiURL,
                  headers: headers,
                  sendAsJSON: sendAsJSON,
                  colorizeLevel: colorizeLevel,
                  batchSize: batchSize,
                  session: URLSession(configuration: .ephemeral))
    }

    /// This method is called when a `LogHandler` must emit a log message. There is no need for the `LogHandler` to
    /// check if the `level` is above or below the configured `logLevel` as `Logger` already performed this check and
    /// determined that a message should be logged.
    ///
    /// - parameters:
    ///     - level: The log level the message was logged at.
    ///     - message: The message to log. To obtain a `String` representation call `message.description`.
    ///     - metadata: The metadata associated to this log message.
    ///     - source: The source where the log message originated, for example the logging module.
    ///     - file: The file the log message was emitted from.
    ///     - function: The function the log line was emitted from.
    ///     - line: The line the log message was emitted from.
    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let prettyMetadata = metadata?.isEmpty ?? true ? prettyMetadata : prettify(self.metadata.merging(metadata!, uniquingKeysWith: { _, new in new }))

        let labels: LokiLabels = ["service": label, "source": source, "file": file, "function": function, "line": String(line)]
        let timestamp = Date()
        var levelString = "[\(level.rawValue.uppercased())]"
        if colorizeLevel {
            levelString = levelString.consoleStyle(level.style)
        }
        let message = "\(levelString)\(prettyMetadata.map { " \($0)"} ?? "") \(message)"
        let log = (timestamp, message)

        batcher.addEntryToBatch(log, with: labels)
        batcher.sendBatchIfNeeded()
    }

    /// Add, remove, or change the logging metadata.
    ///
    /// - note: `LogHandler`s must treat logging metadata as a value type. This means that the change in metadata must
    ///         only affect this very `LogHandler`.
    ///
    /// - parameters:
    ///    - metadataKey: The key for the metadata item
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        }
        set(newValue) {
            metadata[key] = newValue
        }
    }

    private var prettyMetadata: String?

    /// Get or set the entire metadata storage as a dictionary.
    ///
    /// - note: `LogHandler`s must treat logging metadata as a value type. This means that the change in metadata must
    ///         only affect this very `LogHandler`.
    public var metadata = Logger.Metadata() {
        didSet {
            prettyMetadata = prettify(metadata)
        }
    }

    /// Get or set the configured log level.
    ///
    /// - note: `LogHandler`s must treat the log level as a value type. This means that the change in metadata must
    ///         only affect this very `LogHandler`. It is acceptable to provide some form of global log level override
    ///         that means a change in log level on a particular `LogHandler` might not be reflected in any
    ///        `LogHandler`.
    public var logLevel: Logger.Level = .info

    private func prettify(_ metadata: Logger.Metadata) -> String? {
        !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : nil
    }
}
