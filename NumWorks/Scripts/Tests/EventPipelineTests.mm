// Production SDL/event-state-machine tests with rendering replaced by a counter.
// SDL video cannot initialize in an executor with no screens. Input, event
// mapping, keyboard queues, deadlines and AppKit waits are the real code.
#import <AppKit/AppKit.h>
#include <SDL.h>
#include <ion/events.h>
#include <ion/keyboard.h>
#include <ion/timing.h>
#include <ion/src/shared/events.h>
#include <ion/src/shared/events_modifier.h>
#include <ion/src/shared/keyboard.h>
#include "NumWorksSimulatorActive.h"
#import "EpsilonBridge.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/resource.h>

extern "C" int SDL_KeyboardInit(void);
extern "C" int SDL_SendKeyboardKey(Uint8, SDL_Scancode);
static int layouts = 0;
static int refreshes = 0;
static bool hitTestAfterLayout = false;
int epsilon_main(int, char **) { return 0; }

namespace Ion {
const char *softwareVersion() { return "test"; }
namespace Simulator {
namespace Window {
bool isHeadless() { return false; }
void relayout() { ++layouts; }
void refresh() {
  ++refreshes;
  // In a real Cocoa video device SDL_PumpEvents drains these native events.
  while (NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskApplicationDefined
      untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES]) {
    [NSApp sendEvent:event];
  }
}
}
namespace Layout {
Ion::Keyboard::Key getHighlightedKey() { return Ion::Keyboard::Key::None; }
void highlightKeyAt(SDL_Point *) { hitTestAfterLayout = layouts > 0; }
void unhighlightKey() {}
}
namespace Journal { Ion::Events::Journal *replayJournal() { return nullptr; } }
namespace Haptics { void rumble() {} }
}
}

