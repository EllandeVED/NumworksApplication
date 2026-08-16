#import "EpsilonBridge.h"

#import <objc/runtime.h>
#include <stdatomic.h>
#include <stdlib.h>

#include "NumWorksSimulatorActive.h"

/* Epsilon's main() is renamed to epsilon_main by adapt-epsilon.py
 * (-Dmain=epsilon_main on the simulator main.cpp). Declared here with C++ linkage,
 * which matches the symbol produced when compiling Epsilon's main.cpp. */
int epsilon_main(int argc, char *argv[]);

/* Matches Ion::epsilonVersion() from ion/include/ion.h in the linked
 * libepsilon.a. */
namespace Ion {
const char *epsilonVersion();
}

NSNotificationName const EpsilonWindowDidBecomeAvailableNotification =
    @"EpsilonWindowDidBecomeAvailableNotification";

static IMP NumWorksOriginalTerminate = NULL;
/* Start paused: AppController shows or hides after attach. Avoids ~100 Hz
 * polling while the window is still alpha-0 / ordered out. */
static atomic_bool sSimulatorActive = false;

bool NumWorksSimulatorIsActive(void) {
  return atomic_load_explicit(&sSimulatorActive, memory_order_relaxed);
}

bool NumWorksSimulatorShouldPresent(void) {
  if (!atomic_load_explicit(&sSimulatorActive, memory_order_relaxed)) {
    return false;
  }
  /* SDL_RenderPresent / nextDrawable can block indefinitely once the window
   * is occluded in the background. Skipping the present keeps epsilon_main
   * pumping AppKit (menu bar, hover) instead of hanging. The dirty flag is
   * left set, so the frame is drawn as soon as we come back to the front. */
  NSApplication *app = NSApp;
  return app == nil || app.isActive;
}

static void NumWorksTerminate(id self, SEL _cmd, id sender) {
  if (NumWorksOriginalTerminate != NULL) {
    ((void (*)(id, SEL, id))NumWorksOriginalTerminate)(self, _cmd, sender);
  }
  // SDL's terminate: only posts SDL_QUIT. Force a real process exit so Sparkle
  // (and Quit) can finish. Delay briefly so the SDL quit path can run first.
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          exit(EXIT_SUCCESS);
        });
  });
}

@implementation EpsilonBridge

// Weak storage avoids retaining the SDL-owned NSWindow. Epsilon remains the
// owner; Swift observes the window through this bridge without affecting its
// lifetime.
static __weak NSWindow *sCalculatorWindow = nil;

+ (NSWindow *)calculatorWindow {
  return sCalculatorWindow;
}

+ (BOOL)isSimulatorActive {
  return NumWorksSimulatorIsActive();
}

+ (void)setSimulatorActive:(BOOL)active {
  atomic_store_explicit(&sSimulatorActive, active ? true : false,
                        memory_order_relaxed);
}

+ (void)installProcessExitOnTerminate {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = NSClassFromString(@"SDLApplication");
    if (cls == Nil) {
      cls = [NSApplication class];
    }
    Method method = class_getInstanceMethod(cls, @selector(terminate:));
    if (method == NULL) {
      return;
    }
    NumWorksOriginalTerminate =
        method_setImplementation(method, (IMP)NumWorksTerminate);
  });
}

+ (void)registerCalculatorWindow:(NSWindow *)window {
  if (window == nil) {
    return;
  }

  sCalculatorWindow = window;
  [self installProcessExitOnTerminate];

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
    [self setSimulatorActive:NO];
  }
}

+ (int)runSimulatorWithArgc:(int)argc argv:(char **)argv {
  /* SDL disables the screensaver by default (game-oriented). That holds a
   * PreventUserIdleDisplaySleep assertion for the life of the process, which
   * for a menu-bar app blocks idle display/system sleep all day. Opt out
   * before video init so macOS idle timers behave normally. */
  setenv("SDL_VIDEO_ALLOW_SCREENSAVER", "1", 1);
  return epsilon_main(argc, argv);
}

+ (NSString *)epsilonVersionString {
  return [NSString stringWithUTF8String:Ion::epsilonVersion()];
}

@end
