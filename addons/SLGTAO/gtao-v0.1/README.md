# SL GTAO v0.1 — Full-Resolution D0 Reference

Branch: `agent/gtao-reference`

This is a standalone correctness-first GTAO implementation for the current Firestorm + ReShade bridge. It is intentionally isolated from SSR.

## Input contract

- Visible scene depth: `SL_DEPTH_PRIMARY_NATIVE` / D0.
- Native normal payload: `SL_NORMALS`.
- Final color: current `ReShade::BackBuffer`.
- Projection/viewport data: the existing Firestorm bridge uniforms used by the validated native D0 path.

`Dstatic` / `SL_DEPTH_BACKGROUND` is not declared or sampled. Avatars and rigged objects therefore participate wherever they are present in D0.

`SL_NORMALS` is decoded with the current Firestorm stereographic XY decode already used by the avatar-receiver path:

- `fenc = encoded.xy * 4 - 2`
- reconstruct XY with the stereographic scale
- reconstruct Z as `1 - 0.5 * dot(fenc,fenc)`
- normalize

The blue/alpha payload channels are not used as normal components.

## Pipeline

1. `DepthDiscontinuity`
   - Full-resolution D0 edge classification.
   - Immediate view-depth jumps are the primary rejection signal.
   - Normal disagreement strengthens an actual depth edge but cannot reject a continuous-depth corner by itself.

2. `RawGTAO`
   - Full-resolution horizon search directly against D0.
   - Each slice searches both directions.
   - Search radius is specified in view-space units and projected to pixels from the exact inverse projection at the center depth.
   - Samples outside the physical AO radius receive zero weight.
   - Immediate silhouette discontinuities stop the corresponding horizon direction before unrelated foreground/background geometry can generate a halo.
   - No temporal history, no Hi-Z, no SSR inputs.

3. `BilateralHorizontal` / `BilateralVertical`
   - Full-resolution separable bilateral AO filter.
   - Uses D0 depth, decoded native normals, and the discontinuity mask.
   - `GTAO - Enable Bilateral Denoise` defaults to **OFF**. Do not tune the filter until Raw GTAO is correct.

4. `CompositeAndDiagnostics`
   - Multiplies the current backbuffer by the selected AO visibility.
   - `GTAO - Strength = 1` preserves the raw physical response; higher values scale the occlusion term.

## Required diagnostics

`GTAO - Diagnostic View` exposes:

1. Final AO composite
2. Linear D0
3. Decoded normals
4. Raw GTAO
5. Filtered GTAO
6. Depth-discontinuity rejection
7. Final AO contribution
8. Passthrough

The filtered view remains usable while denoise is disabled; it should then be identical to raw GTAO.

## Validation order

Do not judge the final composite first.

1. **Linear D0** — verify avatar, rigged-object, terrain, and static geometry silhouettes align exactly with the visible frame.
2. **Decoded normals** — verify orientation and continuity. If this view is wrong, stop; GTAO cannot be correct.
3. **Depth-discontinuity rejection** — inspect avatar outlines, geometry silhouettes, and near/far transitions. It should be narrow and attached to the actual D0 edge, not a broad halo.
4. **Raw GTAO** with denoise OFF — verify contact/corner darkening, no detached avatar halo, and no dark fringe on the opposite side of a silhouette.
5. Only after raw passes, enable the bilateral denoise and compare **Raw GTAO** vs **Filtered GTAO**.
6. Inspect **Final AO contribution**, then the final composite.

A runtime screenshot or capture is still required to prove correctness in Firestorm. Repository/static validation cannot prove the renderer's live resource bindings or visual result.

## Starting presets

These are explicit starting points, not hard-coded modes.

| Preset | Radius | Slices | Steps/side | Denoise | Filter radius | Intended use |
| --- | ---: | ---: | ---: | --- | ---: | --- |
| Reference | 1.25 | 8 | 8 | Off | 2 | Establish raw correctness |
| Quality | 1.25 | 6 | 6 | On | 2 | High-quality live use after validation |
| Balanced | 1.10 | 4 | 4 | On | 2 | Default performance target |
| Performance | 0.90 | 3 | 3 | On | 1 | Lower sample cost / live viewer |

Keep `Strength = 1.0`, `Falloff Start = 0.65`, and the default silhouette thresholds while validating. Change one variable family at a time.

Approximate raw horizon sample budgets are:

- Reference: 128 depth samples/pixel plus edge probes.
- Quality: 72 depth samples/pixel plus edge probes.
- Balanced: 32 depth samples/pixel plus edge probes.
- Performance: 18 depth samples/pixel plus edge probes.

The projected-radius cap is a separate safety bound and does not change the nominal view-space radius unless the requested radius would exceed the cap.

## Scope guard

This branch adds only `addons/SLGTAO/gtao-v0.1/`.

It does not modify:

- CORE SSR
- Hi-Z SSR
- Spatial SSR
- Avatar SSR
- the v0.49 avatar thickness interval
- MAIN

There is no temporal accumulation in v0.1.
