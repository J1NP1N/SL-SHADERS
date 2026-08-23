# SSR Temporal v0.1 — standalone reprojection test

Baseline producer: `SL SSR v0.35 - Legacy Resolve`.

This is deliberately a separate effect. v0.35 remains the trace + spatial resolve producer. A tiny ReShade add-on (`SLSSRTemporalLink`) exposes v0.35's private `SLSSRResolvedTex` and `SLSSRMetaTex` as `SL_SSR_RESOLVED` / `SL_SSR_META` semantics for the temporal consumer.

## Temporal core

Reuses the already-proven HybridGI camera-history contract:

- Firestorm `inv_modelview_delta` equivalent: `SLGIInvModelviewDeltaC0..C3`
- motion validity: `SLGIMotionValid`
- current receiver is reprojected into previous camera space
- previous depth and normal reject disocclusion/dynamic mismatch
- previous SSR is clamped to the current local SSR neighborhood
- camera motion and clamp distance reduce history trust
- previous history is overwritten only after temporal resolve consumes it

v0.1 is conservative: current SSR confidence must be nonzero before history can contribute. It does not resurrect an old hit where the current frame has no accepted SSR hit.

## Composite contract

Technique order must be:

1. `SL SSR v0.35 - Legacy Resolve`
2. `SL SSR Temporal v0.1 - Reprojected History`

Temporal reconstructs v0.35's current presentation-space SSR contribution, reconstructs the temporally resolved contribution, and applies only:

`temporal contribution - current v0.35 contribution`

Therefore disabling Temporal returns directly to v0.35 instead of double-applying SSR.

## CPU / GPU split

CPU add-on work:

- inter-effect texture binding
- frame index bookkeeping
- mirroring the small set of v0.35 material/composite controls into the temporal consumer

GPU work:

- per-pixel reprojection
- previous depth/normal rejection
- neighborhood clamp
- temporal accumulation

Per-pixel history is intentionally not read back to CPU because the synchronization/readback cost would exceed the shader arithmetic saved.

## Defaults

- `Temporal Accumulation = 1`
- `Temporal History Weight = 0.86`
- `Temporal Depth Rejection = 0.015`
- `Temporal Normal Agreement = 0.90`
- `Temporal Neighborhood Clamp = 0.25`
- `Motion Trust Start = 1.5 px`
- `Motion Trust End = 18 px`

## First runtime test

1. Close Firestorm before installing; this package builds/installs an `.addon`.
2. Keep v0.35 `Long-Ray Ghost Fade = 0`.
3. Verify the technique order above.
4. `Temporal Display -> Link / motion status`: link and motion must both report valid.
5. `History acceptance`: stable opaque receivers should trend green; disocclusions/avatar edges should reject red.
6. Slowly pan the camera and verify `Reprojected motion pixels` responds.
7. Compare `Current resolved SSR input` vs `Temporal resolved SSR` while stationary and while slowly panning.
8. Return `Final temporal correction` and report any trails/smearing on the avatar or nearby geometry.

ReShade Performance Mode must remain OFF because the link add-on mirrors effect uniforms by name.

## Package

`SL_SSR_Temporal_v0_1_Interop.zip`

SHA-256: `36311c474690b5b563a9909ce3af786ceb828396aa5ee602af5a9c0b093d6a70`
