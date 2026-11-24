// Compile against the production bridge, with only the unavailable core entry
// points stubbed. No NumWorks preferences, calculator data, or network are used.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import "EpsilonBridge.h"
#include "NumWorksSimulatorActive.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>

int epsilon_main(int, char **) { return 0; }
namespace Ion { const char *softwareVersion() { return "test"; } }

// Match SDL's activation observer without initializing its video subsystem.
@interface SDLAppDelegate : NSObject
@property(nonatomic) NSUInteger focusCount;
- (void)focusSomeWindow:(NSNotification *)notification;
@end
@implementation SDLAppDelegate
- (void)focusSomeWindow:(NSNotification *)notification { self.focusCount++; }
@end

@interface EpsilonBridge (ActivationTesting)
+ (void)installWindowActivationGuard;
@end

using Clock = std::chrono::steady_clock;
static double ms(Clock::time_point start) {
  return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}
static void require(bool condition, const char *message) {
  if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void drain() {
  while (NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
      untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES]) {
    [NSApp sendEvent:event];
  }
}
static NSEvent *keyEvent() {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
      modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"7"
      charactersIgnoringModifiers:@"7" isARepeat:NO keyCode:26];
}

struct HotkeyProbe {
  bool delivered = false;
  Clock::time_point postedAt;
  double latency = 0;
};
static OSStatus hotkeyHandler(EventHandlerCallRef, EventRef, void *context) {
  HotkeyProbe *probe = static_cast<HotkeyProbe *>(context);
  probe->delivered = true;
  probe->latency = ms(probe->postedAt);
  EpsilonBridge.simulatorActive = YES;
  return noErr;
}

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    drain();

    if ([EpsilonBridge respondsToSelector:@selector(installWindowActivationGuard)]) {
      [EpsilonBridge installWindowActivationGuard];
      [EpsilonBridge installWindowActivationGuard]; // Must not wrap itself.
    }
    SDLAppDelegate *delegate = [SDLAppDelegate new];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:delegate selector:@selector(focusSomeWindow:)
        name:NSApplicationDidBecomeActiveNotification object:nil];
    EpsilonBridge.simulatorActive = NO;
    [center postNotificationName:NSApplicationDidBecomeActiveNotification object:NSApp];
    require(delegate.focusCount == 0, "activation must not raise a hidden calculator");
    EpsilonBridge.simulatorActive = YES;
    [center postNotificationName:NSApplicationDidBecomeActiveNotification object:NSApp];
    require(delegate.focusCount == 1, "activation of a shown calculator still reaches SDL");
    // A delayed activation can arrive after hide and before native orderOut ends.
    // This check deliberately has no timeout or native visibility dependency.
    EpsilonBridge.simulatorActive = NO;
    [center postNotificationName:NSApplicationDidBecomeActiveNotification object:NSApp];
    require(delegate.focusCount == 1, "late activation must not reverse a hide request");
    EpsilonBridge.simulatorActive = YES;
    [center postNotificationName:NSApplicationDidBecomeActiveNotification object:NSApp];
    require(delegate.focusCount == 2, "a later show must allow normal SDL activation again");
    EpsilonBridge.simulatorActive = NO;
    [center removeObserver:delegate];
    drain();

    auto start = Clock::now();
    require(!NumWorksSimulatorWaitForEvent(0), "zero deadline must not wait");
    require(ms(start) < 25, "zero deadline/key repeat must be immediate");

    NumWorksSimulatorWake();
    start = Clock::now();
    require(NumWorksSimulatorWaitForEvent(1000), "wake before entering wait remains pending");
    require(ms(start) < 25, "pre-wait show request must not be lost");

    // Native input is left queued for SDL, including input arriving before wait.
    NSEvent *key = keyEvent();
    [NSApp postEvent:key atStart:NO];
    start = Clock::now();
    require(NumWorksSimulatorWaitForEvent(1000), "queued input wakes wait");
    require(ms(start) < 100, "queued input must not wait for deadline");
    NSEvent *received = [NSApp nextEventMatchingMask:NSEventMaskKeyDown
        untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
    if (received == nil || ![received.characters isEqualToString:@"7"] || received.keyCode != 26) {
      fprintf(stderr, "Expected key: %s; received: %s\n", key.description.UTF8String,
              received.description.UTF8String);
    }
    require(received != nil && [received.characters isEqualToString:@"7"] && received.keyCode == 26,
            "wait must preserve input contents for SDL");
    drain();

    __block bool fired = false;
    __block double callbackDelay = 0;
    start = Clock::now();
    const auto timerStart = start;
    [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *) {
      callbackDelay = ms(timerStart);
      fired = true;
      NumWorksSimulatorWake();
    }];
    while (!fired && ms(start) < 1000) {
      NumWorksSimulatorWaitForEvent(1000);
      drain();
    }
    require(fired && callbackDelay < 100, "main-run-loop timers remain responsive");
    require(ms(start) < 150, "explicit wake exits native wait promptly");

    // Same Carbon event dispatcher used by KeyboardShortcuts, without posting
    // hardware input globally or requiring Accessibility permission.
    HotkeyProbe hotkey;
    EventHandlerRef handler = nullptr;
    EventTypeSpec type = {kEventClassKeyboard, kEventHotKeyReleased};
    require(InstallEventHandler(GetEventDispatcherTarget(), hotkeyHandler,
                               1, &type, &hotkey, &handler) == noErr,
            "Carbon hotkey handler installs");
    HotkeyProbe *hotkeyPointer = &hotkey;
    [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *) {
      EventRef event;
      require(CreateEvent(nullptr, kEventClassKeyboard, kEventHotKeyReleased,
                          GetCurrentEventTime(), kEventAttributeUserEvent, &event) == noErr,
              "Carbon shortcut event created");
      hotkeyPointer->postedAt = Clock::now();
      require(PostEventToQueue(GetMainEventQueue(), event, kEventPriorityStandard) == noErr,
              "Carbon shortcut event queued");
      ReleaseEvent(event);
    }];
    start = Clock::now();
    while (!hotkey.delivered && ms(start) < 1000) {
      NumWorksSimulatorWaitForEvent(1000);
      drain();
    }
    require(hotkey.delivered && hotkey.latency < 100, "Carbon shortcut is delivered immediately");
    require(ms(start) < 150, "Carbon shortcut wakes the native idle wait");
    RemoveEventHandler(handler);
    drain();

    // Nested AppKit processing must leave the outer wait wakeable.
    __block bool nestedFinished = false;
    [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *) {
      NumWorksSimulatorWaitForEvent(2);
      nestedFinished = true;
      NumWorksSimulatorWake();
    }];
    start = Clock::now();
    while (!nestedFinished && ms(start) < 1000) {
      NumWorksSimulatorWaitForEvent(1000);
      drain();
    }
    require(nestedFinished && ms(start) < 150, "outer event wait wakes after a nested wait");

    __block bool followUpRan = false;
    __block Clock::time_point showRequestedAt;
    __block double followUpDelay = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
          showRequestedAt = Clock::now();
          EpsilonBridge.simulatorActive = YES;
          dispatch_async(dispatch_get_main_queue(), ^{
            followUpDelay = ms(showRequestedAt);
            followUpRan = true;
          });
        });
    start = Clock::now();
    while (!followUpRan && ms(start) < 1000) {
      NumWorksSimulatorWaitForEvent(1000);
      drain();
    }
    require(followUpRan && followUpDelay < 100, "deferred show/focus work is not parked on idle deadline");

    // This is the Carbon/GCD shortcut case: show/hide runs *inside* nextEvent.
    double slowestWake = 0;
    for (int i = 0; i < 40; i++) {
      __block bool callbackRan = false;
      __block Clock::time_point requestedAt;
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_MSEC),
          dispatch_get_main_queue(), ^{
            requestedAt = Clock::now();
            EpsilonBridge.simulatorActive = (i % 2 == 0);
            callbackRan = true;
          });
      start = Clock::now();
      while (!callbackRan && ms(start) < 1000) {
        NumWorksSimulatorWaitForEvent(1000);
        drain();
      }
      require(callbackRan, "show/hide callback must run inside wait");
      double latency = ms(requestedAt);
      if (latency > slowestWake) { slowestWake = latency; }
      require(latency < 100, "show/hide must not wait for the idle deadline");
      require(NumWorksSimulatorIsActive() == (i % 2 == 0), "show/hide state preserved");
      require(!NumWorksSimulatorShouldPresent(), "unattached/hidden window must not render");
      drain();
    }

    // Input posted by a main-queue callback is also delivered without a wake call.
    __block bool posted = false;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
          posted = true;
          [NSApp postEvent:keyEvent() atStart:NO];
        });
    start = Clock::now();
    while (!posted && ms(start) < 1000) {
      NumWorksSimulatorWaitForEvent(1000);
    }
    require(posted && ms(start) < 150, "native input wakes a blocked loop immediately");
    received = [NSApp nextEventMatchingMask:NSEventMaskKeyDown
        untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
    require(received != nil, "asynchronous input is preserved for SDL");
    drain();

    // A quiet wait should really block, instead of returning in a busy loop.
    NumWorksSimulatorWaitForEvent(1); // Acknowledge the preceding explicit wake.
    drain();
    start = Clock::now();
    NumWorksSimulatorWaitForEvent(120);
    require(ms(start) >= 100, "quiet wait must block until its timer deadline");
    printf("PASS: activation visibility guard, native wait, input preservation, timers, Carbon shortcut %.3f ms, nested wait, deferred focus %.3f ms, 40 show/hide wakes; slowest wake %.3f ms\n", hotkey.latency, followUpDelay, slowestWake);
  }
  return 0;
}
