# SL Direct GTAO — v1.2.1 corrective operating modes

Date: 2026-08-23
Branch: `agent/direct-gtao-integration`

## Runtime proof preserved from prior builds
- Firestorm straight-alpha boundary detection is stable without nested ReShade execution.
- Direct GTAO reaches the proven pre-alpha boundary and has applied once per frame in prior runtime tests.
- D0, N0, raw AO and denoised AO export paths were proven live.
- D0 is spatially coherent.
- Firestorm N0 encoding matches the direct GTAO stereographic XY decode.
- Raw/denoised AO are currently populated but overwhelmingly dark; AO correctness is not yet validated.

## v1.2.1 corrective changes
- Replaced ambiguous passthrough behavior with explicit Firestorm Baseline / GTAO Diagnostics / GTAO Active modes.
- Baseline is the default and performs zero direct GTAO rendering, zero scene-color copy/write and zero alpha replay.
- Diagnostics generate/export private resources only; Firestorm scene color is never copied or written.
- Debug FX defaults to backbuffer and is forced to backbuffer while Baseline is selected.
- N dot V / unoccluded-baseline validation passes are diagnostics-only and allocated/executed only when requested.
- Pipeline restore now tracks effective canonical stages deterministically instead of overlapping unordered stage masks.
- Alpha replay restores captured Firestorm alpha blend factors and depth-write state; replay fails closed if capture is incomplete.
- Full Firestorm MRT bindings are retained dynamically; there is no four-RTV truncation.
- Firestorm resource/view/pipeline destruction invalidates cached handles/state; direct D0/N0 views are invalidated before reuse.
- Direct/replay recursion guards are thread-local RAII depths. ReShade begin/finish effects uses a paired thread-local depth with mismatch self-healing.
- Overlay settings are edited locally and committed under the device mutex.
- GLSL files are authoritative; the embedded header is generated and verified at build time.
- Runtime counters expose fullscreen passes, Firestorm scene copies/writes, output generation, restore callbacks and invariant violations.

## v1.2.0 runtime regression observed
The first v1.2.0 Firestorm run compiled and loaded, but GTAO Active showed qualified alpha transitions with **0 direct GTAO attempts**, all GTAO semantics unbound, and a rapidly increasing `State restore capture/mismatch failures` counter. The cause was the v1.2.0 fail-closed restore gate requiring all five canonical pipeline stage slots to have been observed through ReShade before injection. Firestorm/OpenGL does not emit an independently observable pipeline bind for every fixed-function stage, so the gate rejected every pending alpha draw before the attempt counter.

v1.2.1 keeps deterministic per-stage restoration but restores every stage Firestorm actually exposed, requires only a captured shader-stage pipeline plus complete RTV/DSV + viewport state, and restores loose OpenGL state from the existing dynamic-state snapshot. This returns the execution gate to the behavior that was runtime-proven in v1.1 while preserving deterministic ordering.

The same run reported `Debug FX operating-mode gate: not found`. That advisory uniform is no longer required for correctness. In v1.2.1 Firestorm Baseline directly resets the existing `SLDirectGTAODebugView` UI uniform to 0, so baseline backbuffer safety works even with an older debug FX copy that predates `SLDirectGTAOOperationMode`.

## Static verification completed by coordinator
- `tests/validate_source.py`: PASS
- `cmake/ValidateSource.cmake`: PASS
- generated shader synchronization check: PASS

## Not yet validated
- MSVC compile of v1.2.1 on the user's ReShade checkout.
- Firestorm runtime transition sequence for the three modes.
- Exact visual/native equality of Baseline on the user's system.
- Final GTAO correctness; the raw AO collapse remains the active algorithmic fault after this corrective state/lifecycle pass.

## Next runtime test
1. Build/install with `SL_InstallLatest.ps1`.
2. Verify Firestorm Baseline counters remain zero and Debug FX shows the native frame.
3. Switch to Diagnostics -> Inputs only and inspect D0/N0.
4. Switch Diagnostics -> N dot V only; capture N dot V.
5. Switch Diagnostics -> Unoccluded baseline only; capture baseline.
6. Switch Diagnostics -> Core AO; confirm raw/denoised still reproduce the dark-field fault without changing Firestorm scene color.
7. Switch to GTAO Active and verify one scene copy/write plus one restore callback per successful run.
8. Return to Firestorm Baseline and verify native presentation immediately returns without restart.
