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
- N0 is populated and spatially coherent, but its diagnostic color distribution is suspicious and still needs space/input verification.
- D0 is now confirmed populated and spatially coherent. The scene depth ordering and silhouettes are present; D0 binding/sampling is not the cause of the globally dark AO field.

Source audit after D0 proof:
- Firestorm `globalF.glsl` uses the same stereographic XY normal decode currently used by the direct GTAO module.
- Firestorm deferred vertex paths generate the stored normal in view space.
- Therefore do not replace the N0 decode formula speculatively. The next fault isolation should be the GTAO horizon/basis math and the exact sampled N0 values/coordinate convention at runtime.

## Current gate
The direct GPU path, debug-export path, D0 input, and AO target writes are proven alive. Do not redesign alpha handling or tune radius/strength/denoise yet.

Next action:
1. Instrument the raw pass with minimal basis diagnostics (decoded N0 facing term and unoccluded baseline/visibility) to determine why visibility collapses toward zero.
2. Keep D0/N0 semantics and Firestorm decode unchanged unless that diagnostic proves an input-space mismatch.
3. Remove the redundant failed pre-alpha attempt only after the successful boundary is identified unambiguously.

Source milestone: `addons/SLGTAO/direct-prealpha-v1.1d-debug/`.
Handoff package SHA-256: `9d1f0e7dd4ff39f1bf569b6571fcd2a3d0f7e74e0ccc586bad1e1e71b038522b`.
