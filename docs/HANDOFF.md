# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint. Update it whenever the active build, proven facts, current failure, or requested runtime test changes.

## Current focus

**Firestorm `specularRect` acquisition, ReShade-side publication, legacy/PBR classification, and legacy RGB material response are now proven. The immediate next step is a normal-composite presentation check before choosing the next algorithm change.**

Current proven native bridge: **SLProbeLighting v1.6.10 / SSR v0.12 ReShadePublish**.

Current proven FX: **SSR v0.13 LegacyRGBResponse**.

Runtime status:

- v0.10 MainPassGate: **PASS** — authoritative full-resolution main-pass `specularRect` capture and private snapshot copy proven.
- v0.11 MainPassConsume: **FAIL, but informative** — the gated snapshot was selected, while the FX still sampled black from the borrowed native/private texture.
- v0.12 ReShadePublish: **PASS** — a ReShade-owned RGBA16F publication target made `G-buffer specular RGB` visibly non-black in the FX.
- material-class diagnostic on the current test scene: **legacy/cyan confirmed**.
- Bridge Status on the current test scene: **healthy/cyan confirmed**.
- v0.13 LegacyRGBResponse: **PASS for the targeted response correction** — legacy `specularRect.rgb` now produces nonzero reflected contribution and final weight without being annihilated by `specularRect.a == 0`.

## What is proven at runtime

- Firestorm/ReShade registration and exact projection data work.
- Compatibility DEPTH works.
- `SL_SCENE_LINEAR` contains valid world scene color.
- SSR ray-hit geometry works.
- Raw reflected hit color contains real scene color.
- The authoritative main-pass material G-buffer can be identified and read.
- The private main-pass specular snapshot is an accurate copy of that source.
- The material payload can be republished into a ReShade-owned target and sampled correctly by the FX.
- The current known test object is classified by the normal-buffer flag as **legacy**, not PBR.
- **Valid legacy specular RGB now reaches the applied SSR contribution even when legacy glossiness alpha is zero.**

The decisive v0.10 proof selected `tex 8, 3840 x 2027`, read clean RGBA8-style material data, and showed nonzero center RGB with a matching private snapshot. v0.12 then showed the same material payload visibly in `Display Mode -> G-buffer specular RGB` after ReShade-owned publication. v0.13 finally showed non-black `SSR contribution` and strong `Final reflection weight x10` on the legacy test cube.

Conclusion: **the old black material diagnostic was a two-part plumbing problem followed by a legacy weighting mismatch: wrong deferred-draw selection, native/private GL texture interoperability, then alpha/glossiness incorrectly gating legacy SSR. Those are all closed.**

## Root-cause chain

### v0.9 ReadProof

Added explicit read success, GL error, format, dimensions, and sampled channel statistics. This exposed the old analyzer reading a `512 x 512` probe-space deferred pass instead of the full-resolution main pass.

### v0.10 MainPassGate

Added a self-calibrating full-resolution gate. Runtime selected the `3840 x 2027` main pass and proved nonzero material bytes plus a matching private snapshot.

### v0.11 MainPassConsume

Made the proven gated snapshot authoritative for `SL_GBUFFER_SPECULAR`, but the FX still sampled black from the borrowed private/native GL texture. This proved semantic-bound alone was not shader-visible payload proof.

Source delta commit: `018a21b4bd441b53526f7dc4ee22fd7320fd76be`.

### v0.12 ReShadePublish — proven

Copies all four specular/material channels into a **ReShade-owned RGBA16F target** and publishes that owned view as `SL_GBUFFER_SPECULAR`.

Runtime showed:

- `SL_GBUFFER_SPECULAR input source: GATED MAIN-PASS SNAPSHOT`
- `SL_GBUFFER_SPECULAR FX publication: RESHADE-OWNED COPY`
- `SL_GBUFFER_SPECULAR semantic bound: YES`
- full-resolution published target
- `G-buffer specular RGB` visibly populated in the FX

