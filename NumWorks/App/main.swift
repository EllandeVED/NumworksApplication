import AppKit

// Custom entry point: the app hands the main thread to Epsilon, whose SDL
// backend creates and pumps the NSApplication event loop. Swift code reacts
// to the simulator through EpsilonBridge notifications.

// The controller must exist before Epsilon starts so its bridge observer is
// registered when the window notification fires.
@MainActor
func startApplication() -> Int32 {
    let appController = AppController()
    appController.start()

    // Blocks until the simulator quits; the controller stays alive for the
    // whole run.
    return withExtendedLifetime(appController) {
        EpsilonBridge.runSimulator(
            withArgc: CommandLine.argc,
            argv: CommandLine.unsafeArgv
        )
    }
}

// Top-level code runs on the main thread, but is not statically
// MainActor-isolated in this language mode.
exit(MainActor.assumeIsolated { startApplication() })
