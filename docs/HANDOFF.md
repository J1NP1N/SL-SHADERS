# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint. Update it whenever the active build, proven facts, current failure, or requested runtime test changes.

## Current focus

**Opaque SSR plumbing and material response are proven. Glass-path work is temporarily parked while the active test fixes a final-composite artifact: Firestorm's cast shadow remains visibly underneath strong SSR because the current composite only adds reflection on top of the already-shadowed receiver.**

Installed/current native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.16 EnergyComposite — PENDING RUNTIME**.

Runtime status:

- v0.10 MainPassGate: **PASS** — full-resolution main-pass `specularRect` acquisition and private snapshot proven.
- v0.11 MainPassConsume: **FAIL, informative** — borrowed native/private GL texture could report semantic-bound while FX sampled black.
- v0.12 ReShadePublish: **PASS** — ReShade-owned RGBA16F publication fixed material-buffer sampling.
- material class / bridge diagnostics: **legacy-cyan classification and healthy bridge confirmed** on the known test scene.
- v0.13 LegacyRGBResponse: **PASS** — legacy `specularRect.rgb` reaches SSR even when legacy alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: **CONCEPT PASS** — diffuse-only legacy surfaces can receive SSR without authored specular maps; user reports it looks decent but somewhat weak. Strength tuning remains open.
- v0.15 PBRAlphaProbe: **PENDING / PARKED** — native diagnostic for PBR alpha-blended forward rendering; no glass SSR yet.
- v0.16 EnergyComposite: **PENDING** — replaces receiver/base energy proportionally under valid SSR instead of only adding reflection on top.

## Proven facts

- Compatibility DEPTH, Firestorm projection data, scene-linear color, SSR ray-hit geometry, and raw reflected hit color work.
- `Raw hit color` sees ordinary scene geometry regardless of whether the receiver has an authored specular map.
- Firestorm's opaque main-pass material buffer can be identified, copied, republished into a ReShade-owned texture, and sampled by the FX.
- Opaque material classification via the normal-buffer PBR flag works.
- Legacy explicit specular RGB drives SSR correctly; legacy alpha/glossiness is no longer an incorrect hard energy gate.
- Legacy surfaces with neither explicit specular RGB nor classic-shiny/env signal can receive a small neutral dielectric fallback.
- The speckled floor response seen earlier is expected PBR sand material structure, not by itself a ray-stability defect.

## v0.16 problem and design

The supplied glossy-floor screenshot shows the avatar reflection correctly, but Firestorm's dark cast shadow remains visible beneath/through it.

This is consistent with the current final composite:

`scene + reflected contribution`

The receiver's original diffuse/shadowed scene color is never reduced. Strong SSR therefore looks partially transparent over the cast shadow.

v0.16 keeps ray tracing and material response unchanged and changes only the final composition:

`compositeLinear = sceneLinear * (1 - baseRemoval) + reflectionLinear`

where:

- `reflectionLinear` is the same reflected term already proven in v0.13/v0.14;
- `appliedWeight` is the actual material-weighted reflection energy;
- `baseRemoval = saturate(appliedWeight * Reflection Base Replacement)`;
- PBR uses the existing scalar material weight;
- legacy base removal also accounts for the magnitude of the legacy RGB reflectance, so weak/tinted legacy specular does not erase too much receiver color.

New control:

`Reflection Base Replacement`

- `0.0` = old additive composite;
- `1.0` = full energy-style replacement, default for the first test.

New diagnostic:

`Display Mode -> Reflection base removal x10`

The tone-map path preserves the existing Firestorm-presentation handling. If captured tonemap state is unavailable, v0.16 applies the signed linear replacement delta through the existing scene-to-presentation scale fallback.

Source delta commit: `4658fb3d6baeeedd7e56cb76c5a3d031b4372c24`.

Local package:

- `SL_SSR_v0_16_EnergyComposite.zip`
- SHA-256 `55302308e8f0a929b315a99cea6d260c7639dd5e8614a30523ebce538f893b03`

