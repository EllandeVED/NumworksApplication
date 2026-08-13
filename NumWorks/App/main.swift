import AppKit

// Custom entry point: normally the app hands the main thread to Epsilon (SDL).
// Under `--ui-testing`, we stay on a plain AppKit run loop so XCTest Accessibility
// queries do not stall waiting for an SDL process that never goes “idle”.

@MainActor
func startApplication() -> Int32 {
    let appController = AppController()
    appController.start()

    return withExtendedLifetime(appController) {
        if UITesting.isEnabled {
            return appController.runUITestingShell()
        }
        return EpsilonBridge.runSimulator(
            withArgc: CommandLine.argc,
            argv: CommandLine.unsafeArgv
        )
    }
}

exit(MainActor.assumeIsolated { startApplication() })
