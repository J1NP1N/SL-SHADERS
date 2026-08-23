# SL SSR Background Depth v0.2 — Test A result

## Runtime result

Clear-only Firestorm diagnostic (`Test-SLSSRBackgroundDepthClearOnly-v0.2.5.ps1`) was applied, rebuilt, copied over the installed custom viewer, and tested.

Observed:

```text
Link / native pair: CYAN
Primary NATIVE RAW: white/far field with gray scene/avatar silhouettes
Background NATIVE RAW: solid black
```

The clear-only pass was intended to bind `mMainRT.ssrBackgroundDepth`, clear depth to raw `1.0`, draw nothing, and flush. Therefore the expected background raw display was solid white.

It was not.

## Important correction to the working diagnosis

This result means the current failure cannot be attributed to static geometry coverage, material pass selection, avatar exclusion, or the v0.2.4 camera-matrix hypothesis. The test contained no geometry draw at all.

The screenshots also show:

- primary raw/inverted diagnostics contain coherent spatial depth structure
- primary native linear depth contains coherent world/avatar structure
- signed background-minus-primary is strongly magenta over most geometry, consistent with the sampled background value being numerically near zero while primary depth is near the usual far/white range

So the current issue is global background-payload validity, not merely failure to recover wall depth behind avatar pixels.

## Confidence / process change

Previous iterations spent full Firestorm rebuilds on plausible but insufficiently isolated hypotheses. Stop doing that.

Do not make another full viewer rebuild for a single state guess. The next instrumented build should collect multiple facts at once, and subsequent viewer edits should use the direct CMake target (`firestorm-bin`) rather than the packaging build when possible.

## Remaining possibilities after Test A

The evidence does not yet distinguish between:

1. `renderSSRBackgroundDepth()` returning before the clear executes.
2. The auxiliary FBO/texture not containing the clear value despite the intended code path (for example another GL state such as scissor, or target state).
3. The native export referring to a valid-sized but wrong/stale texture object.
4. The ReShade v0.2.2 copy path reading/copying the auxiliary source incorrectly while the primary source works.

`Link = CYAN` proves exports/sizes/bridge registration, but it does **not** prove the auxiliary pass executed or that the source texture contains valid depth.

## Next diagnostic requirement

Before another geometry attempt, add instrumentation that reports at least:

- whether `renderSSRBackgroundDepth()` executed this frame / an execution counter
- which early-return gate, if any, prevented execution
- auxiliary GL texture ID and FBO completeness/status
- a native sample/readback of the auxiliary depth after clear, bypassing the ReShade semantic/copy path
- the corresponding primary native sample for comparison

This will separate Firestorm-side texture contents from ReShade-side publication in one build.

Also preserve the FPS regression as a separate tracked issue. The clear-only build still needs performance comparison because the bridge copies full-resolution primary/background resources each effect frame even when geometry re-rendering is removed.
