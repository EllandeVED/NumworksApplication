#import "EpsilonBridge.h"

#import <objc/runtime.h>
#include <stdatomic.h>
#include <stdlib.h>

#include "NumWorksSimulatorActive.h"

/* Epsilon's main() is renamed to epsilon_main by adapt-epsilon.py
 * (-Dmain=epsilon_main on the simulator main.cpp). Declared here with C++ linkage,
 * which matches the symbol produced when compiling Epsilon's main.cpp. */
int epsilon_main(int argc, char *argv[]);

/* Matches Ion::softwareVersion() from ion/include/ion.h (Epsilon 25+). */
namespace Ion {
const char *softwareVersion();
}

NSNotificationName const EpsilonWindowDidBecomeAvailableNotification =
    @"EpsilonWindowDidBecomeAvailableNotification";

static IMP NumWorksOriginalTerminate = NULL;
static IMP NumWorksOriginalFocusSomeWindow = NULL;
/* Start with presentation disabled until Swift restores the frame and decides
 * whether to show the calculator. Input processing is never suspended. */
static atomic_bool sSimulatorActive = false;
static atomic_bool sCanPresent = false;
static atomic_uint sEventWaitDepth = 0;
static atomic_uint_fast64_t sWakeGeneration = 0;
static atomic_uint_fast64_t sConsumedWakeGeneration = 0;
static BOOL sDisplaySleeping = NO;

bool NumWorksSimulatorIsActive(void) {
  return atomic_load_explicit(&sSimulatorActive, memory_order_relaxed);
}

bool NumWorksSimulatorShouldPresent(void) {
  return atomic_load_explicit(&sCanPresent, memory_order_relaxed);
}

void NumWorksSimulatorWake(void) {
  atomic_fetch_add_explicit(&sWakeGeneration, 1, memory_order_seq_cst);
  if (atomic_load_explicit(&sEventWaitDepth, memory_order_seq_cst) == 0) {
    return;
  }
  /* CFRunLoopWakeUp alone does not make -nextEventMatchingMask: return.
   * Posting an ordinary application-defined event also covers a Carbon/GCD
   * callback which showed the window from inside that very call. SDL drains
   * this harmless event together with native input on the next iteration. */
  @autoreleasepool {
    NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
        location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
        context:nil subtype:0x4e57 data1:0 data2:0];
    [NSApp postEvent:wake atStart:NO];
  }
}

bool NumWorksSimulatorWaitForEvent(int maximumDelayMilliseconds) {
  NSCAssert(NSThread.isMainThread, @"The simulator event wait must run on main");
  if (maximumDelayMilliseconds <= 0 || NSApp == nil) {
    return false;
  }
  @autoreleasepool {
    uint_fast64_t generation = atomic_load_explicit(&sWakeGeneration,
                                                   memory_order_seq_cst);
    // A show/activation request made during SDL_PumpEvents must survive until
    // this point. Give pending main-thread work another turn before parking.
    if (generation != atomic_exchange_explicit(&sConsumedWakeGeneration,
                                               generation, memory_order_seq_cst)) {
      return true;
    }
    atomic_fetch_add_explicit(&sEventWaitDepth, 1, memory_order_seq_cst);
    NSEvent *event = nil;
    if (generation == atomic_load_explicit(&sWakeGeneration, memory_order_seq_cst)) {
      event = [NSApp nextEventMatchingMask:NSEventMaskAny
          untilDate:[NSDate dateWithTimeIntervalSinceNow:
              maximumDelayMilliseconds / 1000.0]
          inMode:NSDefaultRunLoopMode dequeue:NO];
    }
    atomic_fetch_sub_explicit(&sEventWaitDepth, 1, memory_order_seq_cst);
    return event != nil || generation != atomic_load_explicit(&sWakeGeneration,
                                                             memory_order_seq_cst);
  }
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

static void NumWorksFocusSomeWindow(id self, SEL _cmd, NSNotification *notification) {
  // SDL raises/restores its window on app activation. A hide request must win
  // even while AppKit still reports the window visible inside orderOut:.
  if (NumWorksSimulatorIsActive() && NumWorksOriginalFocusSomeWindow != NULL) {
    ((void (*)(id, SEL, id))NumWorksOriginalFocusSomeWindow)(self, _cmd, notification);
  }
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
  [self refreshSimulatorVisibility];
  NumWorksSimulatorWake();
}

+ (BOOL)simulatorDisplaySleeping { return sDisplaySleeping; }

+ (void)setSimulatorDisplaySleeping:(BOOL)sleeping {
  sDisplaySleeping = sleeping;
  [self refreshSimulatorVisibility];
}

+ (void)refreshSimulatorVisibility {
  NSWindow *window = sCalculatorWindow;
  BOOL canPresent = NumWorksSimulatorIsActive() && !sDisplaySleeping &&
      NSApp.isActive && !NSApp.isHidden && window.isVisible &&
      !window.isMiniaturized && window.isOnActiveSpace &&
      (window.occlusionState & NSWindowOcclusionStateVisible) != 0;
  /* Never park the event loop on occlusion. nextDrawable can block when a
   * window is covered; only rendering/cursor animation is deferred here. */
  bool previous = atomic_exchange_explicit(&sCanPresent, canPresent,
                                           memory_order_relaxed);
  if (previous != canPresent) {
    NumWorksSimulatorWake();
  }
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

+ (void)installWindowActivationGuard {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = NSClassFromString(@"SDLAppDelegate");
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(@"focusSomeWindow:"));
    if (method != NULL) {
      NumWorksOriginalFocusSomeWindow =
          method_setImplementation(method, (IMP)NumWorksFocusSomeWindow);
    }
  });
}

+ (void)registerCalculatorWindow:(NSWindow *)window {
  if (window == nil) {
    return;
  }

  sCalculatorWindow = window;
  [self installProcessExitOnTerminate];
  [self installWindowActivationGuard];

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
  const char *version = Ion::softwareVersion();
  if (version == nullptr) {
    return @"";
  }
  return [NSString stringWithUTF8String:version];
}

@end
