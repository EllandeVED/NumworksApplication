import Sparkle

/// Keeps Sparkle's standard UI, with a fallback for cached/resumed updates:
/// those bypass shouldProceedWithUpdate in Sparkle 2.9.
@MainActor
final class MoveRequiredUpdateDriver: SPUStandardUserDriver {
    var isInstalled: () -> Bool = { Bundle.main.isInstalled }
    var moveRequired: ((SUAppcastItem) -> Void)?

    override func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        guard isInstalled() else {
            moveRequired?(appcastItem)
            // Reply to Sparkle; merely dismissing its window strands the session.
            reply(.dismiss)
            return
        }
        super.showUpdateFound(with: appcastItem, state: state, reply: reply)
    }
}
