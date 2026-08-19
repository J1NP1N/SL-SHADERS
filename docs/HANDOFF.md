# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The remaining camera-dependent avatar-adjacent black region is already present in the geometry/ray-hit path, but its exact TraceSSR termination cause is **not yet identified**.

A follow-up v0.17 test disproved global hit thickness as the controlling cause: increasing `Hit Thickness` to `0.30` preserved good reflected color where SSR already worked but did not fill the black region.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.18 RayRejectReasons — PENDING RUNTIME**.

## Runtime status

- v0.10 MainPassGate: PASS — full-resolution main-pass `specularRect` acquisition proven.
- v0.11 MainPassConsume: FAIL/informative — borrowed private GL texture sampled black in FX.
- v0.12 ReShadePublish: PASS — ReShade-owned material publication fixed sampling.
- material class / bridge: legacy-cyan classification and healthy bridge confirmed.
- v0.13 LegacyRGBResponse: PASS — legacy `specularRect.rgb` drives SSR even when alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: CONCEPT PASS — diffuse-only legacy surfaces can receive conservative SSR without authored spec maps; strength remains tunable.
- v0.15 PBRAlphaProbe: INCONCLUSIVE / selector miss — supplied PBR alpha-blend path probe mask was fully black. Known glass fixture did not light up. Glass work is parked, not abandoned.
- v0.16 EnergyComposite: PARTIAL PASS — dark cast-shadow ghost was removed/reduced by receiver base replacement.
- v0.17 DisocclusionSkip: FAIL / informative — skip-ahead did not recover the black region. Follow-up clarification established that white in the ray diagnostic is the good/accepted reflection and the black in-between region is the defect. Raising `Hit Thickness` to `0.30` did not fill it.
- v0.18 RayRejectReasons: PENDING — diagnostic-only FX revision that keeps v0.17 behavior and color-codes the exact trace termination reason.

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

## v0.18 RayRejectReasons

Purpose: stop guessing and identify which TraceSSR exit creates the persistent black/missing region.

New display mode:

`Display Mode -> Ray termination reason`

Color key:

- WHITE = accepted reflection hit
- RED = reflected ray direction rejected because it points toward/through camera
- MAGENTA = projected ray left the valid screen/view
- BLUE = no depth crossing before trace-step / max-distance budget ended
- ORANGE = depth crossing remained oversized after the disocclusion-skip budget
- CYAN = geometric hit found but edge/distance confidence became zero
- YELLOW = unexpected / uncategorized

All normal SSR/material/composite behavior is unchanged from v0.17.

Source delta commit: `af126b4908715a242caf7c28e2a1bbc99b7dc2e4`.
Corrected v0.17 runtime record commit: `e44ad9a083d30463e2589b975258c01aec9d7950`.

Local package:

- `SL_SSR_v0_18_RayRejectReasons.zip`
- SHA-256 `924cc344ecb3949be587a69b4bb1d8f65154d09b52af4fbf0d245ade7ed9daea`

FX-only; Firestorm may remain open.

## Next runtime test

1. Hot-install v0.18.
2. Verify technique `SL SSR v0.18 - Ray Reject Reasons`.
3. Use the camera angle where the black/missing region is obvious.
4. Select `Display Mode -> Ray termination reason`.
5. Return one screenshot showing the color occupying the bad region.

Do not keep tuning thickness during this test; the `0.30` follow-up already showed the region survives a large global thickness increase.

## Glass checkpoint

Known glass fixture:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

v0.15 first-segment PBR-alpha probe mask was black in the supplied runtime image. Resume glass work after the current ray-hole cause is identified.

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
