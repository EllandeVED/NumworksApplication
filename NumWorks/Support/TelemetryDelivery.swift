import Foundation
import Aptabase
import Darwin

enum TelemetryMilestone: String, Codable, Sendable, Hashable {
    case firstLaunch = "first_launch"
    case secondLaunch = "second_launch"
}

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
    let milestone: TelemetryMilestone
    var displayVersion: String { "\(version) (\(build))" }

    init(version: String, build: String, mode: TelemetryBuildMode,
         milestone: TelemetryMilestone = .firstLaunch) {
        self.version = version
        self.build = build
        self.mode = mode
        self.milestone = milestone
    }

    func forMilestone(_ milestone: TelemetryMilestone) -> Self {
        Self(version: version, build: build, mode: mode, milestone: milestone)
    }

    private enum CodingKeys: String, CodingKey { case version, build, mode, milestone }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(String.self, forKey: .version)
        build = try values.decode(String.self, forKey: .build)
        mode = try values.decode(TelemetryBuildMode.self, forKey: .mode)
        // All records written before second-launch support were first_launch.
        milestone = try values.decodeIfPresent(TelemetryMilestone.self, forKey: .milestone) ?? .firstLaunch
    }
}

/// Local process-session token, continued only across our own relocation.
/// Neither this token nor the launch history is sent as an analytics identifier.
struct TelemetryLaunchSession: Sendable {
    static let environmentKey = "NUMWORKS_RELAUNCH_SESSION"
    static let current = Self(environment: ProcessInfo.processInfo.environment)
    let id: UUID

    init(environment: [String: String], fallback: UUID = UUID()) {
        id = environment[Self.environmentKey].flatMap(UUID.init(uuidString:)) ?? fallback
    }

    var relaunchEnvironment: String { "\(Self.environmentKey)=\(id.uuidString)" }

    func relaunchArguments(processID: Int32, path: String,
                           openExecutable: String = "/usr/bin/open",
                           additionalEnvironment: [String] = []) -> [String] {
        // Nothing derived from the path or environment is interpolated into shell source.
        let script = "while /bin/kill -0 \"$1\" >/dev/null 2>&1; do /bin/sleep 0.1; done; "
            + "target=\"$2\"; session=\"$3\"; launcher=\"$4\"; shift 4; "
            + "exec \"$launcher\" --env \"$session\" \"$@\" \"$target\""
        return ["-c", script, "numworks-relaunch", String(processID), path, relaunchEnvironment, openExecutable]
            + additionalEnvironment.flatMap { ["--env", $0] }
    }
}

struct TelemetryLaunchHistory: Codable, Sendable {
    let identity: TelemetryMilestoneIdentity // Always the first-launch identity for this build.
    let consentGeneration: Int
    let firstSession: UUID
    var secondSession: UUID?
}

struct TelemetryQualifyingLaunch: Sendable {
    let session: UUID
    let secondLaunch: PendingTelemetryMilestone
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
    var launches: [TelemetryLaunchHistory] = []

    init(formatVersion: Int = 1, pending: [PendingTelemetryMilestone] = [],
         acknowledged: [TelemetryAcknowledgement] = [], launches: [TelemetryLaunchHistory] = []) {
        self.formatVersion = formatVersion
        self.pending = pending
        self.acknowledged = acknowledged
        self.launches = launches
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, pending, acknowledged, launches }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        pending = try values.decode([PendingTelemetryMilestone].self, forKey: .pending)
        acknowledged = try values.decode([TelemetryAcknowledgement].self, forKey: .acknowledged)
        // Do not infer a second use from an old acknowledgement or legacy preference.
        launches = try values.decodeIfPresent([TelemetryLaunchHistory].self, forKey: .launches) ?? []
    }
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
    private let ownership = TelemetryStoreOwnership()
    var file: URL { directory.appendingPathComponent("milestones-v1.json") }

    init(directory: URL) { self.directory = directory }

    static func applicationStore() -> Self? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return Self(directory: base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ellandeved.NumWorks")
            .appendingPathComponent("Telemetry", isDirectory: true))
    }

    func load() throws -> TelemetryOutboxSnapshot {
        try ownership.acquire(directory: directory)
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
        try ownership.acquire(directory: directory)
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

/// One live process owns the read/modify/write state. Another copy backs off
/// instead of overwriting a stale snapshot or reporting the same milestone.
private final class TelemetryStoreOwnership: @unchecked Sendable {
    enum OwnershipError: Error { case unavailable(Int32) }
    private let lock = NSLock()
    private var descriptor: Int32 = -1

    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    func acquire(directory: URL) throws {
        try lock.withLock {
            guard descriptor < 0 else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let path = directory.appendingPathComponent("milestones.lock").path
            let opened = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard opened >= 0 else { throw OwnershipError.unavailable(errno) }
            guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
                let failure = errno
                Darwin.close(opened)
                throw OwnershipError.unavailable(failure)
            }
            descriptor = opened
        }
    }
}
