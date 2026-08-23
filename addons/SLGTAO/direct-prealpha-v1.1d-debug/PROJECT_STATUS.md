# SL Direct GTAO — v1.1d debug validation

## Preserved runtime proof
- Firestorm straight-alpha transition classifier remains the gate.
- No `effect_runtime::render_technique()` call occurs inside Firestorm callbacks.
- Alpha geometry continues through Firestorm normally after the direct pass.

## v1.1d corrections
- Direct GTAO execution is deferred from blend-state transition to the first qualified alpha draw, immediately before that draw.
- The current Firestorm alpha shader `inv_proj` uniform is captured directly from the active OpenGL program.
- Direct GTAO is armed only from `reshade_begin_effects`, outside application draw callbacks.
- `GTAO applied` telemetry increments only when `execute_pre_boundary()` actually succeeds.
- Direct fullscreen draws are recursion-guarded from hook bookkeeping/replay.
- ReShade diagnostics are exposed as `SL_GTAO_D0`, `SL_GTAO_N0`, `SL_GTAO_RAW`, and `SL_GTAO_DENOISED`.
- `SL_DirectGTAO_Debug.fx` visualizes final passthrough/raw AO/denoised AO/D0/N0.

## Runtime result — 2026-08-23
Screenshots confirm:
- `SL_GTAO_D0`: BOUND
- `SL_GTAO_N0`: BOUND
- `SL_GTAO_RAW`: BOUND
- `SL_GTAO_DENOISED`: BOUND
- Direct GTAO applied last frame: 1
- Direct GTAO attempts last frame: 2
- Alpha transitions qualified last frame: 2
- Direct GTAO failures and `inv_proj` capture failures rise together; the redundant failed attempt is projection-capture related.

Visual diagnostics:
- Raw AO is populated but overwhelmingly dark; the raw field is not yet valid for final AO.
- Denoised AO is populated and similarly dark; denoise is processing an already-invalid/over-occluded raw field.
- N0 is populated and spatially coherent enough to show scene geometry/silhouettes, but is strongly biased toward a nearly uniform encoded direction and still needs decode/space verification.
- A D0 diagnostic screenshot is still needed before changing GTAO math.

## Current gate
The direct GPU path and debug-export path are proven alive. Do not redesign alpha handling.

Next action:
1. Capture `D0` diagnostic.
2. If D0 is coherent, audit N0 decode/space and view-position reconstruction before tuning radius/strength/denoise.
3. Remove the redundant second pre-alpha attempt only after the successful boundary is identified unambiguously.

Source milestone: `addons/SLGTAO/direct-prealpha-v1.1d-debug/`.
Handoff package SHA-256: `9d1f0e7dd4ff39f1bf569b6571fcd2a3d0f7e74e0ccc586bad1e1e71b038522b`.
