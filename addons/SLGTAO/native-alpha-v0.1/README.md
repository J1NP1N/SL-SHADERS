# SL native alpha geometry v0.1

This checkpoint builds the Firestorm -> ReShade native dependency required by GTAO v0.14. It does **not** change GTAO or SSR tracing.

## Required viewer baseline

Apply this only to the validated custom Firestorm native backbone used by SSR v0.49, with `Fix-SLSSRAvatarBackDepthCoverage-v0.49.1.ps1` already applied. The patch fails closed if the v0.49 exports or the `SLSSR_AVBACK_COVERAGE_V0491` marker are absent.

Existing semantics remain unchanged:

- `SL_DEPTH_PRIMARY_NATIVE` / D0
- `SL_DEPTH_BACKGROUND` / Dstatic
- `SL_COLOR_BACKGROUND` / Cstatic
- `SL_DEPTH_AVATAR_BACK` / DavatarBack

## New native contract

- `SL_ALPHA_MATERIAL`: R=1 only where an eligible alpha/cutout geometry fragment won the private depth test.
- `SL_DEPTH_ALPHA_NATIVE`: depth attachment from that same material capture, raw convention matching D0.
- `SL_ALPHA_COVERAGE`: R=authored alpha for `PASS_ALPHA`; R=1 for surviving alpha-mask/cutout fragments.

Sky, WL sky and clouds are excluded structurally because the capture never invokes those render pools. Grass and the dedicated tree pool are included explicitly because Firestorm renders them as alpha-tested cutout vegetation.

The first proof uses two identical private depth-writing replays. This is intentionally conservative: material/depth and coverage independently converge to the same nearest eligible alpha fragment without adding MRT plumbing to Firestorm's shader manager.

## Firestorm changes

`Apply-SLNativeAlphaGeometry-v0.1.ps1` modifies:

- `indra/newview/pipeline.cpp`
- `indra/newview/pipeline.h`
- `class1/deferred/shadowAlphaMaskF.glsl`
- `class1/deferred/pbrShadowAlphaMaskF.glsl`
- `class1/deferred/treeShadowF.glsl`

It adds full-resolution private RGBA16F+depth targets and C exports:

- `SL_SetAlphaGeometryEnabled`
- `SL_GetAlphaMaterialInfo`
- `SL_GetAlphaDepthInfo`
- `SL_GetAlphaCoverageInfo`

The normal shadow path is preserved when `sl_alpha_capture_output == 0`. Capture mode removes shadow-only semi-transparent dithering and uses a 0.004 alpha-blend cutoff instead of Firestorm's shadow `ALPHA_BLEND_CUTOFF` (0.598).

## Eligible replay classes

Both non-rigged and rigged variants are replayed where applicable:

- `PASS_ALPHA`
- `PASS_ALPHA_MASK`
- `PASS_GRASS` and the `POOL_TREE` cutout pool
- `PASS_FULLBRIGHT_ALPHA_MASK`
- `PASS_MATERIAL_ALPHA_MASK`
- `PASS_SPECMAP_MASK`
- `PASS_NORMMAP_MASK`
- `PASS_NORMSPEC_MASK`
- `PASS_GLTF_PBR_ALPHA_MASK`

System avatar opaque skin is intentionally **not** replayed here; v0.49.1 includes it for DavatarBack, but it is not alpha geometry.

## Build/install

1. Apply the Firestorm patch:
   `powershell -ExecutionPolicy Bypass -File .\Apply-SLNativeAlphaGeometry-v0.1.ps1 -FirestormRoot C:\firestorm-slssr\phoenix-firestorm`
2. Rebuild `firestorm-bin` using the same build tree as the validated v0.49 viewer.
3. Build the ReShade add-on from a VS developer prompt:
   `build-msvc.bat <ReShadeRoot>`
4. Install `build\SLNativeAlphaLink.addon` next to the existing project ReShade add-ons.
5. Install `SL_NativeAlphaProof_v0_1.fx` into the active ReShade shader directory.

## First runtime proof

Disable GTAO and enable only `NATIVE ALPHA — v0.1 Proof` (plus the existing bridge/core effect that publishes `SLBridgeViewport` if required for aligned display).

Use a scene containing:

- EEP clouds clearly visible behind geometry;
- alpha-blended hair or a transparent textured prim;
- cutout foliage/fence/alpha-mask content;
- ideally both rigged and non-rigged examples.

Return these views separately:

1. `Material classification`
2. `Native alpha depth (raw)`
3. `Coverage`
4. `Registration/status`

Acceptance:

- alpha/cutout geometry appears in material;
- clouds/sky are completely absent;
- depth silhouettes correspond to the same alpha geometry;
- blended coverage contains fractional values instead of a binary shadow dither;
- cutout survivors are solid coverage;
- status is white (all three valid) after the first armed frame.

Only after this passes should GTAO v0.14 consume the semantics.

## Known v0.1 limitation

A dedicated alpha normal is intentionally deferred. GTAO v0.14 currently solves native alpha classification/depth/coverage first and continues to use `SL_NORMALS`. If runtime proof shows alpha surfaces need their own orientation for receiving/filtering AO, add `SL_NORMAL_ALPHA_NATIVE` from the same replay as the next native semantic.
