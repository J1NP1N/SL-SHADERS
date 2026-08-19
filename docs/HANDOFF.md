# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint. Update it whenever the active build, proven facts, current failure, or requested runtime test changes.

## Current focus

**Firestorm `specularRect` acquisition, ReShade-side publication, legacy/PBR classification, and explicit legacy RGB response are proven. The active test is legacy SSR on opaque surfaces that have no authored specular response.**

Current proven native bridge: **SLProbeLighting v1.6.10 / SSR v0.12 ReShadePublish**.

Current proven FX: **SSR v0.13 LegacyRGBResponse**.

Current test FX: **SSR v0.14 LegacyDielectricFallback — PENDING RUNTIME**.

Runtime status:

- v0.10 MainPassGate: **PASS** — authoritative full-resolution main-pass `specularRect` capture and private snapshot copy proven.
- v0.11 MainPassConsume: **FAIL, but informative** — the gated snapshot was selected, while the FX still sampled black from the borrowed native/private texture.
- v0.12 ReShadePublish: **PASS** — a ReShade-owned RGBA16F publication target made `G-buffer specular RGB` visibly non-black in the FX.
- material-class diagnostic on the current test scene: **legacy/cyan confirmed**.
- Bridge Status: **healthy/cyan confirmed**.
- v0.13 LegacyRGBResponse: **PASS** — legacy `specularRect.rgb` now produces visible SSR even when legacy `specularRect.a == 0`.
- v0.14 LegacyDielectricFallback: **PENDING** — gives legacy opaque pixels with neither explicit specular RGB nor classic-shiny/env signal a small neutral fallback response; PBR remains unchanged.

## What is proven at runtime

- Firestorm/ReShade registration and exact projection data work.
- Compatibility DEPTH works.
- `SL_SCENE_LINEAR` contains valid world scene color.
- SSR ray-hit geometry works.
- **Raw hit color sees ordinary scene geometry regardless of whether the receiving surface has an authored specular map.**
- The authoritative main-pass material G-buffer can be identified and read.
- The private main-pass specular snapshot is an accurate copy of that source.
- The material payload can be republished into a ReShade-owned target and sampled correctly by the FX.
- The current known test object is classified by the normal-buffer flag as legacy, not PBR.
- Valid legacy specular RGB reaches the applied SSR contribution even when legacy glossiness alpha is zero.

Conclusion: **missing reflections on diffuse-only legacy surfaces are now a receiver/material-weighting problem, not a ray-tracing visibility problem.**

## Root-cause chain

### v0.9 ReadProof

Added explicit read success, GL error, format, dimensions, and sampled channel statistics. This exposed the old analyzer reading a `512 x 512` probe-space deferred pass instead of the full-resolution main pass.

### v0.10 MainPassGate

Added a self-calibrating full-resolution gate. Runtime selected the `3840 x 2027` main pass and proved nonzero material bytes plus a matching private snapshot.

### v0.11 MainPassConsume

Made the proven gated snapshot authoritative for `SL_GBUFFER_SPECULAR`, but the FX still sampled black from the borrowed private/native GL texture. Semantic-bound alone was not shader-visible payload proof.

Source delta commit: `018a21b4bd441b53526f7dc4ee22fd7320fd76be`.

### v0.12 ReShadePublish — proven

Copies all four specular/material channels into a ReShade-owned RGBA16F target and publishes that owned view as `SL_GBUFFER_SPECULAR`.

Runtime showed the published full-resolution target, semantic bound, and visibly populated `G-buffer specular RGB`.

Source delta commit: `eede4fd47b8284b3b7bf973c2d082da4825f153f`.
Runtime result commit: `8655e4a9214fb1febe3477f3c8287ac1181e2f62`.

### v0.13 LegacyRGBResponse — proven

FX-only; v0.12 native add-on remains installed.

Changed only legacy material response:

- legacy `specularRect.rgb` directly tints reflected scene color;
- legacy `specularRect.a` remains diagnostic glossiness and no longer gates SSR energy;
- classic shiny/environment intensity remains a neutral fallback;
- PBR response is unchanged.

Runtime showed non-black `SSR contribution` and strong `Final reflection weight x10` on the legacy cube. Therefore `A=0` no longer kills valid legacy RGB response.