static void require(bool ok, const char *message) {
  if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void windowBurst(int count) {
  for (int i = 0; i < count; i++) {
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_EXPOSED;
    require(SDL_PushEvent(&event) == 1, "window event enqueued");
  }
}
static Ion::Events::Event nextEvent() {
  int timeout = 300;
  return Ion::Events::getEvent(&timeout);
}

static double cpuSeconds() {
  rusage usage = {};
  getrusage(RUSAGE_SELF, &usage);
  return usage.ru_utime.tv_sec + usage.ru_stime.tv_sec
      + (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000000.0;
}

static void checkQuietIdle(bool visible) {
  EpsilonBridge.simulatorActive = visible;
  nextEvent(); // Consume startup/visibility wakes before measuring a quiet run.
  refreshes = 0;
  uint64_t start = Ion::Timing::millis();
  double cpuStart = cpuSeconds();
  for (int i = 0; i < 3; ++i) {
    Ion::Events::Event event = nextEvent();
    require(event == Ion::Events::None || event == Ion::Events::Idle,
            "quiet idle must not generate user input");
  }
  uint64_t elapsed = Ion::Timing::millis() - start;
  require(elapsed >= 850, "idle waits must retain the calculator timer deadlines");
  require(refreshes <= 9, "quiet idle must not resume 10/50 ms polling");
  printf("PASS: %s quiet idle: %d scan/refresh checks across three 300 ms deadlines; %.3f%% CPU in renderer-free harness\n",
         visible ? "visible" : "hidden", refreshes,
         (cpuSeconds() - cpuStart) * 100000 / elapsed);
}

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    require(SDL_Init(SDL_INIT_EVENTS | SDL_INIT_TIMER) == 0, "SDL events initialize without video");
    require(SDL_KeyboardInit() == 0, "real SDL keyboard initializes");
    Ion::Events::SharedState.init();
    Ion::Events::SharedModifierState.init();
    EpsilonBridge.simulatorActive = YES;

    if (getenv("NUMWORKS_MEASURE_REPEAT")) {
      SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RIGHT);
      require(nextEvent() == Ion::Events::Right, "measurement initial key");
      uint64_t started = Ion::Timing::millis();
      require(nextEvent() == Ion::Events::Right, "measurement first repeat");
      uint64_t first = Ion::Timing::millis() - started;
      started = Ion::Timing::millis();
      require(nextEvent() == Ion::Events::Right, "measurement subsequent repeat");
      printf("REPEAT MEASUREMENT: %llu/%llu ms\n", first, Ion::Timing::millis() - started);
      SDL_Quit();
      return 0;
    }

    checkQuietIdle(true);
    checkQuietIdle(false);
    EpsilonBridge.simulatorActive = YES;

    windowBurst(100);
    require(Ion::Events::getPlatformEvent() == Ion::Events::None, "window notifications stay non-input");
    require(layouts == 1, "100 window events coalesce into one layout");
    require(!SDL_HasEvents(SDL_FIRSTEVENT, SDL_LASTEVENT), "window burst fully drained");

    layouts = 0;
    windowBurst(20);
    SDL_Event motion = {};
    motion.type = SDL_MOUSEMOTION;
    SDL_PushEvent(&motion);
    windowBurst(20);
    Ion::Events::getPlatformEvent();
    require(layouts == 2 && hitTestAfterLayout, "layout precedes hit testing and trailing layout is applied");

    layouts = 0;
    refreshes = 0;
    windowBurst(100);
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RIGHT);
    uint64_t start = Ion::Timing::millis();
    require(nextEvent() == Ion::Events::Right, "queued arrow is delivered");
    require(Ion::Timing::millis() - start < 100, "window burst cannot delay keyboard input");
    require(layouts == 1 && refreshes <= 2, "window burst does not render 100 frames");

    start = Ion::Timing::millis();
    Ion::Events::Event firstRepeated = nextEvent();
    if (firstRepeated != Ion::Events::Right) {
      fprintf(stderr, "Repeat diagnostic: event=%d elapsed=%llu SDL right=%d\n",
          static_cast<uint8_t>(firstRepeated), Ion::Timing::millis() - start,
          SDL_GetKeyboardState(nullptr)[SDL_SCANCODE_RIGHT]);
    }
    require(firstRepeated == Ion::Events::Right, "held key repeats");
    uint64_t firstRepeat = Ion::Timing::millis() - start;
    require(firstRepeat >= 100 && firstRepeat <= 240, "first repeat retains the original simulator cadence");
    start = Ion::Timing::millis();
    require(nextEvent() == Ion::Events::Right, "held key repeats again");
    uint64_t repeat = Ion::Timing::millis() - start;
    require(repeat >= 15 && repeat <= 100, "subsequent repeat retains the original simulator cadence");
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_RIGHT);
    require(nextEvent() != Ion::Events::Right, "key release stops repetition");

    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RIGHT);
    require(nextEvent() == Ion::Events::Right, "new press starts a new repeat deadline");
    __block bool stalled = false;
    [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *) {
      // Deliberately simulate an OS/main-thread stall in this test process.
      [NSThread sleepForTimeInterval:0.31];
      stalled = true;
    }];
    require(nextEvent() == Ion::Events::Right, "late wake preserves repeat-before-timer priority");
    require(stalled, "scheduler overshoot was exercised");
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_RIGHT);
    require(nextEvent() != Ion::Events::Right, "release after late repeat stops repetition");

    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RIGHT);
    require(nextEvent() == Ion::Events::Right, "press before frequent UI wakes");
    NSTimer *uiWakes = [NSTimer scheduledTimerWithTimeInterval:0.002 repeats:YES block:^(NSTimer *) {
      NumWorksSimulatorWake();
    }];
    start = Ion::Timing::millis();
    Ion::Events::Event noisyRepeat = nextEvent();
    uint64_t noisyDelay = Ion::Timing::millis() - start;
    [uiWakes invalidate];
    require(noisyRepeat == Ion::Events::Right && noisyDelay <= 240,
            "frequent native UI wakes cannot starve or slow key repetition");
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_RIGHT);
    require(nextEvent() != Ion::Events::Right, "release after frequent wakes stops repetition");

    SDL_Event text = {};
    text.type = SDL_TEXTINPUT;
    strcpy(text.text.text, "7");
    SDL_PushEvent(&text);
    start = Ion::Timing::millis();
    Ion::Events::Event typed = nextEvent();
    require(typed.text() && strcmp(typed.text(), "7") == 0, "text input mapping is unchanged");
    require(Ion::Timing::millis() - start < 100, "queued text does not wait for an idle deadline");

    [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *) {
      SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_LEFT);
      NumWorksSimulatorWake();
    }];
    start = Ion::Timing::millis();
    require(nextEvent() == Ion::Events::Left, "input arriving during a wait wakes the core");
    require(Ion::Timing::millis() - start < 100, "delayed input wakes before 300 ms deadline");
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_LEFT);
    require(nextEvent() != Ion::Events::Left, "delayed key also releases");

    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_ESCAPE);
    require(Ion::Keyboard::scan(true).keyDown(Ion::Keyboard::Key::Back), "Python interruption scan remains live");
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_ESCAPE);
    require(!Ion::Keyboard::scan(true).keyDown(Ion::Keyboard::Key::Back), "Python scan sees release");
    printf("PASS: production event pipeline: 100-event bursts, input ordering, queued/delayed input, text, Python scans, repeat %llu/%llu ms, releases\n", firstRepeat, repeat);
    SDL_Quit();
  }
  return 0;
}
