# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The remaining camera-dependent missing avatar reflection is upstream in `TraceSSR`.

The target missing region follows the upside-down silhouette of the avatar reflection. v0.21 proved those failed rays sample both signs of the depth relation. v0.22 now proves the ray forms a real negative-to-positive crossing candidate, but the candidate remains beyond `Hit Thickness` after binary refinement and is treated as oversized.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.23 DeepRefine — PENDING RUNTIME**.

## Runtime status

- v0.10 MainPassGate: PASS — full-resolution main-pass `specularRect` acquisition proven.
- v0.11 MainPassConsume: FAIL/informative — borrowed private GL texture sampled black in FX.
- v0.12 ReShadePublish: PASS — ReShade-owned material publication fixed sampling.
- material class / bridge: legacy-cyan classification and healthy bridge confirmed.
- v0.13 LegacyRGBResponse: PASS — legacy `specularRect.rgb` drives SSR even when alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: CONCEPT PASS — diffuse-only legacy surfaces can receive conservative SSR without authored spec maps; strength remains tunable.
- v0.15 PBRAlphaProbe: INCONCLUSIVE / selector miss — known PBR alpha-blend glass fixture did not light up. Glass work remains parked.
- v0.16 EnergyComposite: PARTIAL PASS — dark cast-shadow ghost was removed/reduced by receiver base replacement.
- v0.17 DisocclusionSkip: separate ORANGE class established. `Disocclusion Skips = 3` is the known working setting for that separate problem and should remain enabled.
- v0.18 RayRejectReasons: target missing reflection classified BLUE/no accepted depth crossing.
- v0.19 TraceBudget: FAIL for target artifact, informative — target persists with Trace Steps 48 and Maximum Ray Distance 128, so total search range is not the cause.
- v0.20 BackgroundEntry: FAIL for target artifact, informative — dedicated recovered-entry mask stayed essentially empty over the target.
- v0.21 NoHitHistory: PASS as diagnostic — target is YELLOW/mixed-sign no-hit while `Disocclusion Skips = 3` remains enabled.
- v0.22 CrossingPath: PASS as diagnostic — target reflected-avatar region is ORANGE: a negative-to-positive crossing candidate reaches refinement but remains oversized and is skipped/rejected.
- v0.23 DeepRefine: PENDING — increases binary refinement depth from 5 to 9 iterations only.

## Proven facts

- Compatibility DEPTH, exact Firestorm matrices, scene-linear color, SSR ray geometry, and raw hit color work.
- Raw hit sees ordinary scene geometry regardless of authored specular maps.
- Opaque Firestorm material G-buffer can be captured, copied to ReShade-owned storage, and sampled correctly.
- Legacy/PBR classification via normal-buffer flag works.
- Legacy explicit specular RGB response produces visible SSR.
- Diffuse-only legacy surfaces can receive a small dielectric fallback.
- v0.16 energy composite fixed the dark receiver/shadow bleed component.
- The remaining target artifact is already present in ray-hit/termination diagnostics, before material weighting/composite.
- Global `Hit Thickness` is not the controlling fix; testing up to 0.30 did not fill the region.
- Total ray range is not the controlling fix.
- ORANGE/disocclusion and the target investigation must not be conflated; keep `Disocclusion Skips = 3` unless specifically testing that path.
- v0.21 proves target rays sample both `delta < 0` and `delta >= 0` geometry.
- v0.22 proves the target forms the correct `negative -> positive` crossing candidate, but refinement leaves `finalDelta > Hit Thickness` and the candidate is classified oversized.

## v0.22 result

Runtime screenshot used `Disocclusion Skips = 3` and `No-hit crossing candidate path`.

The avatar-reflection target is dominated by ORANGE. In v0.22 this means:

1. the ray reaches real geometry;
2. a `previousDelta < 0 && delta >= 0` candidate exists;
3. binary refinement runs;
4. the final refined sample still has `finalDelta > Hit Thickness`;
5. the candidate is treated as oversized and consumes the disocclusion skip budget instead of becoming a hit.

This moves the current bug from traversal/coverage into **refinement/acceptance precision**.

Runtime record commit: `0a84a797b3d2cfada7c80277842fdb8adcb2e643`.

## v0.23 DeepRefine

FX-only isolated test.

Change:

- `SL_SSR_BINARY_STEPS`: `5 -> 9`

Unchanged:

- `Disocclusion Skips = 3`
- trace range / growth
- `Hit Thickness` policy
- material response
- legacy no-spec fallback
- PBR response
- v0.16 energy composite
- crossing-path diagnostics

Purpose: determine whether the target ORANGE candidates are legitimate continuous crossings that were simply under-refined before the fixed thickness test.

Runtime test:

1. Hot-install `SL_SSR_v0_23_DeepRefine.zip`; Firestorm may remain open.
2. Verify technique `SL SSR v0.23 - Deep Refine`.
3. KEEP `Disocclusion Skips = 3`.
4. Keep `Hit Thickness = 0.18` for this comparison.
5. Use the same camera angle.
6. Return `No-hit crossing candidate path` and `Final composite`.

Interpretation:

- Former ORANGE target becomes WHITE and reflection fills: PASS; five binary steps were insufficient.
- Target remains ORANGE: binary search is converging on a screen-depth discontinuity, so fixed-depth-thickness acceptance is structurally wrong at the silhouette. Next fix should be edge/silhouette-aware acceptance rather than more steps or larger global thickness.

Source delta commit: `4205510bbfcdf3ea11b059c5b72ad971cc22af64`.

Local package:

- `SL_SSR_v0_23_DeepRefine.zip`
- SHA-256 `0e3e59d2f22a5d06c1df297f17b6cd9e99ba0989ccafde044d31ec0c3e48f659`

## Glass checkpoint

Known fixture:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

v0.15 first-segment PBR-alpha probe was black. Resume after the current ray-hole cause is settled.

## Important commits

- v0.12 source: `eede4fd47b8284b3b7bf973c2d082da4825f153f`
- v0.13 source: `886ead5ad289ff0ddf728ca669bc2b664a8b4843`
- v0.14 source: `c2fe2cd1a8317d480cadc0fc4868c38129b3e2a2`
- v0.16 source: `4658fb3d6baeeedd7e56cb76c5a3d031b4372c24`
- v0.17 source: `17abe9b17ca54ff8d01e4d5c50c28f531664e578`
- v0.18 source: `af126b4908715a242caf7c28e2a1bbc99b7dc2e4`
- v0.19 source: `faeee069379d21e8bd824c0e3087b77be170898d`
- v0.20 source: `26d6d431773b55e82528bc2b7f702820d223c980`
- v0.21 source: `45c89fa8efdd432c923b2b282eff1daa5b1d9a84`
- v0.21 runtime: `72e0a0564298a6813cc2eb399784abddf64fe76c`
- v0.22 source: `0efe13739c7e7d0445822bf0b91705a1b6cf5a39`
- v0.22 runtime: `0a84a797b3d2cfada7c80277842fdb8adcb2e643`
- v0.23 source: `4205510bbfcdf3ea11b059c5b72ad971cc22af64`

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
