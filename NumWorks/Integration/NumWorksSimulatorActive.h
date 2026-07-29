#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* True when the calculator window is visible / not occluded.
 * Epsilon's simulator poll loop uses this to sleep longer and skip GPU presents. */
bool NumWorksSimulatorIsActive(void);

#ifdef __cplusplus
}
#endif
