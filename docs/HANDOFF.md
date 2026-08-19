# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The remaining camera-dependent missing avatar reflection is upstream in `TraceSSR` and follows the upside-down silhouette of the avatar reflection.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.24 SilhouetteEdge — PENDING RUNTIME**.

## Runtime status

- v0.10 MainPassGate: PASS — full-resolution main-pass `specularRect` acquisition proven.
- v0.11 MainPassConsume: FAIL/informative — borrowed private GL texture sampled black in FX.
- v0.12 ReShadePublish: PASS — ReShade-owned material publication fixed sampling.
- v0.13 LegacyRGBResponse: PASS — legacy `specularRect.rgb` drives SSR even when alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: CONCEPT PASS — diffuse-only legacy surfaces can receive conservative SSR without authored spec maps.
- v0.15 PBRAlphaProbe: INCONCLUSIVE — known PBR alpha-blend glass fixture did not light up; glass work parked.
- v0.16 EnergyComposite: PARTIAL PASS — dark cast-shadow/base bleed removed/reduced.
- v0.17 DisocclusionSkip: separate ORANGE class established. **Keep `Disocclusion Skips = 3`**; this is the known working setting for that separate problem.
- v0.18 RayRejectReasons: target missing reflection classified BLUE/no accepted crossing.
- v0.19 TraceBudget: FAIL/informative — target persists with enlarged trace range.
- v0.20 BackgroundEntry: FAIL/informative — background-entry recovery did not identify target.
- v0.21 NoHitHistory: PASS diagnostic — target is YELLOW/mixed-sign no-hit with skips=3.
- v0.22 CrossingPath: PASS diagnostic — target is ORANGE: a real negative-to-positive candidate reaches refinement but remains oversized.
- v0.23 DeepRefine: FAIL/informative — increasing binary refinement from 5 to 9 iterations does **not** remove the target; target remains ORANGE and final composite still has the missing silhouette.
- v0.24 SilhouetteEdge: PENDING — conservatively recovers only a terminal oversized candidate that converges to a tight foreground depth edge after the normal disocclusion skip budget is exhausted.

## Proven facts for the current artifact

- The problem is upstream of material weighting/composite; it exists in ray-hit diagnostics.
- `Hit Thickness` is not the fix; testing up to 0.30 did not fill the region.
- Total ray range is not the fix.
- The ray samples real geometry on both sides of the depth relation.
- The ray forms the correct `previousDelta < 0 && delta >= 0` crossing candidate.
- More binary refinement does not make the refined positive sample fall within global `Hit Thickness`.
- Therefore the target is a **screen-depth discontinuity / silhouette-entry acceptance problem**, not under-refinement.
- ORANGE/disocclusion and the current silhouette target must not be conflated. Keep `Disocclusion Skips = 3` unless specifically testing disocclusion.

## v0.23 result

Runtime screenshots on v0.23 show:

- `No-hit crossing candidate path`: avatar-reflection target still ORANGE.
- `Final composite`: same missing upside-down avatar-shaped reflection region remains.
- `Disocclusion Skips = 3` and `Hit Thickness = 0.18` retained.

v0.23 changed only `SL_SSR_BINARY_STEPS: 5 -> 9`, so deeper binary refinement is ruled out as the controlling fix.

Runtime record commit: `25c4f45ba5d3ccd222287aff7dc919a9bdf3ffd7`.

## v0.24 SilhouetteEdge

FX-only isolated test. v0.23's 9 binary steps remain.

The normal disocclusion logic runs first and may still skip up to 3 oversized crossings. Only when that skip budget is exhausted does v0.24 consider a terminal silhouette recovery.

A terminal oversized candidate is accepted only if:

- the refined negative side is valid geometry with `delta < 0`;
- the refined positive side is valid and still `finalDelta > Hit Thickness`;
- the positive side represents a substantial jump to **nearer scene depth**;
- the refined bracket endpoints are within a tight full-resolution pixel span.

Defaults:

- `Silhouette Edge Recovery = 1`
- `Silhouette Edge Confidence = 0.60`
- `Silhouette Min Depth Jump = 0.25`
- `Silhouette Max Pixel Span = 2.0`
- keep `Disocclusion Skips = 3`
- keep `Hit Thickness = 0.18`

New diagnostic:

`Display Mode -> Silhouette-edge recovered hit mask`

WHITE means the accepted hit came specifically from the new terminal silhouette-edge path.

Runtime test:

1. Hot-install `SL_SSR_v0_24_SilhouetteEdge.zip`; Firestorm may remain open.
2. Verify technique `SL SSR v0.24 - Silhouette Edge`.
3. Keep `Disocclusion Skips = 3` and `Hit Thickness = 0.18`.
4. Return:
   - `Silhouette-edge recovered hit mask`
   - `Final composite`

Success: the upside-down avatar-shaped missing region lights in the new mask and fills in the composite without widespread false edge reflections.

Source delta commit: `cac5b0c0bb5e14b53ddfe3671313288ad9df0752`.

Local package:

- `SL_SSR_v0_24_SilhouetteEdge.zip`
- SHA-256 `efe1d1c529b0e3fa879dfb2ecf97f3655606f1e5c817277e0b7b62bcb5d89ab9`

## Glass checkpoint

Known fixture:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

Resume glass work after the current ray-hole cause is settled.

## Runtime-development rules

1. Every installable ZIP starts with `SL_`.
2. FX-only package = hot install; Firestorm may remain open.
3. Native add-on/build package = close Firestorm before install.
4. Debug screens/readouts are mandatory.
5. Loop: build -> commit source delta/checkpoint -> user runs real Firestorm -> report result -> update handoff -> next revision.
6. Semantic-bound alone is not proof of shader-visible payload.
7. New versions require visible version identifiers.
8. Never call a binary package remotely backed up until byte count/checksum is independently verified.
