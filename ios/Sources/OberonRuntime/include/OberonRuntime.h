/* OberonRuntime.h — C-ABI surface of the Oberon runtime as seen from
 * the Swift host.
 *
 * The flow is bidirectional but the directions don't mirror:
 *
 *   Oberon → Swift: every TUI / Out / Env call in the Oberon code
 *     enters the runtime sidecar (runtime/ios/TUI_rt.c etc.) which
 *     forwards to an `ios_tui_*` / `ios_out_*` / `ios_env_*` extern.
 *     Swift defines those via @_cdecl and the linker resolves them
 *     at app-build time. Those externs aren't declared here — they're
 *     defined in Swift; the Oberon side declares them.
 *
 *   Swift → Oberon: the host drives the event-driven path. For each
 *     keystroke the SwiftUI input handler calls `oc_dispatch_key(k)`
 *     to invoke the Oberon-registered handler. This header declares
 *     the small set of Oberon-defined symbols Swift needs to call.
 *
 * Per-program symbols (`<Entry>__init`, `<Entry>__<Procedure>`) are
 * the consuming app's responsibility — declare them in the app's own
 * bridging header. This header carries only the generic runtime
 * surface.
 */

#ifndef OBERON_RUNTIME_H
#define OBERON_RUNTIME_H

#ifdef __cplusplus
extern "C" {
#endif

/* Dispatch a key code into the Oberon-side handler registered via
 * TUI.SetKeyHandler. Returns immediately if no handler is registered.
 * Codes:
 *   1..26    Ctrl + letter
 *   32..126  printable ASCII
 *   127      backspace
 *   256..264 arrow / home / end / page / delete (synthetic)
 *   290..299 Meta-X (synthetic)
 * Higher codes are unassigned and should be ignored by the host. */
void oc_dispatch_key(int code);

/* Stash argv before any Oberon module body runs. iOS apps have no
 * meaningful argv — call once at startup with (0, NULL). Provided
 * for parity with the posix / wasm runtimes where the synthesised
 * main() does the equivalent. */
void oc_set_args(int argc, const char **argv);

#ifdef __cplusplus
}
#endif

#endif /* OBERON_RUNTIME_H */