The apparent speckled structure on the ground in the weight diagnostic was later identified by the user as the expected PBR sand material response, not evidence by itself of ray instability.

Source delta commit: `886ead5ad289ff0ddf728ca669bc2b664a8b4843`.
Runtime result commit: `99bba41723fb2b89ac38c97d66467940d5477c1b`.

### v0.14 LegacyDielectricFallback — current test

FX-only; v0.12 native bridge remains installed.

Motivation: `Raw hit color` already sees the scene broadly. A legacy surface without a specular map can therefore have a valid SSR ray hit and still receive no visible reflection solely because material weighting reduces the result to zero.

Legacy receiver priority is now:

1. explicit Firestorm legacy `specularRect.rgb`;
2. classic shiny/environment intensity from the normal G-buffer;
3. small neutral dielectric fallback only if both signals are absent.

Detection uses the raw Firestorm payload before user scaling:

- authored signal = max(`specularRect.r/g/b`, classic-shiny/env intensity);
- `Legacy No-Spec Threshold` default = `0.005`;
- `Legacy No-Spec Fallback` default = `0.040`.

The existing view-angle Fresnel still multiplies this response, so the fallback is intended to remain subtle and strengthen at grazing angles. PBR ORM behavior is unchanged.

New diagnostic:

`Display Mode -> Legacy no-spec fallback mask`

- white = legacy pixel eligible for the synthetic fallback;
- black = explicit legacy specular/classic shiny, PBR, or background.

Source delta commit: `c2fe2cd1a8317d480cadc0fc4868c38129b3e2a2`.

## Next runtime step

Install **SL_SSR_v0_14_LegacyDielectricFallback.zip**. FX-only; Firestorm may remain open.

Verify the technique label:

`SL SSR v0.14 - Legacy Dielectric Fallback`

Do **not** press Analyze.

Return the same scene in these views:

1. `Legacy no-spec fallback mask`
2. `SSR contribution`
3. `Final reflection weight x10`
4. `Final composite`

Interpretation:

- diffuse-only legacy building/wall pixels should be white in the fallback mask;
- explicit legacy specular and PBR should remain black in that mask;
- fallback surfaces should show a subtle nonzero SSR contribution where the ray tracer has valid hits;
- if the final composite looks wet/plastic, lower or reshape the fallback rather than touching the proven explicit legacy/PBR paths;
- if the fallback mask is unexpectedly absent on known diffuse-only legacy geometry, investigate the raw classic-shiny/env signal threshold before changing reflection strength.

## Material interpretation retained from upstream audit

Pinned Firestorm commit: `f0d4a81c5ded331fb35d19e88544f0d22723bee5`.
Pinned Black Dragon commit: `b2ca434b39bcd93aff0e23414999dddd73527e05`.

At those revisions:

- legacy uses `specularRect.rgb` as specular color;
- PBR interprets `specularRect.rgb` as ORM and derives specular response from ORM plus base color;
- the normal-buffer PBR flag selects the interpretation.

## Source/recovery bookkeeping

Original recovered v0.10 source commit: `dd7022c80e0acf89295b11bda00ee788ae10d166`.

Recovery artifacts:

- `SL-SHADERS_ssr-v0.10-mainpassgate.patch` — SHA-256 `a855700f61e81fc1323037c370cdaffc29b8d3a78639a6e59b36fdc1c49cff57`
- `SL-SHADERS_ssr-v0.10-mainpassgate.bundle` — SHA-256 `c750b2a7d8306b9067528a095653b273ca1b6f11c9bd3c0875bb94ffad22c217`
- local v0.11 package SHA-256 `88562a49861abbb93ab3782b4e95ab6ac8b7dd9a22b401cb6bf9038900c77345`
- local v0.12 package SHA-256 `de71cbc0ada1faf2e6e4b6ee71619e04137cfeb28463dcb0ef3bd74768d2def0`
- local v0.13 package SHA-256 `7c293097aec6cf6dcd46eb3e49613f195d898a3321d4317a594f65b94917e5a4`
- local v0.14 package SHA-256 `166e6b089a52523a84970dfc21e2071c6105d3d78677b5012c4fd3aec591727c`

v0.11 through v0.14 source deltas are committed under `history/ssr/`. Local ZIPs are not remotely byte-verified unless separately uploaded and checksum-verified.

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