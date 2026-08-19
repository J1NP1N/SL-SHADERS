# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The remaining camera-dependent missing avatar reflection is upstream in `TraceSSR` and follows the upside-down silhouette of the avatar reflection.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current runtime result: **SSR v0.25 SilhouetteGate — COMPLETE / informative fail**.

Next runtime comparison: **SSR v0.26 OriginBiasAudit**. Prepared fallback/prototype: **v0.28 ScreenDDAPrototype**. v0.27 FullResBaseline is optional if resolution needs isolation.

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
- v0.23 DeepRefine: FAIL/informative — 5 -> 9 binary steps does not remove target; still ORANGE.
- v0.24 SilhouetteEdge: FAIL/informative — terminal recovery fires on only sparse isolated pixels.
- v0.25 SilhouetteGate: PASS diagnostic / architecture fail — target is mostly ordinary BLUE in the gate-reason view, meaning most target rays never reach the terminal silhouette gate after normal disocclusion skips.

## Proven facts for the current artifact

- The problem is upstream of material weighting/composite; it exists in ray-hit diagnostics.
- `Hit Thickness` is not the controlling fix; testing up to 0.30 did not fill the region.
- Total ray range is not the fix.
- The ray samples real geometry on both sides of the depth relation.
- The ray forms the correct `previousDelta < 0 && delta >= 0` crossing candidate.
- More binary refinement does not make the refined positive sample fall within global `Hit Thickness`.
- v0.24 terminal silhouette recovery is structurally too late for most target rays.
- ORANGE/disocclusion and the current silhouette target must not be conflated. Keep `Disocclusion Skips = 3` unless specifically testing disocclusion.

## v0.25 result — important architectural correction

Runtime settings:

- `Disocclusion Skips = 3`
- `Hit Thickness = 0.18`
- v0.24 silhouette thresholds unchanged
- display `Silhouette-edge gate reason`

Observed:

The target upside-down avatar-reflection hole is dominated by ordinary BLUE/no-crossing, not by v0.25 terminal gate-failure colors.

Interpretation:

1. v0.22 already proved target rays do form oversized crossing candidates.
2. Those candidates can consume one or more of the three normal disocclusion skips.
3. Many rays then terminate later as ordinary no-crossing before the skip budget is exhausted.
4. Therefore the terminal-only v0.24 silhouette recovery never runs for most target pixels.
5. This explains v0.24's sparse isolated recovery pixels.

Conclusion: silhouette-vs-disocclusion classification must occur **at each oversized candidate**, not only after all skips are spent.

Runtime record commit: `09d6e6c58561433212c8ba0a7b36d1b88913dbce`.

## Trace-core audit

A broader source audit is committed in `docs/SSR_TRACE_CORE_AUDIT_2026-08-19.md`.

Key findings:

### 1. Ray-origin bias was incorrectly coupled to Hit Thickness

Old code used:

```hlsl
originPos + originNormal * max(SSRThickness * 0.75, 0.01)
```

At `Hit Thickness = 0.18`, that offsets the ray origin by `0.135` view-space units. Thickness tests therefore changed both hit tolerance and ray geometry.

### 2. Strict sign-crossing binary refinement assumes local depth continuity

At visible silhouettes the single-layer depth buffer is discontinuous. Binary search may converge spatially to the silhouette while `finalDelta` remains large indefinitely. v0.23 strongly supports this.

### 3. Half-resolution receiver tracing is not a neutral diagnostic baseline

Current SSR launches one receiver ray per half-resolution pixel and upsamples. Full-resolution comparison is prepared as v0.27 if required.

### 4. Current custom marcher differs materially from Firestorm native SSR

Firestorm native SSR uses adaptive depth-error stepping and an absolute depth-distance acceptance path, not only our strict negative-to-positive/fixed-thickness rule.

### 5. Screen-space DDA is the preferred architectural prototype

A contiguous pixel traversal with perspective-correct ray depth intervals is prepared in v0.28 to test whether the current artifact is fundamentally tied to the old trace core.

Audit commit: `69997fb69917c4b2808f97a6a5a7051bcd1626ac`.

## Next tests

### v0.26 OriginBiasAudit

FX-only. Decouples `Ray Origin Bias` from `Hit Thickness`.

- corrected default `Ray Origin Bias = 0.010`
- `0.135` reproduces the old effective bias at `Hit Thickness = 0.18`
- keep `Disocclusion Skips = 3`
- keep `Hit Thickness = 0.18`

Compare the same bad camera angle at bias `0.010` and `0.135` using final composite and/or ray termination/hit diagnostics.

Source delta commit: `1de46b30f98143e1a4cf6d46765a61e7289f78ca`.

### v0.27 FullResBaseline

Prepared diagnostic only. Same trace family, but one receiver ray per full-resolution pixel. Use only if v0.26/v0.28 leave a resolution ambiguity.

Source delta commit: `d0945f9a894ff04259e6a1240f60698a7ff4ce0c`.

### v0.28 ScreenDDAPrototype

Prepared experimental trace-core replacement. Uses contiguous screen-pixel traversal / perspective-correct depth-slab testing rather than extending the old binary-discontinuity workaround. Compare DDA ON/OFF without changing material response/composite.

Source delta commit: `b59bc237430a81c885ac719830785b2231d25336`.

Prepared-test checkpoint commit: `9a2c86f92b41618e95405703efece993893f0de0`.

## Glass checkpoint

Known fixture:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

v0.15 first-segment PBR-alpha probe was black. Resume after the current ray-hole cause is settled.

## Runtime-development rules

1. Every installable ZIP starts with `SL_`.
2. FX-only package = hot install; Firestorm may remain open.
3. Native add-on/build package = close Firestorm before install.
4. Debug screens/readouts are mandatory.
5. Loop: build -> commit source delta/checkpoint -> user runs real Firestorm -> report result -> update handoff -> next revision.
6. Semantic-bound alone is not proof of shader-visible payload.
7. New versions require visible version identifiers.
8. Never call a binary package remotely backed up until byte count/checksum is independently verified.
