# SL Direct GTAO — v1.2.0 corrective operating modes

Date: 2026-08-23
Branch: `agent/direct-gtao-integration`

## Runtime proof preserved from prior builds
- Firestorm straight-alpha boundary detection is stable without nested ReShade execution.
- Direct GTAO reaches the proven pre-alpha boundary and has applied once per frame in prior runtime tests.
- D0, N0, raw AO and denoised AO export paths were proven live.
- D0 is spatially coherent.
- Firestorm N0 encoding matches the direct GTAO stereographic XY decode.
- Raw/denoised AO are currently populated but overwhelmingly dark; AO correctness is not yet validated.

## v1.2.0 corrective changes
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

## Static verification completed by coordinator
- `tests/validate_source.py`: PASS
- `cmake/ValidateSource.cmake`: PASS
- generated shader synchronization check: PASS

## Artifact
- `packages/latest/SL_GTAO_Direct_v1_2_0_FirestormModes.zip`
- SHA-256: `c1574fae096f696276c077e55abef49e641202386e8e3bc3ae7545e77e287d47`
- The ZIP contains the full v1.2.0 source tree, build scripts, debug FX, authoritative GLSL, validation scripts, and engineering report.

## Not yet validated
- MSVC compile of v1.2.0 on the user's ReShade checkout.
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
