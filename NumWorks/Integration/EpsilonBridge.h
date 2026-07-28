#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const EpsilonWindowDidBecomeAvailableNotification;

@interface EpsilonBridge : NSObject

@property(class, nonatomic, readonly, nullable, weak) NSWindow *calculatorWindow;

+ (void)registerCalculatorWindow:(NSWindow *)window;
+ (void)unregisterCalculatorWindow:(NSWindow *)window;

/* Runs the Epsilon simulator on the current thread. This wraps
 * epsilon_main(), the renamed Epsilon entry point (see
 * Patches/002-static-library-target.patch). It must be called from the main
 * thread and does not return until the simulator quits. */
+ (int)runSimulatorWithArgc:(int)argc
                       argv:(char *_Nullable *_Nonnull)argv;

/* Version string of the linked Epsilon library (e.g. "23.2.3"). */
+ (NSString *)epsilonVersionString;

@end

NS_ASSUME_NONNULL_END
