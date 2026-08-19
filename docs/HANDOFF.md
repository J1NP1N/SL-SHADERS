# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The remaining camera-dependent missing avatar reflection is upstream in `TraceSSR` and follows the upside-down silhouette of the avatar reflection.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.25 SilhouetteGate — PENDING RUNTIME**.

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
- v0.24 SilhouetteEdge: FAIL/informative — recovery path fires on only sparse isolated pixels; target avatar-shaped region is not substantially recovered.
- v0.25 SilhouetteGate: PENDING — diagnostic-only split of the exact silhouette-edge gate that rejects terminal oversized candidates.

## Proven facts for the current artifact

- The problem is upstream of material weighting/composite; it exists in ray-hit diagnostics.
- `Hit Thickness` is not the controlling fix; testing up to 0.30 did not fill the region.
- Total ray range is not the fix.
- The ray samples real geometry on both sides of the depth relation.
- The ray forms the correct `previousDelta < 0 && delta >= 0` crossing candidate.
- More binary refinement does not make the refined positive sample fall within global `Hit Thickness`.
- v0.24's terminal silhouette recovery is too selective for the target at its current gates.
- ORANGE/disocclusion and the current silhouette target must not be conflated. Keep `Disocclusion Skips = 3` unless specifically testing disocclusion.

## v0.24 runtime result

`Silhouette-edge recovered hit mask` was almost entirely black in the target region, with only a few isolated white recovered pixels.

Settings retained:

- `Silhouette Edge Recovery = 1`
- `Silhouette Edge Confidence = 0.60`
- `Silhouette Min Depth Jump = 0.25`
- `Silhouette Max Pixel Span = 2.0`
- `Disocclusion Skips = 3`
- `Hit Thickness = 0.18`

Do not loosen those thresholds blindly. The next diagnostic identifies which gate is failing.

Runtime record commit: `ccc2f4e0b2f8bb7aa46f5f19b1f2baa2acf57d65`.

## v0.25 SilhouetteGate

FX-only diagnostic revision. v0.24 behavior is preserved.

New display mode:

`Display Mode -> Silhouette-edge gate reason`

Color key for terminal oversized candidates:

- WHITE = recovered silhouette-edge hit
- RED = refined positive side invalid / no longer oversized
- CYAN = refined negative-side bracket invalid or not negative geometry
- YELLOW = foreground depth jump below `Silhouette Min Depth Jump`
- MAGENTA = refined bracket wider than `Silhouette Max Pixel Span`
- ORANGE = both depth-jump and pixel-span gates fail
- GREEN = all geometric gates pass but recovery is disabled or confidence dies
- Other colors preserve existing rejection diagnostics

Runtime test:

1. Hot-install `SL_SSR_v0_25_SilhouetteGate.zip`; Firestorm may remain open.
2. Verify technique `SL SSR v0.25 - Silhouette Gate`.
3. KEEP `Disocclusion Skips = 3` and `Hit Thickness = 0.18`.
4. Keep silhouette thresholds at their v0.24 defaults.
5. Use the same camera angle.
6. Return one screenshot of `Silhouette-edge gate reason`.

Do not tune thresholds before this diagnostic is read.

Source delta commit: `85c526b2b70a67cb102014a9577694ebb1e1d349`.

Local package:

- `SL_SSR_v0_25_SilhouetteGate.zip`
- SHA-256 `675eaf0a5865003cba03dea96d0de6f391aeff222cfe77a618a533d9426142a9`

## Glass checkpoint

Known fixture:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

v0.15 first-segment PBR-alpha probe was black. Resume after the current ray-hole cause is settled.

## Important recent commits

- v0.21 runtime: `72e0a0564298a6813cc2eb399784abddf64fe76c`
- v0.22 source: `0efe13739c7e7d0445822bf0b91705a1b6cf5a39`
- v0.22 runtime: `0a84a797b3d2cfada7c80277842fdb8adcb2e643`
- v0.23 source: `4205510bbfcdf3ea11b059c5b72ad971cc22af64`
- v0.23 runtime: `25c4f45ba5d3ccd222287aff7dc919a9bdf3ffd7`
- v0.24 source: `cac5b0c0bb5e14b53ddfe3671313288ad9df0752`
- v0.24 runtime: `ccc2f4e0b2f8bb7aa46f5f19b1f2baa2acf57d65`
- v0.25 source: `85c526b2b70a67cb102014a9577694ebb1e1d349`

Original recovered v0.10 source commit: `dd7022c80e0acf89295b11bda00ee788ae10d166`.

## Runtime-development rules

1. Every installable ZIP starts with `SL_`.
2. FX-only package = hot install; Firestorm may remain open.
3. Native add-on/build package = close Firestorm before install.
4. Debug screens/readouts are mandatory.
5. Loop: build -> commit source delta/checkpoint -> user runs real Firestorm -> report result -> update handoff -> next revision.
6. Semantic-bound alone is not proof of shader-visible payload.
7. New versions require visible version identifiers.
8. Never call a binary package remotely backed up until byte count/checksum is independently verified.
