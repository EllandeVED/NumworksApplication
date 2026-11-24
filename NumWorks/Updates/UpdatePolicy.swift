import Foundation

/// Attempts survive restarts. Failed or interrupted requests retry at most hourly.
struct UpdateCheckSchedule {
    static let successInterval: TimeInterval = 24 * 60 * 60
    static let retryInterval: TimeInterval = 60 * 60
    private static let nextCheckKey = "NumWorksNextAutomaticUpdateCheck"
    private static let lastSuccessKey = "NumWorksLastSuccessfulUpdateCheck"

    private(set) var nextAutomaticCheckAt: Date?
    private(set) var lastSuccessfulCheckAt: Date?

    init(nextAutomaticCheckAt: Date? = nil, lastSuccessfulCheckAt: Date? = nil) {
        self.nextAutomaticCheckAt = nextAutomaticCheckAt
        self.lastSuccessfulCheckAt = lastSuccessfulCheckAt
    }

    init(defaults: UserDefaults, previousAttempt: Date?) {
        nextAutomaticCheckAt = defaults.object(forKey: Self.nextCheckKey) as? Date
        lastSuccessfulCheckAt = defaults.object(forKey: Self.lastSuccessKey) as? Date
        // Sparkle's old timestamp records attempts, including failures.
        if nextAutomaticCheckAt == nil {
            nextAutomaticCheckAt = previousAttempt?.addingTimeInterval(Self.retryInterval)
        }
    }

    func delay(at now: Date) -> TimeInterval {
        // A clock change must not postpone checks indefinitely.
        let interval = nextAutomaticCheckAt?.timeIntervalSince(now) ?? 0
        return interval > Self.successInterval ? 0 : max(0, interval)
    }

    mutating func beganAttempt(at now: Date) {
        nextAutomaticCheckAt = now.addingTimeInterval(Self.retryInterval)
    }

    mutating func completed(succeeded: Bool, at now: Date) {
        if succeeded { lastSuccessfulCheckAt = now }
        nextAutomaticCheckAt = now.addingTimeInterval(
            succeeded ? Self.successInterval : Self.retryInterval)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(nextAutomaticCheckAt, forKey: Self.nextCheckKey)
        defaults.set(lastSuccessfulCheckAt, forKey: Self.lastSuccessKey)
    }
}

/// Serializes the move-first prompt independently of the capped startup reminder.
struct UpdateMovePromptState {
    var startupComplete = false
    private(set) var pendingVersion: String?
    private(set) var isPresenting = false

    mutating func request(version: String) {
        guard !isPresenting else { return }
        pendingVersion = version
    }

    mutating func takePending(sessionInProgress: Bool) -> String? {
        guard startupComplete, !sessionInProgress, !isPresenting,
              let version = pendingVersion else { return nil }
        pendingVersion = nil
        isPresenting = true
        return version
    }

    mutating func finishedPresenting() { isPresenting = false }
}

enum UpdateRelaunch {
    static let environmentKey = "NUMWORKS_CHECK_AFTER_MOVE"
    static let environment = "\(environmentKey)=1"

    static func requested(environment: [String: String], isInstalled: Bool) -> Bool {
        isInstalled && environment[environmentKey] == "1"
    }
}
