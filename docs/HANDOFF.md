# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. v0.16 fixed the dark additive-composite shadow bleed. The remaining camera-dependent missing reflection is upstream in `TraceSSR`.

The target no-hit region follows the upside-down silhouette of the avatar reflection. v0.20 directly tested the background-to-geometry-entry hypothesis and **failed**: the dedicated recovered-entry mask stayed essentially empty over the target while the target remained no-hit.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.21 NoHitHistory — PENDING RUNTIME**.

## Runtime status

- v0.10 MainPassGate: PASS — full-resolution main-pass `specularRect` acquisition proven.
- v0.11 MainPassConsume: FAIL/informative — borrowed private GL texture sampled black in FX.
- v0.12 ReShadePublish: PASS — ReShade-owned material publication fixed sampling.
- material class / bridge: legacy-cyan classification and healthy bridge confirmed.
- v0.13 LegacyRGBResponse: PASS — legacy `specularRect.rgb` drives SSR even when alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: CONCEPT PASS — diffuse-only legacy surfaces can receive conservative SSR without authored spec maps; strength remains tunable.
- v0.15 PBRAlphaProbe: INCONCLUSIVE / selector miss — known PBR alpha-blend glass fixture did not light up. Glass work remains parked.
- v0.16 EnergyComposite: PARTIAL PASS — dark cast-shadow ghost was removed/reduced by receiver base replacement.
- v0.17 DisocclusionSkip: FAIL for the BLUE target / informative — ORANGE cleanly identifies the separate oversized/disocclusion crossing class.
- v0.18 RayRejectReasons: PASS as diagnostic — target missing reflection is BLUE/no accepted depth crossing.
- v0.19 TraceBudget: FAIL for target artifact, informative — BLUE persists even with Trace Steps 48 and Maximum Ray Distance 128, so total search range is not the cause.
- v0.20 BackgroundEntry: FAIL for target artifact, informative — recovered-entry mask does not identify the target silhouette; direct background-to-first-positive-geometry entry is not the cause.
- v0.21 NoHitHistory: PENDING — diagnostic-only classification of what failed no-crossing rays actually sampled.

## Proven facts

- Compatibility DEPTH, exact Firestorm matrices, scene-linear color, SSR ray geometry, and raw hit color work.
- Raw hit sees ordinary scene geometry regardless of authored specular maps.
- Opaque Firestorm material G-buffer can be captured, copied to ReShade-owned storage, and sampled correctly.
- Legacy/PBR classification via normal-buffer flag works.
- Legacy explicit specular RGB response produces visible SSR.
- Diffuse-only legacy surfaces can receive a small dielectric fallback.
- v0.16 energy composite fixed the dark receiver/shadow bleed component.
- The remaining target artifact is already present in ray-hit/termination diagnostics, before material weighting/composite.
- Hit Thickness is not the controlling fix; testing up to 0.30 did not fill the region.
- Total ray range is not the controlling fix; v0.19 remained BLUE with an enlarged runtime budget.
- ORANGE disocclusion rejection and BLUE no-crossing are separate failure classes.
- v0.20 disproves the specific background-entry recovery hypothesis for the target region.

## v0.21 NoHitHistory

FX-only diagnostic revision. It preserves v0.20 tracing/material/composite behavior and adds two diagnostics.

### `Display Mode -> No-hit depth history`

For the no-crossing path:

- WHITE = accepted reflection hit
- BLUE = ray sampled background only; no non-background geometry was observed
- GREEN = geometry sampled, but every sampled depth delta stayed `< 0` (ray stayed in front of sampled scene depth)
- RED = geometry sampled, but every sampled depth delta stayed `>= 0` (ray stayed behind sampled scene depth)
- YELLOW = both negative and non-negative geometry samples occurred, but no hit was accepted
- PURPLE = no usable samples / unexpected no-hit state

Other rejection classes preserve the existing `Ray termination reason` colors.

### `Display Mode -> No-hit closest depth delta`

For failed no-crossing rays that sampled geometry:

- WHITE = at least one sample came very close to the scene depth
- BLACK = sampled geometry remained comparatively far from the ray

The display is normalized against the current `Hit Thickness` scale and is diagnostic only.

## Next runtime test

1. Hot-install `SL_SSR_v0_21_NoHitHistory.zip`; Firestorm may remain open.
2. Verify technique `SL SSR v0.21 - No-Hit History`.
3. Use the same camera angle with the upside-down avatar-shaped missing reflection.
4. Set `Disocclusion Skips = 0` for the cleanest classification.
5. Return `Display Mode -> No-hit depth history`.
6. If the target silhouette is GREEN, RED, or YELLOW, also return `No-hit closest depth delta`.

Interpretation:

- BLUE target = the ray never samples avatar/non-background depth at all; next work is screen-space coverage/projection/sampling traversal.
- GREEN target = ray samples geometry but always remains in front; next work is step progression/crossing geometry.
- RED target = ray samples geometry but is always already behind it; next work is start bias/sign handling.
- YELLOW target = both signs exist but bracket/refinement continuity is failing.

v0.20 runtime record: `7a8874bd68b1669913681506b69f106c6ed0e395`.
v0.21 source delta: `45c89fa8efdd432c923b2b282eff1daa5b1d9a84`.

Local v0.21 package:

- `SL_SSR_v0_21_NoHitHistory.zip`
- SHA-256 `60857cc1991658a3a252f0a050b44b9127eaf5bd1cb46eefa3b80f61c4550ff2`

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
- v0.12 runtime PASS: `8655e4a9214fb1febe3477f3c8287ac1181e2f62`
- v0.13 source: `886ead5ad289ff0ddf728ca669bc2b664a8b4843`
- v0.13 runtime PASS: `99bba41723fb2b89ac38c97d66467940d5477c1b`
- v0.14 source: `c2fe2cd1a8317d480cadc0fc4868c38129b3e2a2`
- v0.15 runtime record: `ce1f122f1be908a12a4e1fc735171da0682dc805`
- v0.16 source: `4658fb3d6baeeedd7e56cb76c5a3d031b4372c24`
- v0.16 runtime record: `399e0075e49b4e628056f06bc7ae70c31f41e003`
- v0.17 source: `17abe9b17ca54ff8d01e4d5c50c28f531664e578`
- v0.18 source: `af126b4908715a242caf7c28e2a1bbc99b7dc2e4`
- v0.18 runtime: `179a926ac5d6b788d680ce146b899f762d494576`
- v0.19 source: `faeee069379d21e8bd824c0e3087b77be170898d`
- v0.19 runtime: `e64462d2d304cafe39e552eb06c5983c86da9c29`
- v0.19 refined diagnosis: `1c3737dbbf9aeed0240c4729593cc2fb6ca999ff`
- v0.20 source: `26d6d431773b55e82528bc2b7f702820d223c980`
- v0.20 runtime: `7a8874bd68b1669913681506b69f106c6ed0e395`
- v0.21 source: `45c89fa8efdd432c923b2b282eff1daa5b1d9a84`

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
