#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The user has requested the calculator window to be shown. */
bool NumWorksSimulatorIsActive(void);

/* True when it is safe to hand a frame to the GPU: visible *and* frontmost.
 * Presenting from the background can block forever in Metal nextDrawable,
 * which wedges the main thread (beachball over the app and the menu bar). */
bool NumWorksSimulatorShouldPresent(void);

/* Wait in AppKit, rather than sleeping the main thread. Native input, Carbon
 * shortcuts, dispatch sources and timers remain serviceable. Returns true if
 * native input or an explicit wake interrupted the wait. Never consumes input. */
bool NumWorksSimulatorWaitForEvent(int maximumDelayMilliseconds);
void NumWorksSimulatorWake(void);

#ifdef __cplusplus
}
#endif
