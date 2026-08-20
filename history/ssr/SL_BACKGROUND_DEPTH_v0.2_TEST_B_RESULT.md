# SL SSR Background Depth v0.2 — Test B result

Date: 2026-08-20

Branch: `agent/ssr-background-depth`

## Test B

The auxiliary Firestorm depth target was forced to a constant raw depth of `0.5` with no geometry draw.

Expected ReShade result:

`Background NATIVE RAW = uniform 50% gray`

Observed result:

**PASS — uniform gray.**

This follows the successful Test A result where Firestorm natively reported a complete auxiliary FBO with `center=1`, `corner=1`, `gl_error=0`, and ReShade displayed the background raw texture as solid white.

## Conclusion

The following path is now proven end-to-end for the auxiliary background depth texture:

Firestorm auxiliary depth FBO -> depth texture -> exported OpenGL texture ID -> v0.2.2 ReShade backup copy -> `SL_DEPTH_BACKGROUND` -> FX sampling.

The prior solid-black result was not a layering problem and was not a ReShade sampling problem. The major root cause was that the original Firestorm patch inserted `renderSSRBackgroundDepth()` into `display_cube_face()` rather than the main world deferred render. The main invocation was corrected by v0.2.7.

## Next

Proceed to Test C: restore the non-rigged/static geometry draw and verify that `Background NATIVE RAW` shows world depth while avatar/rigged geometry is absent, allowing wall/floor depth to remain visible through the avatar silhouette.
