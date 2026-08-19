# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint. Update it whenever the active build, proven facts, current failure, or requested runtime test changes.

## Current focus

**Opaque legacy/PBR SSR plumbing is proven through material response. The active problem is locating Firestorm's forward-rendered PBR alpha-blend path so glass can be handled separately.**

Current test build: **SLProbeLighting v1.6.11 / SSR v0.15 PBRAlphaProbe — PENDING RUNTIME**.

Runtime status:

- v0.10 MainPassGate: **PASS** — full-resolution main-pass `specularRect` acquisition and private snapshot proven.
- v0.11 MainPassConsume: **FAIL, informative** — borrowed native/private GL texture could report semantic-bound while FX sampled black.
- v0.12 ReShadePublish: **PASS** — ReShade-owned RGBA16F publication fixed material-buffer sampling.
- material class / bridge diagnostics: **legacy-cyan classification and healthy bridge confirmed** on the known test scene.
- v0.13 LegacyRGBResponse: **PASS** — legacy `specularRect.rgb` reaches SSR even when legacy alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: **CONCEPT PASS** — diffuse-only legacy surfaces can receive a conservative no-spec fallback; user reports the result looks decent but somewhat weak. Strength tuning is not finalized.
- v0.15 PBRAlphaProbe: **PENDING** — diagnostic-only native/FX revision to spatially identify PBR alpha-blended forward rendering. It does not add glass SSR yet.

## Proven facts

- Compatibility DEPTH, Firestorm projection data, scene-linear color, SSR ray-hit geometry, and raw reflected hit color work.
- `Raw hit color` sees ordinary scene geometry regardless of whether the receiving surface has an authored specular map.
- Firestorm's authoritative opaque main-pass material buffer can be identified, copied, republished into a ReShade-owned texture, and sampled by the FX.
- Opaque material classification via the normal-buffer PBR flag works.
- Legacy explicit specular RGB now drives SSR correctly; legacy alpha/glossiness no longer acts as an incorrect hard energy gate.
- Legacy surfaces with neither explicit specular RGB nor classic-shiny/env signal can receive a small neutral dielectric fallback without requiring a specular map.
- The apparent speckled ground response seen in diagnostics was identified by the user as the expected PBR sand material, not by itself a ray-stability defect.

## Why glass is separate

Pinned Firestorm source shows transparency is forward-rendered after deferred rendering. PBR alpha rendering still has access to base color/alpha, normal, ORM, metallic factor, and roughness factor, but those pixels are not represented by the opaque `specularRect` contract in the same way.

Do not identify glass by material inventory name. The render-side `LLGLTFMaterial` does not provide an inventory-style name to the ReShade/OpenGL add-on, and the add-on does not currently receive SL asset UUIDs as texture labels.

Do not require low metallic to classify glass. The known test glass uses a magenta ORM texture and factor 1.0, giving approximately AO=1 / roughness=0 / metallic=1 while still visually functioning as transparent glass.

## Known glass fixture

See `history/ssr/SSR_v0.15_PBRAlphaProbe_FIXTURE.md`.

Editor state supplied by the user:

- PBR material
- Alpha mode `Blend`
- base alpha `0.500`
- metallic factor `1.000`
- roughness factor `1.000`
- magenta ORM texture, approximately AO=1 / roughness=0 / metallic=1

Texture asset UUID fingerprints:

- Base color: `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM: `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal: `4ed76883-9057-3be5-c18e-1b878bf9dd88`

These UUIDs are validation data only, not the production detector.

## v0.15 PBRAlphaProbe design

This revision preserves the proven v0.14 FX material response and changes the native bridge to detect Firestorm PBR-alpha draw state using:

- alpha blending enabled with `SRC_ALPHA / ONE_MINUS_SRC_ALPHA`;
- PBR sampler signature: `diffuseMap`, `bumpMap`, `specularMap`, `emissiveMap`;
- PBR factors: `metallicFactor`, `roughnessFactor`;
- valid current scene color attachment.

For the **first contiguous PBR-alpha segment** in the frame, the add-on snapshots the scene target immediately before and after that segment. It publishes the absolute scene-color difference as a ReShade-owned semantic:

`SL_PBR_ALPHA_MASK`

FX display mode:

`PBR alpha-blend path probe mask`

White means the captured PBR-alpha segment changed that screen pixel. Black means no detected change in that segment.

Important: this is a render-path probe, not yet a glass classifier. Other PBR alpha content may also appear white. If the glass is not in the first captured segment but another PBR-alpha object is, the next revision should accumulate/select segments rather than conclude the path is wrong.

Overlay diagnostics added:

- `PBR alpha draws last frame: ... program ...`
- `PBR alpha samplers: base ..., ORM ..., normal ...`
- `PBR alpha factors: metallic ..., roughness ...`
- `PBR alpha snapshots: ..., mask semantic bound: YES/no`

## v0.15 source bookkeeping

Validated source deltas are committed under `history/ssr/`:

- native part 1 commit: `19ef8ffbc5ad7b340eaed5512631411504c2a67b`
- native part 2a commit: `3883a5df0e410249b2203312e92299c64f932caf`
- native part 2b commit: `8649c5a291b7bda08d65d743fca799dc101c4e82`
- native CMake/version commit: `fd7e1299d63526bc464261ea7c9703803804678f`
- FX delta commit: `3ad7bc9bd706f2b4d1b4228ab24c49e2cbcfc6d7`
- fixture record commit: `20a3fde2d19b89c53e8abbb8dad138f4a0d3d014`

The native split patches were validated sequentially against the recovered v0.12 source and reconstruct the final v0.15 `SLProbeLighting.cpp` byte-for-byte.

Local package:

- `SL_SSR_v0_15_PBRAlphaProbe.zip`
- SHA-256 `d050833e72b2c6f1119619e41434e4311368f6a8cdae18d802acae5d188559bc`

Do not describe the ZIP as remotely byte-verified unless separately uploaded and checksum-verified.

## Next runtime test

v0.15 contains a native add-on change, so **close Firestorm before installing**.

Confirm visible versions:

- native overlay: `SL Probe Lighting v1.6.11 ... (v0.15 PBRAlphaProbe)`
- ReShade technique: `SL SSR v0.15 - PBR Alpha Probe`

Use the known glass fixture in view. Do not press Analyze.

Return:

1. native overlay showing the four PBR-alpha diagnostics above;
2. `Display Mode -> PBR alpha-blend path probe mask`.

Interpretation:

- `PBR alpha draws > 0`, snapshots increasing, semantic `YES`, and glass pane white: **forward PBR-alpha path found**. Next revision can capture the glass receiver's actual alpha/normal/material state and begin SSR integration.
- draws > 0 and semantic `YES`, but mask only shows another transparent PBR object: first-segment selection is too narrow; accumulate/select multiple PBR-alpha segments next.
- draws > 0 but mask black: inspect before/after capture timing or delta threshold before touching SSR.
- draws = 0: relax/inspect the PBR-alpha program signature or blend-state assumptions; do not change the proven opaque SSR path.

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