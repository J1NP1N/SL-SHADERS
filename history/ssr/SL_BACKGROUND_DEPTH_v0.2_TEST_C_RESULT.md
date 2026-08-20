# SL SSR Background Depth v0.2 — Test C result

Branch: `agent/ssr-background-depth`

## Test

Test C restored the static/non-rigged geometry pass after two prior control tests had proven the auxiliary depth target and ReShade path:

- Test A: clear-only depth `1.0` -> `Background NATIVE RAW` solid white.
- Test B: constant depth `0.5` -> `Background NATIVE RAW` uniform 50% gray.
- v0.2.7 also fixed the original invocation bug by moving `renderSSRBackgroundDepth()` from `display_cube_face()` into the actual main world deferred render.

## Screenshots / observed modes

The submitted diagnostic screenshots show:

- `Primary NATIVE RAW`: normal primary depth, mostly white with gray/darker avatar/world structure.
- `Background NATIVE RAW`: essentially solid white.
- `Primary NATIVE linear depth`: coherent scene depth with avatar visible.
- `Background NATIVE linear depth`: effectively far/empty.
- `Signed background minus primary`: green mainly over the avatar silhouette.
- `RAW signed bg-primary x4096`: green mainly over primary geometry including the avatar.
- `Recovered-behind-primary mask`: green avatar silhouette.
- `Recovered-behind-primary overlay`: green avatar silhouette over the scene.

## Interpretation

**Test C does not yet prove recovered wall/floor depth. It fails at the geometry-write stage.**

The key observation is `Background NATIVE RAW` remaining essentially solid white. White is the verified far clear value (`1.0`). Therefore the auxiliary depth target is being cleared successfully, but the attempted static/non-rigged draw is not writing usable depth into it.

The green avatar in the signed/recovered diagnostics is currently a false-positive consequence of comparing primary avatar depth (`D0 < 1`) against an all-far background value (`Dstatic = 1`). It must not be interpreted as recovered wall depth.

This narrows the remaining problem to the Firestorm static geometry draw itself. The following are already proven and should not be re-debugged unless new evidence appears:

1. main-world invocation executes;
2. auxiliary depth-only FBO is complete;
3. depth clear works (`1.0` native readback and white in ReShade);
4. constant `0.5` propagates correctly through export -> ReShade backup -> FX sampler;
5. primary native depth bridge works.

## Next diagnostic

Instrument the geometry pass rather than changing more GL state blindly. On one build, record enough information to distinguish:

- render-map batches are empty / wrong pass types;
- batches exist but draw calls are skipped;
- draw calls execute but the chosen shader/vertex state does not write depth.

At minimum log `hasRenderBatches(type)` / render-map sizes for each requested pass, plus a native depth readback after the geometry draw. If batches are present but the depth remains `1.0`, then inspect the exact normal Firestorm shadow/depth-only draw sequence and shader vertex-mask requirements.

## Performance note

Do not optimize the final pass yet, but continue tracking the FPS regression. The current prototype still enables an extra full-resolution pass and ReShade resource copies whenever the bridge is active.
