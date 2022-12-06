import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// ``LokiLogHandler`` is a logging backend for `Logging`.
public struct LokiLogHandler: LogHandler {

    internal let session: LokiSession

    private var lokiURL: URL
    private let headers: [String: String]

    /// The service label for the log handler instance.
    ///
    /// This value will be sent to Grafana Loki as the `service` label.
    public var label: String

    internal init(label: String, lokiURL: URL, headers: [String: String] = [:], session: LokiSession) {
        self.label = label
        #if os(Linux)
        self.lokiURL = lokiURL.appendingPathComponent("/loki/api/v1/push")
        #else
        if #available(macOS 13.0, *) {
            self.lokiURL = lokiURL.appending(path: "/loki/api/v1/push")
        } else {
            self.lokiURL = lokiURL.appendingPathComponent("/loki/api/v1/push")
        }
        #endif
        self.session = session
        self.headers = headers
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
    ///   - headers: additional headers for logger requests
    public init(label: String, lokiURL: URL, headers: [String: String] = [:]) {
        self.init(
            label: label,
            lokiURL: lokiURL,
            headers: headers,
            session: URLSession(configuration: .ephemeral)
        )
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
        var metadata = self.metadata.merging(metadata ?? [:], uniquingKeysWith: { $0.merging($1) })
        var labels = metadata.lokiLabels
        metadata.lokiLabels = [:]

        labels.merge(
            [
                "level": level.rawValue,
                "service": label,
                "source": source,
                "file": file,
                "function": function,
                "line": String(line)
            ]
        ) { metadata, _ in
            metadata
        }
        let timestamp = Date()
        let message = "[\(level.rawValue.uppercased())] \(metadata.isEmpty ? "" : prettify(metadata) + " ")\(message)"

        session.send((timestamp, message), with: labels, url: lokiURL, headers: headers) { result in
            if case .failure(let failure) = result {
                debugPrint(failure.localizedDescription)
            }
        }
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

    /// Get or set the entire metadata storage as a dictionary.
    ///
    /// - note: `LogHandler`s must treat logging metadata as a value type. This means that the change in metadata must
    ///         only affect this very `LogHandler`.
    public var metadata = Logger.Metadata()

    /// Get or set the configured log level.
    ///
    /// - note: `LogHandler`s must treat the log level as a value type. This means that the change in metadata must
    ///         only affect this very `LogHandler`. It is acceptable to provide some form of global log level override
    ///         that means a change in log level on a particular `LogHandler` might not be reflected in any
    ///        `LogHandler`.
    public var logLevel: Logger.Level = .info

    private func prettify(_ metadata: Logger.Metadata) -> String {
        metadata.map { "\($0)=\($1)" }.joined(separator: " ")
    }

}

public extension LokiLogHandler {
    
    
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
    ///   - user: client supplied Grafana Loki user name
    ///   - password: client supplied Grafana Loki user password
    init(label: String, lokiURL: URL, user: String, password: String) {
        let string = "\(user):\(password)".data(using: .utf8)?.base64EncodedString() ?? "\(user):\(password)"
        self.init(
            label: label,
            lokiURL: lokiURL,
            headers: ["Authorization": "Basic \(string)"]
        )
    }
}