Source delta commit: `eede4fd47b8284b3b7bf973c2d082da4825f153f`.
Runtime result commit: `8655e4a9214fb1febe3477f3c8287ac1181e2f62`.

### v0.13 LegacyRGBResponse — proven

FX-only; the v0.12 native add-on remains installed.

The pinned Firestorm native SSR post shader uses legacy `specularRect.rgb` directly to color the reflected scene contribution. It does not use legacy `specularRect.a` as a reflectivity gate.

v0.13 changed only the legacy material response:

- legacy `specularRect.rgb` directly tints the reflected scene color;
- legacy `specularRect.a` remains a glossiness diagnostic but no longer gates SSR energy;
- classic shiny/environment intensity remains a neutral fallback;
- PBR response is unchanged;
- ray marcher, depth, normals, scene-linear source, G-buffer publication, receiver protection, Fresnel, and tonemap/composite path are otherwise unchanged.

Runtime result:

- `SSR contribution` visibly non-black with colored reflected signal;
- `Final reflection weight x10` strongly nonzero on the legacy cube;
- therefore `A=0` no longer kills a valid legacy RGB response.

The weight diagnostic also shows visible speckling/noise across parts of the ground/scene. Treat that as a separate ray/weight stability issue, not a failure of v0.13.

Source delta commit: `886ead5ad289ff0ddf728ca669bc2b664a8b4843`.
Runtime result commit: `99bba41723fb2b89ac38c97d66467940d5477c1b`.

## Next runtime step

Stay on **v0.13 LegacyRGBResponse**. No new build yet.

Return one screenshot with:

`Display Mode -> Off`

Use the same scene/camera if practical. This is only to judge the real composite at normal scale.

Do **not** press Analyze.

Interpretation after that screenshot:

- if the normal composite is directionally correct but noisy/unstable, the next revision should isolate ray-confidence/temporal stability without changing the now-proven material path;
- if the contribution is essentially invisible despite the strong diagnostic weight, inspect presentation/tonemap scaling before temporal work;
- if it is visibly over-strong or reflective on inappropriate surfaces, inspect response shaping/material eligibility before temporal work.

## Material interpretation retained from upstream audit

Pinned Firestorm commit: `f0d4a81c5ded331fb35d19e88544f0d22723bee5`.
Pinned Black Dragon commit: `b2ca434b39bcd93aff0e23414999dddd73527e05`.

At those revisions:

- legacy uses `specularRect.rgb` as specular color;
- PBR interprets `specularRect.rgb` as ORM and derives specular response from ORM plus base color;
- the normal-buffer PBR flag selects the interpretation.

The current test object has been runtime-confirmed as legacy/cyan.

## Source/recovery bookkeeping

Original recovered v0.10 source commit: `dd7022c80e0acf89295b11bda00ee788ae10d166`.

Recovery artifacts:

- `SL-SHADERS_ssr-v0.10-mainpassgate.patch` — SHA-256 `a855700f61e81fc1323037c370cdaffc29b8d3a78639a6e59b36fdc1c49cff57`
- `SL-SHADERS_ssr-v0.10-mainpassgate.bundle` — SHA-256 `c750b2a7d8306b9067528a095653b273ca1b6f11c9bd3c0875bb94ffad22c217`
- local v0.11 package SHA-256 `88562a49861abbb93ab3782b4e95ab6ac8b7dd9a22b401cb6bf9038900c77345`
- local v0.12 package SHA-256 `de71cbc0ada1faf2e6e4b6ee71619e04137cfeb28463dcb0ef3bd74768d2def0`
- local v0.13 package SHA-256 `7c293097aec6cf6dcd46eb3e49613f195d898a3321d4317a594f65b94917e5a4`

v0.11, v0.12, and v0.13 source deltas are committed under `history/ssr/`. Local ZIPs are not to be described as remotely byte-verified unless separately uploaded and checksum-verified.

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