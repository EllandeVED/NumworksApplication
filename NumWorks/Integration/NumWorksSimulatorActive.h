#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* True when the calculator window is visible / not occluded.
 * Drives the poll interval only. epsilon_main pumps AppKit on the main thread,
 * so slowing this down also delays clicks and shortcuts. */
bool NumWorksSimulatorIsActive(void);

/* True when it is safe to hand a frame to the GPU: visible *and* frontmost.
 * Presenting from the background can block forever in Metal nextDrawable,
 * which wedges the main thread (beachball over the app and the menu bar). */
bool NumWorksSimulatorShouldPresent(void);

#ifdef __cplusplus
}
#endif
