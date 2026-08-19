# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The persistent camera-dependent avatar-adjacent black strip is still present in the geometry/ray-hit path.

The current leading hypothesis is now **ray-march sampling/tunneling**, not total trace range, hit thickness, material weighting, or final composite.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX baseline under investigation: **SSR v0.19 TraceBudget**.

## Runtime status

- v0.10 MainPassGate: PASS — full-resolution main-pass `specularRect` acquisition proven.
- v0.11 MainPassConsume: FAIL/informative — borrowed private GL texture sampled black in FX.
- v0.12 ReShadePublish: PASS — ReShade-owned material publication fixed sampling.
- material class / bridge: legacy-cyan classification and healthy bridge confirmed.
- v0.13 LegacyRGBResponse: PASS — legacy `specularRect.rgb` drives SSR even when alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: CONCEPT PASS — diffuse-only legacy surfaces can receive conservative SSR without authored spec maps; strength remains tunable.
- v0.15 PBRAlphaProbe: INCONCLUSIVE / selector miss — supplied PBR alpha-blend path probe mask was fully black. Known glass fixture did not light up. Glass work is parked, not abandoned.
- v0.16 EnergyComposite: PARTIAL PASS — dark cast-shadow ghost was removed/reduced by receiver base replacement.
- v0.17 DisocclusionSkip: FAIL / informative — skip-ahead did not recover the black region. White in the ray diagnostic is good/accepted reflection; black is the defect. Raising `Hit Thickness` to `0.30` did not fill it.
- v0.18 RayRejectReasons: PASS as diagnostic — target strip is BLUE, meaning no depth crossing was accepted before the march terminated.
- v0.19 TraceBudget: FAIL for target artifact, informative — target strip remains BLUE even with a much larger runtime search budget.

## Proven facts

- Compatibility DEPTH, exact Firestorm matrices, scene-linear color, SSR ray geometry, and raw hit color work.
- Raw hit sees ordinary scene geometry regardless of authored specular maps.
- Opaque Firestorm material G-buffer can be captured, copied to ReShade-owned storage, and sampled correctly.
- Legacy/PBR classification via normal-buffer flag works.
- Legacy explicit specular RGB response produces visible SSR.
- Diffuse-only legacy surfaces can receive a small dielectric fallback.
- v0.16 demonstrated that the old dark artifact was partly an additive-composite problem.
- The remaining black region appears before material weighting/composite because it is present in the ray-hit path.
- Global `Hit Thickness` is not the controlling fix.
- v0.18 classifies the bad strip as BLUE/no accepted crossing.
- v0.19 proves the old 32-step hard ceiling was a real bug, but **not the full cause of this strip**.

## v0.19 runtime result

Runtime screenshot showed:

- Trace Steps = 48
- Initial Ray Step = 0.12
- Ray Step Growth = 1.18
- Maximum Ray Distance = 128
- Hit Thickness = 0.18
- Disocclusion Skips = 4
- Skipped-Hit Confidence = 1.00

The bad strip still remained BLUE.

With 48 steps at 0.12 / 1.18, the march can reach beyond the visible 128-unit maximum-distance setting. Therefore the target strip is no longer explained by insufficient total ray range or the old hard 32-step ceiling.

Runtime result commit: `e64462d2d304cafe39e552eb06c5983c86da9c29`.

## Current hypothesis: sampling / tunneling

The marcher samples exponentially spaced distances and only detects a hit when sampled depth changes from negative to non-negative:

`previousDelta < 0 && delta >= 0`

A thin or steep reflected surface can therefore be crossed between two samples and never produce the required sign transition. In that case:

- `Hit Thickness` does nothing because binary refinement never starts;
- extending maximum distance does nothing because the ray already passed the missed geometry;
- adding more late samples does little if the local spacing near the target remains too coarse.

This matches the persistent BLUE result around thin avatar/limb reflection geometry.

## Next runtime step

Before another structural marcher rewrite, use v0.19 and test local sample density on the same bad camera angle.

Keep:

- Trace Steps = 48
- Initial Ray Step = 0.12
- Hit Thickness = 0.18
- Disocclusion Skips = 0 for a clean test
- Ray termination reason display

Test `Ray Step Growth` in this order:

1. `1.12`
2. `1.08`

Set Maximum Ray Distance only high enough for the avatar reflection target; do not use 128 unless needed. The purpose is local density, not range.

Interpretation:

- BLUE strip shrinks/turns WHITE as growth is reduced: sampling/tunneling confirmed. Next build should replace the current coarse exponential march with a denser/adaptive screen-space/depth-aware march while preserving practical cost.
- BLUE strip unchanged: next build should add a closest-approach diagnostic (minimum absolute depth delta along BLUE rays) before changing the marcher.

## Glass checkpoint

Known glass fixture:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

v0.15 first-segment PBR-alpha probe mask was black in the supplied runtime image. Resume glass work after the current ray-hole cause is settled.

## Important commits

- v0.12 source: `eede4fd47b8284b3b7bf973c2d082da4825f153f`
- v0.12 runtime PASS: `8655e4a9214fb1febe3477f3c8287ac1181e2f62`
- v0.13 source: `886ead5ad289ff0ddf728ca669bc2b664a8b4843`
- v0.13 runtime PASS: `99bba41723fb2b89ac38c97d66467940d5477c1b`
- v0.14 source: `c2fe2cd1a8317d480cadc0fc4868c38129b3e2a2`
- v0.15 runtime record: `ce1f122f1be908a12a4e1fc735171da0682dc805`
- v0.16 source: `4658fb3d6baeeedd7e56cb76c5a3d031b4372c24`
- v0.16 runtime record: `399e0075e49b4e628056f06bc7ae70c31f41e003`
- v0.17 source delta: `17abe9b17ca54ff8d01e4d5c50c28f531664e578`
- v0.17 corrected runtime record: `e44ad9a083d30463e2589b975258c01aec9d7950`
- v0.18 source delta: `af126b4908715a242caf7c28e2a1bbc99b7dc2e4`
- v0.18 runtime record: `179a926ac5d6b788d680ce146b899f762d494576`
- v0.19 source delta: `faeee069379d21e8bd824c0e3087b77be170898d`
- v0.19 runtime record: `e64462d2d304cafe39e552eb06c5983c86da9c29`

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
