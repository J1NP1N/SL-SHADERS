# SL SSR Background Depth v0.1 — native static layer

## Diagnosis entering this build

The magenta-wall fixture makes the avatar-shaped dark region obvious. In the `v0.35 vs Hi-Z hit mask`, the visible dark region is BLACK: neither the old tracer nor the Hi-Z tracer has an accepted reflection hit there.

That changes the working diagnosis from an extra false hit to a missing reflected-background hit: primary camera depth contains the avatar while the static wall behind it is unavailable to single-layer SSR.

## v0.1 structural test

This build adds a second camera-aligned Firestorm depth target. It is intentionally **not generic depth peeling yet**. It re-renders only non-rigged static opaque material families using Firestorm's existing depth-only deferred shadow program. Rigged/avatar geometry is excluded, so the static wall/floor should become visible in the auxiliary depth where the avatar occupies primary depth.

Firestorm public source base used for the patcher:

`FirestormViewer/phoenix-firestorm@f0d4a81c5ded331fb35d19e88544f0d22723bee5`

Native exports:

- `SL_GetSSRBackgroundDepthInfo(texture,width,height)`
- `SL_SetSSRBackgroundDepthEnabled(enabled)`

ReShade semantic:

- `SL_DEPTH_BACKGROUND`

## First runtime

Use the same magenta wall / reflective floor / avatar fixture.

1. `SL Background Depth v0.1 - Native Static Layer`
2. `Background Depth Display -> Link / native payload`
   - expected CYAN
3. `Recovered-behind-primary overlay`
   - expected GREEN over much of the avatar silhouette where the static wall is farther behind primary avatar depth
4. `Recovered-behind-primary mask`
   - expected mostly BLACK elsewhere and GREEN where a farther static layer is recovered
5. compare `Primary linear depth` and `Background linear depth`

## Pass condition

The auxiliary layer visibly recovers farther static wall/floor geometry through the primary avatar silhouette.

If this passes, the next tracer revision keeps primary depth as layer 0 and consults `SL_DEPTH_BACKGROUND` only when the primary layer is an occluder/miss.

## Known v0.1 limits

- rigged exclusion is a targeted structural test, not generic second-nearest depth
- non-rigged attachments may still appear
- alpha-masked cutouts are not represented accurately yet
- no SSR behavior is changed in this build
- OpenGL ReShade view publication is pinned to the current ReShade OpenGL handle encoding

Package: `SL_SSR_BackgroundDepth_v0_1_SourceBridge.zip`
SHA-256: `f31353095108d1ff4e460dfe9108528e2775552c14a288032b8f65b723e2495e`
