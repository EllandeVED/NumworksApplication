import Foundation
import Aptabase

enum TelemetryBuildMode: String, Codable, Sendable, Hashable {
    case debug, release
    static var current: Self {
#if DEBUG
        .debug
#else
        .release
#endif
    }
}

struct TelemetryMilestoneIdentity: Codable, Hashable, Sendable {
    let version: String
    let build: String
    let mode: TelemetryBuildMode
    var displayVersion: String { "\(version) (\(build))" }
}

struct PendingTelemetryMilestone: Codable, Sendable {
    let id: UUID
    let identity: TelemetryMilestoneIdentity
    // Local consent fence. Never included in the event sent to Aptabase.
    let consentGeneration: Int
    let event: PreparedEvent
    var attempts = 0
    var nextAttemptAt: Date
    var rejected = false
    var lastHTTPStatus: Int?
}

struct TelemetryAcknowledgement: Codable, Sendable {
    enum Kind: String, Codable { case accepted, legacySkip }
    let identity: TelemetryMilestoneIdentity
    let recordID: UUID?
    let kind: Kind
}

struct TelemetryOutboxSnapshot: Codable, Sendable {
    var formatVersion = 1
    var pending: [PendingTelemetryMilestone] = []
    var acknowledged: [TelemetryAcknowledgement] = []
}

protocol TelemetryPersisting: Sendable {
    func load() throws -> TelemetryOutboxSnapshot
    func save(_ snapshot: TelemetryOutboxSnapshot) throws
}

protocol TelemetrySending: Sendable {
    func send(_ event: PreparedEvent) async -> EventDeliveryResult
}

struct AptabaseMilestoneSender: TelemetrySending {
    func send(_ event: PreparedEvent) async -> EventDeliveryResult {
        await Aptabase.shared.sendPreparedEvent(event)
    }
}

protocol TelemetryClock: Sendable {
    func now() -> Date
    func sleep(until date: Date) async throws
}

struct SystemTelemetryClock: TelemetryClock {
    func now() -> Date { Date() }
    func sleep(until date: Date) async throws {
        // Chunk long Retry-After delays so conversion to nanoseconds cannot overflow.
        while date > Date() {
            try Task.checkCancellation()
            let seconds = min(date.timeIntervalSinceNow, 60)
            if seconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }
}

struct TelemetryFileStore: TelemetryPersisting {
    enum StoreError: Error { case unsupportedFormat }
    let directory: URL
    var file: URL { directory.appendingPathComponent("milestones-v1.json") }

    static func applicationStore() -> Self? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return Self(directory: base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ellandeved.NumWorks")
            .appendingPathComponent("Telemetry", isDirectory: true))
    }

    func load() throws -> TelemetryOutboxSnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return TelemetryOutboxSnapshot()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let value = try decoder.decode(TelemetryOutboxSnapshot.self, from: data)
        guard value.formatVersion == 1 else { throw StoreError.unsupportedFormat }
        return value
    }

    func save(_ snapshot: TelemetryOutboxSnapshot) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
