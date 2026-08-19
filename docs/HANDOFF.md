# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The persistent camera-dependent avatar-adjacent black strip is still present in the geometry/ray-hit path.

Current leading hypothesis is now **background-to-geometry entry miss in TraceSSR**, more specific than generic sampling/tunneling. The missing BLUE region has the upside-down silhouette of the avatar reflection.

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
- Follow-up images cleanly separate ORANGE disocclusion rejection from BLUE no-crossing failure.
- The BLUE missing region follows the upside-down avatar-reflection silhouette.

## Current source-level diagnosis

The current marcher detects a hit only on:

`previousValid && previousDelta < 0.0 && delta >= 0.0`

But a background depth sample does:

`previousValid = false`

This creates a specific blind spot:

1. ray samples background;
2. next sample lands directly on the avatar and already has `delta >= 0`;
3. the crossing is not tested because `previousValid` is false;
4. the positive avatar sample becomes the new previous sample;
5. the ray may leave the thin avatar silhouette without ever producing the required negative-to-positive transition.

That exactly matches an upside-down avatar-shaped BLUE hole while surrounding reflection geometry still works.

This is more specific than generic exponential-step tunneling. Reducing step growth can mask the problem by increasing the chance of a negative geometry sample before the positive sample, but the structural problem is that **background -> first non-background positive sample cannot currently bracket a hit**.

## Next revision

Build **SSR v0.20 BackgroundEntry** as an FX-only isolated test.

Goals:

- preserve all v0.19 material/composite behavior;
- preserve ORANGE disocclusion handling as a separate path;
- add a conservative background-entry candidate when the previous march state was background and the first non-background sample is `delta >= 0`;
- bracket/refine that entry against the last background march interval rather than silently storing the positive sample;
- add a diagnostic mask/color for hits recovered specifically through this background-entry path.

Primary success criterion: the upside-down avatar-shaped BLUE region turns WHITE/valid hit without widespread through-object false positives.

Do not replace the entire marcher until this narrower hypothesis is tested.

Runtime result commit with this refined diagnosis: `1c3737dbbf9aeed0240c4729593cc2fb6ca999ff`.

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
- v0.19 refined diagnosis: `1c3737dbbf9aeed0240c4729593cc2fb6ca999ff`

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
