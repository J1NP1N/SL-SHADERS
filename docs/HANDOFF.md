# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The persistent camera-dependent avatar-adjacent black strip is now diagnosed as a **ray-search budget exhaustion** problem, not hit thickness/material/composite.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.19 TraceBudget — PENDING RUNTIME**.

## Runtime status

- v0.10 MainPassGate: PASS — full-resolution main-pass `specularRect` acquisition proven.
- v0.11 MainPassConsume: FAIL/informative — borrowed private GL texture sampled black in FX.
- v0.12 ReShadePublish: PASS — ReShade-owned material publication fixed sampling.
- material class / bridge: legacy-cyan classification and healthy bridge confirmed.
- v0.13 LegacyRGBResponse: PASS — legacy `specularRect.rgb` drives SSR even when alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: CONCEPT PASS — diffuse-only legacy surfaces can receive conservative SSR without authored spec maps; strength remains tunable.
- v0.15 PBRAlphaProbe: INCONCLUSIVE / selector miss — supplied PBR alpha-blend path probe mask was fully black. Known glass fixture did not light up. Glass work is parked, not abandoned.
- v0.16 EnergyComposite: PARTIAL PASS — dark cast-shadow ghost was removed/reduced by receiver base replacement.
- v0.17 DisocclusionSkip: FAIL / informative — skip-ahead did not recover the black region. Follow-up clarification established white in the ray diagnostic is the good/accepted reflection and black is the defect. Raising `Hit Thickness` to `0.30` did not fill it.
- v0.18 RayRejectReasons: PASS as diagnostic — the bad strip is BLUE, meaning the ray ended without an accepted depth crossing before its step/distance search budget ended.
- v0.19 TraceBudget: PENDING — increases the hard march ceiling so the configured 32-unit max ray distance can actually be searched with the current step schedule.

## Proven facts

- Compatibility DEPTH, exact Firestorm matrices, scene-linear color, SSR ray geometry, and raw hit color work.
- Raw hit sees ordinary scene geometry regardless of authored specular maps.
- Opaque Firestorm material G-buffer can be captured, copied to ReShade-owned storage, and sampled correctly.
- Legacy/PBR classification via normal-buffer flag works.
- Legacy explicit specular RGB response produces visible SSR.
- Diffuse-only legacy surfaces can receive a small dielectric fallback.
- v0.16 demonstrated that the old dark artifact was partly an additive-composite problem.
- The remaining black region appears before material weighting/composite because it is present in the ray-hit path.
- Global `Hit Thickness` is not the controlling fix for this region.
- v0.18 proves the defect terminates as BLUE: search-budget exhaustion.

## v0.18 diagnosis

The shader had:

- `SL_SSR_MAX_STEPS = 32`
- active `Initial Ray Step = 0.12`
- active `Ray Step Growth = 1.18`
- `Maximum Ray Distance = 32`

With exponential stepping, iteration 32 reaches only about **20.3 view-space units**. Roughly **35 iterations** are required to search the configured 32-unit ray distance.

Therefore the previous shader could legally return BLUE because the hard 32-iteration loop ended before the ray had searched the configured maximum distance.

Runtime record commit: `179a926ac5d6b788d680ce146b899f762d494576`.

## v0.19 TraceBudget

FX-only.

Changes:

- compile-time max trace iterations: `32 -> 48`
- default `Trace Steps`: `40`
- `Maximum Ray Distance` remains `32`
- initial step/growth remain `0.12 / 1.18`
- material response, v0.14 fallback, v0.16 energy composite, disocclusion logic, and v0.18 rejection diagnostics are unchanged.

At the default 32-unit max distance, the exponential step reaches the distance cap after roughly 35 iterations, so the extra hard ceiling does not imply 48 iterations every pixel. It simply removes the premature 32-step cutoff.

Source delta commit: `faeee069379d21e8bd824c0e3087b77be170898d`.

Local package:

- `SL_SSR_v0_19_TraceBudget.zip`
- SHA-256 `72e75b126d49df4ebc3181828382094b001b7c12b6afd0c2506a1994a38d753c`

## Next runtime test

Hot-install v0.19; Firestorm may remain open.

Because ReShade presets can retain the old uniform value, manually set:

- `Trace Steps = 40`
- `Initial Ray Step = 0.12`
- `Ray Step Growth = 1.18`
- `Maximum Ray Distance = 32`

Use the same camera angle where v0.18 showed the BLUE strip.

Return:

1. `Ray termination reason`
2. `Ray hit mask`
3. normal composite

Interpretation:

- previous BLUE strip becomes WHITE / valid hit: PASS; the hard trace-step ceiling was the missing-reflection cause.
- BLUE strip remains: further split BLUE into explicit `Trace Steps exhausted` versus `Maximum Ray Distance reached`, and inspect whether prior disocclusion skips consume the added search range.

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
