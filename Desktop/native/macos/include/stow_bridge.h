#ifndef STOW_DESKTOP_BRIDGE_H
#define STOW_DESKTOP_BRIDGE_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ABI v1. Requests are UTF-8 JSON, <=16 MiB; responses are <=64 MiB.
 * submit copies input synchronously. All completions are asynchronous on the
 * main actor. The host must run the main run loop and must not block it waiting
 * for a completion. context must remain valid until completion returns.
 * Each completion transfers one response allocation to its caller. Release it
 * exactly once with stow_bridge_free, including error responses. No NUL suffix.
 * Handles are registry numbers, not object pointers. close stops admission,
 * drains earlier accepted work and callbacks, then releases the store and writer
 * lock before invoking its completion. Completion guarantees teardown.
 */
uint32_t stow_bridge_abi_version(void);
typedef void (*stow_bridge_completion)(void *context, uint8_t *bytes, intptr_t length);
void stow_bridge_submit(uint64_t handle, const uint8_t *bytes, intptr_t length,
                        void *context, stow_bridge_completion completion);
void stow_bridge_free(uint8_t *bytes, intptr_t length);

#ifdef __cplusplus
}
#endif
#endif
