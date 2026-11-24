import Foundation
import Testing
import Sparkle
@testable import NumWorks

@Suite(.serialized)
struct UpdateTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func firstAutomaticCheckIsDue() {
        #expect(UpdateCheckSchedule().delay(at: now) == 0)
    }

    @Test func failedCheckRetriesHourlyWithoutBecomingASuccess() {
        var schedule = UpdateCheckSchedule()
        schedule.beganAttempt(at: now)
        schedule.completed(succeeded: false, at: now.addingTimeInterval(20))
        #expect(schedule.lastSuccessfulCheckAt == nil)
        #expect(schedule.delay(at: now.addingTimeInterval(20)) == 3_600)
        #expect(schedule.delay(at: now.addingTimeInterval(3_619)) == 1)
        #expect(schedule.delay(at: now.addingTimeInterval(3_620)) == 0)
    }

    @Test func repeatedFailuresDoNotCreateRapidRetries() {
        var schedule = UpdateCheckSchedule()
        for hour in 0..<48 {
            let attempt = now.addingTimeInterval(Double(hour) * 3_600)
            #expect(schedule.delay(at: attempt) == 0)
            schedule.beganAttempt(at: attempt)
            schedule.completed(succeeded: false, at: attempt)
            #expect(schedule.delay(at: attempt.addingTimeInterval(3_599)) == 1)
        }
        #expect(schedule.lastSuccessfulCheckAt == nil)
    }

    @Test func successReturnsToDailyChecks() {
        var schedule = UpdateCheckSchedule()
        schedule.beganAttempt(at: now)
        schedule.completed(succeeded: false, at: now)
        let retry = now.addingTimeInterval(3_600)
        schedule.beganAttempt(at: retry)
        schedule.completed(succeeded: true, at: retry)
        #expect(schedule.lastSuccessfulCheckAt == retry)
        #expect(schedule.delay(at: retry) == 86_400)
        #expect(schedule.delay(at: retry.addingTimeInterval(86_399)) == 1)
        #expect(schedule.delay(at: retry.addingTimeInterval(86_400)) == 0)
    }

    @Test func failurePreservesThePreviousSuccessfulCheck() {
        var schedule = UpdateCheckSchedule()
        schedule.completed(succeeded: true, at: now)
        let later = now.addingTimeInterval(100)
        schedule.beganAttempt(at: later) // Explicit manual checks bypass cooldown.
        schedule.completed(succeeded: false, at: later)
        #expect(schedule.lastSuccessfulCheckAt == now)
        #expect(schedule.delay(at: later) == 3_600)
    }

    @Test func interruptedAttemptIsRateLimitedAfterRestart() throws {
        try withIsolatedDefaults { defaults in
            var before = UpdateCheckSchedule()
            before.beganAttempt(at: now)
            before.save(to: defaults)
            let restored = UpdateCheckSchedule(defaults: defaults, previousAttempt: nil)
            #expect(restored.delay(at: now.addingTimeInterval(30)) == 3_570)
            #expect(restored.lastSuccessfulCheckAt == nil)
        }
    }

    @Test(arguments: [false, true])
    func completedScheduleSurvivesRestart(succeeded: Bool) throws {
        try withIsolatedDefaults { defaults in
            var before = UpdateCheckSchedule()
            before.beganAttempt(at: now)
            before.completed(succeeded: succeeded, at: now)
            before.save(to: defaults)
            // Sparkle's later attempt timestamp must not replace our schedule.
            let restored = UpdateCheckSchedule(defaults: defaults,
                previousAttempt: now.addingTimeInterval(100))
            #expect(restored.nextAutomaticCheckAt == before.nextAutomaticCheckAt)
            #expect(restored.lastSuccessfulCheckAt == before.lastSuccessfulCheckAt)
        }
    }

    @Test func migrationDoesNotTreatSparklesAttemptAsSuccess() throws {
        try withIsolatedDefaults { defaults in
            let restored = UpdateCheckSchedule(defaults: defaults, previousAttempt: now)
            #expect(restored.lastSuccessfulCheckAt == nil)
            #expect(restored.delay(at: now) == 3_600)
            #expect(restored.delay(at: now.addingTimeInterval(4_000)) == 0)
        }
    }

    @Test func futureClockDoesNotStrandTheSchedule() {
        let schedule = UpdateCheckSchedule(nextAutomaticCheckAt: now.addingTimeInterval(200_000))
        #expect(schedule.delay(at: now) == 0)
    }

    @Test func promptWaitsForBothStartupAndSparkleCompletion() {
        var prompt = UpdateMovePromptState()
        prompt.request(version: "3.0")
        #expect(prompt.takePending(sessionInProgress: false) == nil)
        #expect(prompt.pendingVersion == "3.0")
        prompt.startupComplete = true
        #expect(prompt.takePending(sessionInProgress: true) == nil)
        #expect(prompt.pendingVersion == "3.0")
        #expect(prompt.takePending(sessionInProgress: false) == "3.0")
        #expect(prompt.pendingVersion == nil)
    }

    @Test func duplicateCallbacksProduceOnePrompt() {
        var prompt = UpdateMovePromptState()
        prompt.startupComplete = true
        prompt.request(version: "3.0")
        prompt.request(version: "3.0")
        #expect(prompt.takePending(sessionInProgress: false) == "3.0")
        prompt.request(version: "3.0") // Reentrant callback during modal UI.
        #expect(prompt.takePending(sessionInProgress: false) == nil)
        prompt.finishedPresenting()
        #expect(prompt.takePending(sessionInProgress: false) == nil)
        #expect(!prompt.isPresenting)
    }

    @Test func laterAllowsANewUserCheckForTheSameUpdate() {
        var prompt = UpdateMovePromptState()
        prompt.startupComplete = true
        prompt.request(version: "3.0")
        #expect(prompt.takePending(sessionInProgress: false) == "3.0")
        prompt.finishedPresenting()
        prompt.request(version: "3.0")
        #expect(prompt.takePending(sessionInProgress: false) == "3.0")
    }

    @Test func startupCompletionBeforeDiscoveryAlsoPresentsTheUpdate() {
        var prompt = UpdateMovePromptState()
        prompt.startupComplete = true
        #expect(prompt.takePending(sessionInProgress: false) == nil)
        prompt.request(version: "3.1")
        #expect(prompt.takePending(sessionInProgress: false) == "3.1")
    }

    @Test(arguments: [false, true])
    func relocationRequestRequiresTheInstalledCopy(isInstalled: Bool) {
        #expect(UpdateRelaunch.requested(
            environment: [UpdateRelaunch.environmentKey: "1"], isInstalled: isInstalled) == isInstalled)
        #expect(!UpdateRelaunch.requested(environment: [:], isInstalled: isInstalled))
        #expect(!UpdateRelaunch.requested(
            environment: [UpdateRelaunch.environmentKey: "invalid"], isInstalled: isInstalled))
    }

    @Test func updateRelaunchCarriesBothRequestsWithoutShellExpansion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stub = directory.appendingPathComponent("fake open")
        try Data("#!/bin/sh\nprintf '%s\\0' \"$@\"\n".utf8).write(to: stub)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)
        let session = TelemetryLaunchSession(environment: [:])
        let path = "/tmp/Applications with spaces/'\";$(printf UNEXPECTED)\nNumWorks.app"
        let extra = "TEST_LITERAL='\";$(printf UNEXPECTED)"
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = session.relaunchArguments(processID: .max, path: path,
            openExecutable: stub.path, additionalEnvironment: [UpdateRelaunch.environment, extra])
        process.standardOutput = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(bytes.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
            == ["--env", session.relaunchEnvironment, "--env", UpdateRelaunch.environment,
                "--env", extra, path])
    }

    @Test(arguments: [false, true], [SPUUserUpdateStage.notDownloaded, .downloaded, .installing])
    @MainActor func resumedUpdateOutsideApplicationsRepliesToSparkle(
        userInitiated: Bool, stage: SPUUserUpdateStage
    ) throws {
        let driver = MoveRequiredUpdateDriver(hostBundle: .main, delegate: nil)
        driver.isInstalled = { false }
        let item = SUAppcastItem.empty()
        var prompts = 0
        var choices: [SPUUserUpdateChoice] = []
        driver.moveRequired = { received in
            #expect(received === item)
            prompts += 1
        }
        // Use Sparkle's public secure-coding initializer, without an installer,
        // network request, app launch, or visible modal UI.
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        encoder.encode(stage.rawValue, forKey: "SPUUserUpdateStateStage")
        encoder.encode(userInitiated, forKey: "SPUUserUpdateStateUserInitiated")
        encoder.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: encoder.encodedData)
        let state = try #require(SPUUserUpdateState(coder: decoder))
        #expect(state.stage == stage)
        #expect(state.userInitiated == userInitiated)
        driver.showUpdateFound(with: item, state: state) { choices.append($0) }
        #expect(prompts == 1)
        #expect(choices == [.dismiss])
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "NumWorks.UpdateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
