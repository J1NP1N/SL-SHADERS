# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint. Update it whenever the active build, proven facts, current failure, or requested runtime test changes.

## Current focus

**Firestorm `specularRect` acquisition, ReShade-side publication, and legacy/PBR classification are now proven. The active test is the first real legacy SSR material-response correction.**

Current proven native bridge: **SLProbeLighting v1.6.10 / SSR v0.12 ReShadePublish**.

Current FX test: **SSR v0.13 LegacyRGBResponse — PENDING RUNTIME**.

Runtime status:

- v0.10 MainPassGate: **PASS** — authoritative full-resolution main-pass `specularRect` capture and private snapshot copy proven.
- v0.11 MainPassConsume: **FAIL, but informative** — the gated snapshot was selected, while the FX still sampled black from the borrowed native/private texture.
- v0.12 ReShadePublish: **PASS** — a ReShade-owned RGBA16F publication target made `G-buffer specular RGB` visibly non-black in the FX.
- material-class diagnostic on the current test scene: **legacy/cyan confirmed**.
- Bridge Status on the current test scene: **healthy/cyan confirmed**.
- v0.13 LegacyRGBResponse: **PENDING** — removes legacy alpha/glossiness as a reflectivity gate and applies the actual legacy `specularRect.rgb` to the reflected scene color.

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

The decisive v0.10 proof selected `tex 8, 3840 x 2027`, read clean RGBA8-style material data, and showed nonzero center RGB with a matching private snapshot. v0.12 then showed the same material payload visibly in `Display Mode -> G-buffer specular RGB` after ReShade-owned publication.

Conclusion: **the old black material diagnostic was a two-part plumbing problem: wrong deferred-draw selection first, then native/private GL texture interoperability with the FX. Both are closed.**

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

### v0.13 LegacyRGBResponse — current test

This is FX-only; the v0.12 native add-on remains installed.

The pinned Firestorm native SSR post shader uses legacy `specularRect.rgb` directly to color the reflected scene contribution. It does not use legacy `specularRect.a` as a reflectivity gate.

v0.13 therefore changes only the legacy material response:

- legacy `specularRect.rgb` directly tints the reflected scene color;
- legacy `specularRect.a` remains visible as a glossiness diagnostic but no longer gates SSR energy;
- classic shiny/environment intensity remains a neutral fallback;
- PBR response is unchanged;
- ray marcher, depth, normals, scene-linear source, G-buffer publication, receiver protection, Fresnel, and tonemap/composite path are otherwise unchanged.

Source delta commit: `886ead5ad289ff0ddf728ca669bc2b664a8b4843`.

## Next runtime step

Install **SL_SSR_v0_13_LegacyRGBResponse.zip**. It is FX-only, so Firestorm may remain open. The v0.12 native bridge stays installed; therefore the native overlay will still say v1.6.10 / v0.12 ReShadePublish.

Verify the ReShade technique label says:

`SL SSR v0.13 - Legacy RGB Response`

Use the same legacy/cyan test scene. Do **not** press Analyze.

Return screenshots of:

1. `Display Mode -> SSR contribution`
2. `Display Mode -> Final reflection weight x10`
3. `Display Mode -> Off` / normal composite

Interpretation:

- nonzero contribution/weight on legacy pixels with valid specular RGB: the old alpha/glossiness gate was the downstream blocker; proceed to response shaping/roughness and temporal stability;
- valid G-buffer RGB but black contribution/weight: investigate ray confidence / receiver / composite weighting next, not publication.

## Material interpretation retained from upstream audit

Pinned Firestorm commit: `f0d4a81c5ded331fb35d19e88544f0d22723bee5`.
Pinned Black Dragon commit: `b2ca434b39bcd93aff0e23414999dddd73527e05`.

At those revisions:

- legacy uses `specularRect.rgb` as specular color;
- PBR interprets `specularRect.rgb` as ORM and derives specular response from ORM plus base color;
- the normal-buffer PBR flag selects the interpretation.

The current test object has now been runtime-confirmed as legacy/cyan.

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
