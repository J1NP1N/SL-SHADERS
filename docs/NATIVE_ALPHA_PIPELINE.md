# Native alpha geometry pipeline

Status: implementation workstream, not runtime-proven yet.

Branch: `agent/native-alpha-geometry`

## Purpose

Expose Firestorm's actual alpha/cutout geometry to ReShade without reconstructing material identity from framebuffer alpha, D0 validity, normals, specular data, or other post-process heuristics.

This work is a dependency for GTAO. It is intentionally independent of CORE/Hi-Z/Spatial/Avatar SSR.

## Pinned upstream source

Firestorm repository: `FirestormViewer/phoenix-firestorm`

Inspected commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294` (2026-08-20)

Important paths:

- `indra/newview/lldrawpoolalpha.cpp`
- `indra/newview/pipeline.cpp`
- `indra/newview/llviewershadermgr.cpp`
- `indra/newview/llviewershadermgr.h`
- `indra/newview/app_settings/shaders/class1/deferred/alphaV.glsl`
- `indra/newview/app_settings/shaders/class1/deferred/shadowAlphaMaskV.glsl`
- `indra/newview/app_settings/shaders/class1/deferred/shadowAlphaMaskF.glsl`
- `indra/newview/app_settings/shaders/class1/deferred/pbrShadowAlphaMaskV.glsl`
- `indra/newview/app_settings/shaders/class1/deferred/pbrShadowAlphaMaskF.glsl`
- `indra/newview/app_settings/shaders/class1/deferred/pbrShadowAlphaBlendF.glsl`

## Proven renderer facts

Firestorm does not discover alpha geometry from framebuffer alpha. Geometry is classified before rasterization into explicit alpha/alpha-mask render passes and pools.

Clouds are a separate sky path (`LLDrawPoolWLSky`, `renderSkyCloudsDeferred()`, `RENDER_TYPE_CLOUDS`). Cloud opacity therefore must never be treated as an alpha-material semantic.

Ordinary forward alpha frequently renders with scene depth writes disabled. D0 alone cannot represent the visible depth of all alpha geometry.

Firestorm's shadow path already demonstrates a reusable render-classification set for alpha geometry. It explicitly renders alpha blend, alpha mask, legacy material mask variants, rigged equivalents, and GLTF/PBR alpha-mask content without including sky/cloud render types.

The project's existing native SSR bridge established two additional architectural rules that are reused here:

1. auxiliary native render passes must execute while the main Firestorm render maps are still populated;
2. ReShade should copy Firestorm-owned OpenGL textures into ReShade-owned shader-readable resources before publishing semantics.

## Required ReShade semantics

The native pipeline publishes four semantics:

- `SL_DEPTH_ALPHA_NATIVE`
- `SL_NORMAL_ALPHA_NATIVE`
- `SL_ALPHA_COVERAGE`
- `SL_ALPHA_MATERIAL`

The four values are not four independent captures. They describe one coherent nearest eligible alpha/cutout fragment.

### Coherence invariant

For every native pixel with an alpha fragment:

`{ depth, normal, coverage, material-class }` must belong to the fragment that won the private alpha depth test.

The Firestorm implementation therefore uses one private render target containing:

- one native depth attachment;
- one RGBA metadata color attachment.

Depth testing selects the winning fragment and the same draw writes its metadata.

The ReShade bridge copies those two native textures once per frame. The three metadata semantics intentionally alias the same ReShade-owned metadata copy. Consumers select the required channels.

## Metadata layout v0.1

Private metadata target: RGBA16F.

- `R,G`: Firestorm-compatible stereographic encoded view-space geometry normal.
- `B`: fragment coverage.
- `A`: alpha material class.

Material-class encoding:

- `0.0`: no eligible alpha fragment;
- `0.5`: alpha-blended geometry;
- `1.0`: alpha-mask/cutout geometry.

Coverage encoding:

- blended geometry: surviving fragment alpha/coverage in `[0,1]`;
- cutout/masked geometry: `1.0` after the material cutoff survives;
- no eligible fragment: `0.0`.

### v0.1 normal limitation

The first implementation stores the interpolated geometric/view-space surface normal. It does not yet reproduce material normal-map perturbation in the private alpha replay.

That is intentional for the first GTAO dependency: GTAO primarily needs a coherent geometric surface orientation at the same depth winner. If runtime testing demonstrates that alpha normal maps materially affect rejection/denoise quality, normal-map perturbation can be added as a separate refinement after the pipeline is proven.

## Inclusion contract

Include visible world geometry routed through alpha blend and alpha-mask/cutout classes, including required rigged equivalents. The Firestorm shadow classification is the starting reference, including:

- `PASS_ALPHA` / alpha pool content;
- `PASS_ALPHA_MASK`;
- `PASS_FULLBRIGHT_ALPHA_MASK`;
- legacy material/specular/normal/normspec alpha-mask variants;
- `PASS_GLTF_PBR_ALPHA_MASK`;
- corresponding rigged variants;
- PBR/GLTF alpha-blend content routed through the alpha pool.

The capture must explicitly exclude HUD/UI, sky, WL sky, clouds, reflection/cube renders, impostor-only auxiliary renders, and other non-main-world passes.

## Depth contract

`SL_DEPTH_ALPHA_NATIVE` is raw Firestorm-native depth in the same camera projection/depth convention as D0. The private capture must not modify the normal scene depth buffer.

The GTAO consumer resolves:

`Dvisible = nearest(D0, Dalpha)`

and selects the matching normal:

- if D0 wins: `Nvisible = SL_NORMALS`;
- if Dalpha wins: `Nvisible = SL_NORMAL_ALPHA_NATIVE`.

A single nearest alpha layer is an accepted first milestone. This is not an A-buffer and does not attempt to represent multiple stacked translucent surfaces.

## Firestorm -> ReShade transport

Firestorm exports C-ABI getters from the viewer executable:

- `SL_SetAlphaGeometryCaptureEnabled(int)`
- `SL_GetAlphaGeometryDepthInfo(texture,width,height)`
- `SL_GetAlphaGeometryMetaInfo(texture,width,height)`

The ReShade add-on resolves those exports with `GetProcAddress`, wraps the OpenGL texture IDs as ReShade resources, validates dimensions/formats, copies them into ReShade-owned shader-readable resources at `reshade_begin_effects`, then publishes the four semantics.

The metadata semantics deliberately bind the same resource view:

- `SL_NORMAL_ALPHA_NATIVE` -> metadata RGBA copy;
- `SL_ALPHA_COVERAGE` -> metadata RGBA copy;
- `SL_ALPHA_MATERIAL` -> metadata RGBA copy.

This prevents channel lifetime/skew bugs.

## Runtime acceptance test

Do not connect this to GTAO first. Prove the native pipeline independently.

Use one scene containing, at minimum:

- visible clouds;
- alpha-blended hair or another blended rigged object;
- alpha-mask/cutout foliage or similar geometry;
- opaque geometry behind those targets.

Return these diagnostic views:

1. bridge/status;
2. raw alpha depth occupancy;
3. decoded alpha normal;
4. alpha coverage;
5. alpha material class;
6. metadata semantic coherence.

Acceptance criteria:

- clouds are absent from alpha depth, coverage, and class;
- blend geometry appears as blend class and preserves useful coverage;
- cutout geometry appears as mask class with surviving coverage `1`;
- alpha depth silhouettes register to the visible alpha geometry;
- normals belong to the same winning alpha fragments;
- no evidence that D0 was modified;
- the three metadata semantics sample the same payload.

Only after those pass should `agent/gtao-reference` consume the semantics.

## Scope guard

This workstream must not modify:

- CORE SSR;
- Hi-Z SSR;
- Spatial SSR;
- Avatar SSR;
- GTAO algorithm code before native runtime proof.

Optional later semantic `SL_CLOUD_MASK` remains a separate renderer export and is not part of this GTAO dependency.