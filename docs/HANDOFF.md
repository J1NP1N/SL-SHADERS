# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint. Update it whenever the active build, proven facts, current failure, or requested runtime test changes.

## Current focus

**Firestorm `specularRect` acquisition is proven. The active problem is ReShade-side publication/consumption of those proven bytes.**

Current test build: **SLProbeLighting v1.6.10 / SSR v0.12 ReShadePublish**.

Runtime status:

- v0.10 MainPassGate: **PASS** — authoritative full-resolution main-pass `specularRect` capture and private snapshot copy proven.
- v0.11 MainPassConsume: **FAIL, but informative** — the gated main-pass snapshot was selected as the FX source, while `Display Mode -> G-buffer specular RGB` still sampled black.
- v0.12 ReShadePublish: **PENDING RUNTIME** — publishes the proven snapshot through a ReShade-owned RGBA16F target instead of borrowing the private/native GL texture directly.

Do **not** resume SSR strength/weight/roughness tuning until v0.12 proves that the FX can visibly sample the material payload.

## What is proven at runtime

- Firestorm/ReShade registration and projection data work.
- Compatibility DEPTH works.
- `SL_SCENE_LINEAR` contains valid world scene color.
- SSR ray-hit geometry works.
- Raw reflected hit color contains real scene color.
- The authoritative main-pass material G-buffer can be identified and read.
- The private main-pass specular snapshot is an accurate copy of that source.

The decisive v0.10 proof selected:

- `Source-proof sample: tex 8, 3840 x 2027` — full-resolution main deferred pass, not the 512x512 probe-space pass.
- `source read: OK`, `glError 0x0000`.
- `componentType 0x8C17 (UNSIGNED_NORMALIZED)`, `redBits 8`.
- nonzero RGB in the center block over the material test object.
- snapshot statistics matched source statistics.

The latest v0.11 runtime screenshot independently reconfirmed the same acquisition path: full-resolution `tex 8, 3840 x 2027`, clean read, nonzero source/snapshot RGB, and overlay source `GATED MAIN-PASS SNAPSHOT`.

Conclusion: **the black FX diagnostic is not an acquisition, readback, or private snapshot-copy failure.**

## Root-cause chain

### v0.9 ReadProof

Added explicit read success, GL error, attachment numeric format, dimensions, and sampled channel statistics. This exposed that earlier analysis was reading a `512 x 512` probe-space deferred pass instead of the full-resolution main pass.

### v0.10 MainPassGate

Added a self-calibrating full-resolution gate: candidate specular draws are accepted for source proof at >=75% of the tallest observed specular draw. Runtime selected the `3840 x 2027` main pass and proved nonzero material bytes plus a matching private snapshot.

This closed the old "black specular capture" investigation.

### v0.11 MainPassConsume

Changed `SL_GBUFFER_SPECULAR` source priority so the v0.10-proven gated private snapshot was authoritative and the older direct/current attachment became fallback only.

Runtime result:

- overlay: `SL_GBUFFER_SPECULAR FX source: GATED MAIN-PASS SNAPSHOT`
- source/snapshot analysis: valid and nonzero
- FX `G-buffer specular RGB`: **black**

Interpretation: a borrowed private/native GL texture could report semantic-bound while the FX still sampled black. Semantic-bound is therefore not sufficient proof of shader-visible payload.

Source delta commit: `018a21b4bd441b53526f7dc4ee22fd7320fd76be`.

### v0.12 ReShadePublish — current

The bridge now copies all four material channels into a **ReShade-owned RGBA16F render target** and binds that owned view as `SL_GBUFFER_SPECULAR`.

This deliberately mirrors the ownership model already used by the working `SL_SCENE_LINEAR` publication path.

Preserved material contract:

- legacy: `RGB = specular color`, `A = glossiness`
- PBR: `RGB = occlusion / roughness / metallic`

SSR weighting is unchanged. This build tests publication only.

Source delta commit: `eede4fd47b8284b3b7bf973c2d082da4825f153f`.

## Next runtime step

Run **v0.12 ReShadePublish** on the same material test scene.

Return:

1. overlay screenshot showing:
   - `SL_GBUFFER_SPECULAR input source: GATED MAIN-PASS SNAPSHOT`
   - `SL_GBUFFER_SPECULAR FX publication: RESHADE-OWNED COPY`
   - `SL_GBUFFER_SPECULAR semantic bound: YES`
2. `Display Mode -> G-buffer specular RGB`

Do **not** press Analyze unless new numeric source proof is specifically requested. Analyze is manual CPU instrumentation and is independent of FX publication.

Interpretation:

- **non-black G-buffer specular RGB:** publication is fixed; move to material-class interpretation and then SSR response/weighting.
- **black G-buffer specular RGB with RESHADE-OWNED COPY + semantic YES:** numerically inspect the ReShade-owned publication target itself before changing SSR weighting.

## Material interpretation retained from upstream audit

Pinned source audit is stored in `docs/UPSTREAM_RENDERER_NOTES.md`.

Firestorm commit: `f0d4a81c5ded331fb35d19e88544f0d22723bee5`.

Black Dragon commit: `b2ca434b39bcd93aff0e23414999dddd73527e05`.

At those revisions, native SSR samples `specularRect` directly and branches by the normal-buffer PBR flag:

- legacy uses `specularRect.rgb` as specular color;
- PBR interprets RGB as ORM and derives specular response from ORM plus base color.

Do not infer legacy/PBR classification from RGB shape alone. Use the actual G-buffer flag diagnostic after publication is proven.

## Source/recovery bookkeeping

Original recovered v0.10 source commit: `dd7022c80e0acf89295b11bda00ee788ae10d166`.

Recovery artifacts:

- `SL-SHADERS_ssr-v0.10-mainpassgate.patch` — 282,690 bytes — SHA-256 `a855700f61e81fc1323037c370cdaffc29b8d3a78639a6e59b36fdc1c49cff57`
- `SL-SHADERS_ssr-v0.10-mainpassgate.bundle` — 66,505 bytes — SHA-256 `c750b2a7d8306b9067528a095653b273ca1b6f11c9bd3c0875bb94ffad22c217`
- local v0.11 package SHA-256 `88562a49861abbb93ab3782b4e95ab6ac8b7dd9a22b401cb6bf9038900c77345`
- local v0.12 package SHA-256 `de71cbc0ada1faf2e6e4b6ee71619e04137cfeb28463dcb0ef3bd74768d2def0`

The v0.11 and v0.12 **source deltas are now committed to GitHub** under `history/ssr/`. Their ZIP packages should not be described as remotely byte-verified unless separately uploaded and checksum-verified.

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
