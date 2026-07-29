#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const EpsilonWindowDidBecomeAvailableNotification;

@interface EpsilonBridge : NSObject

@property(class, nonatomic, readonly, nullable, weak) NSWindow *calculatorWindow;

+ (void)registerCalculatorWindow:(NSWindow *)window;
+ (void)unregisterCalculatorWindow:(NSWindow *)window;

/* When NO, Epsilon sleeps longer between polls and skips SDL presents.
 * Drive from CalculatorWindow show/hide / occlusion. */
@property(class, nonatomic, getter=isSimulatorActive) BOOL simulatorActive;

/* Runs the Epsilon simulator on the current thread. This wraps
 * epsilon_main(), the renamed Epsilon entry point (see
 * Patches/002-static-library-target.patch). It must be called from the main
 * thread and does not return until the simulator quits. */
+ (int)runSimulatorWithArgc:(int)argc
                       argv:(char *_Nullable *_Nonnull)argv;

/* Version string of the linked Epsilon library (e.g. "23.2.3"). */
+ (NSString *)epsilonVersionString;

/* SDLApplication overrides -terminate: to only post SDL_QUIT (no process
 * exit). Sparkle’s installer sends a soft terminate and waits for the process
 * to die before replacing the bundle. Call once SDL has created NSApp. */
+ (void)installProcessExitOnTerminate;

@end

NS_ASSUME_NONNULL_END
