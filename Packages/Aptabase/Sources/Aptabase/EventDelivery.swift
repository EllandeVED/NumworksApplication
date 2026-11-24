import Foundation

/// Result of submitting a prepared event to Aptabase.
///
/// A completed `flush()` is not acceptance: empty queues, 4xx discards and
/// caught 5xx all return from `flush` without throwing.
public enum EventDeliveryResult: Sendable, Equatable {
    case accepted(statusCode: Int)
    case retryableFailure(statusCode: Int?, retryAfter: TimeInterval?)
    case rejected(statusCode: Int?, diagnostic: String)
    case cancelled
}

public enum EventDelivery {
    /// Classifies a transport outcome. 2xx is the only acceptance.
    public static func interpret(
        statusCode: Int?,
        error: Error?,
        retryAfterHeader: String?,
        now: Date = Date()
    ) -> EventDeliveryResult {
        if let error, isCancellation(error) {
            return .cancelled
        }

        if let statusCode {
            if (200..<300).contains(statusCode) {
                return .accepted(statusCode: statusCode)
            }
            if statusCode == 429 || statusCode == 408 || statusCode >= 500 {
                return .retryableFailure(
                    statusCode: statusCode,
                    retryAfter: parseRetryAfter(retryAfterHeader, now: now))
            }
            if (400..<500).contains(statusCode) {
                return .rejected(
                    statusCode: statusCode,
                    diagnostic: "HTTP \(statusCode)")
            }
            return .retryableFailure(
                statusCode: statusCode,
                retryAfter: parseRetryAfter(retryAfterHeader, now: now))
        }

        if error != nil {
            return .retryableFailure(statusCode: nil, retryAfter: parseRetryAfter(retryAfterHeader, now: now))
        }

        return .retryableFailure(statusCode: nil, retryAfter: nil)
    }

    public static func parseRetryAfter(_ header: String?, now: Date) -> TimeInterval? {
        guard let raw = header?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw) {
            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }
        if let date = httpDateFormatter.date(from: raw) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let urlError = error as? URLError
        if urlError?.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

/// Immutable Aptabase event, encoded with the SDK session and system metadata.
public struct PreparedEvent: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var sessionId: String
    public var eventName: String
    public var systemProps: Event.SystemProps
    public var props: [String: AnyCodableValue]?

    public init(event: Event) {
        timestamp = event.timestamp
        sessionId = event.sessionId
        eventName = event.eventName
        systemProps = event.systemProps
        props = event.props
    }

    func asEvent() -> Event {
        Event(
            timestamp: timestamp,
            sessionId: sessionId,
            eventName: eventName,
            systemProps: systemProps,
            props: props)
    }
}
