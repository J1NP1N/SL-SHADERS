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

## Validation target
A successful frame should show one qualified transition, one direct attempt, one direct applied run, zero projection failures, and all four debug semantics bound after the pass has executed.

Full source package: `packages/SLGTAO/SLAlphaGTAOHook_direct_merge_v1_1d_debug.zip`.
