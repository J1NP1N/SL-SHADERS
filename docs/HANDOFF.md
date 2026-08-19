# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed, but a camera-angle-dependent avatar-shaped **SSR disocclusion hole** remains. The active build is an FX-only test that skips a limited number of oversized foreground depth crossings instead of immediately terminating the reflected ray.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.17 DisocclusionSkip — PENDING RUNTIME**.

## Runtime status

- v0.10 MainPassGate: PASS — full-resolution main-pass `specularRect` acquisition proven.
- v0.11 MainPassConsume: FAIL/informative — borrowed private GL texture sampled black in FX.
- v0.12 ReShadePublish: PASS — ReShade-owned material publication fixed sampling.
- material class / bridge: legacy-cyan classification and healthy bridge confirmed.
- v0.13 LegacyRGBResponse: PASS — legacy `specularRect.rgb` drives SSR even when alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: CONCEPT PASS — diffuse-only legacy surfaces can receive conservative SSR without authored spec maps; strength remains tunable.
- v0.15 PBRAlphaProbe: INCONCLUSIVE / selector miss — supplied `PBR alpha-blend path probe mask` was fully black. Known glass fixture did not light up. Lower draw counters were not visible, so do not infer draws=0. Glass work is parked, not abandoned.
- v0.16 EnergyComposite: PARTIAL PASS — dark cast-shadow ghost was removed/reduced, proving receiver base replacement works. Remaining artifact is a camera-dependent missing-SSR region behind/around the avatar, consistent with screen-space disocclusion.
- v0.17 DisocclusionSkip: PENDING — keep v0.16 composite/material behavior and allow limited oversized-crossing skips with reduced confidence.

## Proven facts

- Compatibility DEPTH, exact Firestorm matrices, scene-linear color, SSR ray geometry, and raw hit color work.
- Raw hit sees ordinary scene geometry regardless of authored specular maps.
- Opaque Firestorm material G-buffer can be captured, copied to ReShade-owned storage, and sampled correctly.
- Legacy/PBR classification via normal-buffer flag works.
- Legacy explicit specular RGB response is correct enough to produce visible SSR.
- Diffuse-only legacy surfaces can receive a small dielectric fallback.
- v0.16 demonstrated that the old dark artifact was partly an additive-composite problem, but the remaining camera-dependent hole is not a shadow-color problem.

## v0.17 design

Current v0.16 ray marcher behavior:

- binary-refines a depth crossing;
- accepts the hit if final depth delta is within `SSRThickness`;
- otherwise treats a large crossing as disocclusion and returns false immediately.

This is a plausible cause of the avatar-dependent hole: a foreground occluder can terminate the reflected ray before the march reaches recoverable screen-space background.

v0.17 changes only that failure path:

- normal accepted hits remain unchanged;
- oversized crossings may be skipped up to `Disocclusion Skips` times (default 2);
- the ray resumes farther along its direction instead of immediately returning false;
- a later hit after one or more skips has its confidence multiplied by `Skipped-Hit Confidence` per skip (default 0.55);
- material weighting, PBR/legacy handling, v0.14 fallback, and v0.16 energy composite are unchanged.

New diagnostic:

`Display Mode -> Disocclusion-skip hit mask`

White means the final accepted hit required at least one oversized-crossing skip.

## v0.17 test

FX-only. Firestorm may remain open.

Verify technique:

`SL SSR v0.17 - Disocclusion Skip`

Defaults:

- `Reflection Base Replacement = 1.00`
- `Disocclusion Skips = 2`
- `Skipped-Hit Confidence = 0.55`

Use the same glossy floor/avatar angle that shows the missing SSR shape.

Return:

1. `Final composite`
2. `Disocclusion-skip hit mask`

Interpretation:

- hole reduced + white skip mask in the recovered region: keep and tune confidence conservatively;
- white skip mask but obvious reflections bleed through solid objects: reduce confidence/skips;
- hole remains and mask is black there: single-layer march continuation cannot recover the missing data; next step is temporal/spatial/probe fallback rather than more composite tuning.

Source delta commit: `17abe9b17ca54ff8d01e4d5c50c28f531664e578`.

Local package: `SL_SSR_v0_17_DisocclusionSkip.zip`
SHA-256: `34e757d3aa38ad0bff232e450340df52f8efc5f1267124783c813dbf9754231c`

## Glass checkpoint

Known glass fixture:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

v0.15 first-segment PBR-alpha probe mask was black in the supplied runtime image. Resume glass work after the disocclusion issue is settled; likely next glass revision should accumulate/select multiple PBR-alpha segments or expose the draw counters more directly.

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