FX-only package. Do not describe it as remotely byte-verified unless separately uploaded and checksum-verified.

## Next runtime test

Firestorm may remain open because v0.16 is FX-only. Keep the v0.15 native bridge installed if already present.

Confirm ReShade technique:

`SL SSR v0.16 - Energy Composite`

Use the same glossy floor / avatar view that showed the dark shadow ghost.

First run with:

`Reflection Base Replacement = 1.00`

Return:

1. `Display Mode -> Final composite`
2. `Display Mode -> Reflection base removal x10`

PASS criteria:

- avatar reflection remains visible;
- the dark cast-shadow ghost under the reflected avatar is substantially reduced;
- non-reflective areas are not globally washed out or replaced.

If receiver detail disappears too aggressively, test `0.75`, then `0.50`; do not change ray tracing or material response during this test.

## Glass work — parked checkpoint

Pinned Firestorm source shows transparency is forward-rendered after deferred rendering. PBR alpha rendering still has base color/alpha, normal, ORM, metallic factor, and roughness factor available.

Known test glass fixture:

- PBR, Alpha Mode `Blend`, base alpha `0.500`;
- metallic factor `1.000`, roughness factor `1.000`;
- magenta ORM approximately AO=1 / roughness=0 / metallic=1;
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`;
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`;
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`.

The UUIDs are validation fingerprints only, not the production detector. v0.15 detects PBR alpha blend from renderer state and publishes `SL_PBR_ALPHA_MASK`. Resume that work after v0.16 composite behavior is settled.

v0.15 source bookkeeping:

- native part 1 `19ef8ffbc5ad7b340eaed5512631411504c2a67b`
- native part 2a `3883a5df0e410249b2203312e92299c64f932caf`
- native part 2b `8649c5a291b7bda08d65d743fca799dc101c4e82`
- native CMake/version `fd7e1299d63526bc464261ea7c9703803804678f`
- FX delta `3ad7bc9bd706f2b4d1b4228ab24c49e2cbcfc6d7`
- fixture record `20a3fde2d19b89c53e8abbb8dad138f4a0d3d014`

## Earlier source checkpoints

- v0.11 source delta: `018a21b4bd441b53526f7dc4ee22fd7320fd76be`
- v0.12 source delta: `eede4fd47b8284b3b7bf973c2d082da4825f153f`
- v0.12 runtime PASS: `8655e4a9214fb1febe3477f3c8287ac1181e2f62`
- v0.13 source delta: `886ead5ad289ff0ddf728ca669bc2b664a8b4843`
- v0.13 runtime PASS: `99bba41723fb2b89ac38c97d66467940d5477c1b`
- v0.14 source delta: `c2fe2cd1a8317d480cadc0fc4868c38129b3e2a2`

Original recovered v0.10 source commit: `dd7022c80e0acf89295b11bda00ee788ae10d166`.

## Runtime-development rules

1. Every installable ZIP starts with `SL_` so `SL_InstallLatest.ps1` finds it.
2. FX-only package = hot install; Firestorm may remain open.
3. Native add-on/build package = Firestorm closed before install.
4. Debug screens/readouts are mandatory for renderer experiments.
5. Loop: build -> commit source delta/checkpoint -> user runs real Firestorm -> report result -> update handoff -> next revision.
6. A semantic being bound does not prove its shader-visible payload is correct.
7. New versions require unambiguous visible version identifiers.
8. Never call a binary package remotely backed up until byte count/checksum is independently verified.
9. When a runtime result changes the conclusion, update this handoff immediately.

## Fresh-chat bootstrap

Read in order:

1. `docs/HANDOFF.md`
2. `README.md`
3. `packages/RECOVERY_STATUS.md`
4. `docs/UPSTREAM_RENDERER_NOTES.md`
5. `history/ssr/` deltas for the active SSR chain

Do not ask the user to reconstruct the old conversation when these records contain the needed state.