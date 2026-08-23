# SL Direct GTAO — v1.1g clean passthrough

Date: 2026-08-23
Branch: `agent/direct-gtao-integration`

Purpose: make the add-on a clean producer while `SL_DirectGTAO_Debug.fx` is used as the consumer/viewer.

## Passthrough contract
When `Passthrough (clean FX validation)` is enabled:

- direct pre-alpha GTAO still executes;
- D0/N0/raw/denoised/N·V/baseline semantics remain exported;
- the opaque Firestorm scene-color target is restored unchanged by the direct composite pass;
- the add-on `Boundary diagnostic` output is disabled;
- legacy `SL_ALPHA_PRE_COLOR` / `SL_ALPHA_POST_COLOR` / `SL_ALPHA_MASK` diagnostics are unbound;
- Firestorm alpha replay into the old coverage mask is skipped;
- PRE/POST alpha-recompose captures are skipped.

The Firestorm scene target is remembered directly from the qualified alpha draw without taking a boundary diagnostic snapshot, so safe-phase GTAO resource arming still works in clean passthrough mode.

## Validation
Enable `Passthrough (clean FX validation)`, then use `SL_DirectGTAO_Debug.fx` to inspect:
- Raw AO
- Denoised AO
- D0
- N0
- N dot V
- Unoccluded slice baseline

No GTAO math, alpha classification, or SSR path is changed by this build.
