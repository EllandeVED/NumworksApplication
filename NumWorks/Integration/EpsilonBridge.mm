#import "EpsilonBridge.h"

/* Epsilon's main() is renamed to epsilon_main by the build-system patch
 * (Patches/002-static-library-target.patch). Declared here with C++ linkage,
 * which matches the symbol produced when compiling Epsilon's main.cpp. */
int epsilon_main(int argc, char *argv[]);

/* Matches Ion::epsilonVersion() from ion/include/ion.h in the linked
 * libepsilon.a. */
namespace Ion {
const char *epsilonVersion();
}

NSNotificationName const EpsilonWindowDidBecomeAvailableNotification =
    @"EpsilonWindowDidBecomeAvailableNotification";

@implementation EpsilonBridge

// Weak storage avoids retaining the SDL-owned NSWindow. Epsilon remains the
// owner; Swift observes the window through this bridge without affecting its
// lifetime.
static __weak NSWindow *sCalculatorWindow = nil;

+ (NSWindow *)calculatorWindow {
  return sCalculatorWindow;
}

+ (void)registerCalculatorWindow:(NSWindow *)window {
  if (window == nil) {
    return;
  }

  sCalculatorWindow = window;

  /* Epsilon calls this from didInit() on the main thread, before it starts
   * pumping SDL events. Posting synchronously in that case guarantees
   * delivery to observers registered before epsilon_main() was entered.
   * The dispatch_async fallback keeps delivery on the main thread if
   * registration ever happens elsewhere. */
  if (NSThread.isMainThread) {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:EpsilonWindowDidBecomeAvailableNotification
                      object:window];
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSNotificationCenter defaultCenter]
          postNotificationName:EpsilonWindowDidBecomeAvailableNotification
                        object:window];
    });
  }
}

+ (void)unregisterCalculatorWindow:(NSWindow *)window {
  // Only clear the bridge when Epsilon shuts down the same window instance.
  if (window != nil && sCalculatorWindow == window) {
    sCalculatorWindow = nil;
  }
}

+ (int)runSimulatorWithArgc:(int)argc argv:(char **)argv {
  return epsilon_main(argc, argv);
}

+ (NSString *)epsilonVersionString {
  return [NSString stringWithUTF8String:Ion::epsilonVersion()];
}

@end
