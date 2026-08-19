# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This file exists so a fresh ChatGPT conversation can resume the project without reconstructing the prior chat. **Update this file whenever the active build, proven facts, current failure, or requested runtime test changes.**

## Current focus

**SSR v0.8 SourceProof / SLProbeLighting v1.6.6**

Current install/test package:

`SL_SSR_v0_8_SourceProof.zip`

Current objective: prove the exact Firestorm `specularRect` material G-buffer payload and its lifetime/copy into ReShade. Do **not** tune SSR reflection strength, weighting, roughness response, or appearance until this is proven.

## What is already proven

- Firestorm/ReShade registration and projection data can be captured.
- `SL_SCENE_LINEAR` has produced valid scene color.
- SSR ray-hit geometry works.
- Raw reflected hit color has contained real scene color.
- Therefore a black material-aware reflection does **not** automatically mean depth/normals/ray tracing are broken.

### v0.5 -> v0.7 diagnostic progression

**v0.5**

`Bridge status` was encoded `R = SSR not ready, G = scene-linear valid, B = G-buffer specular valid`. A yellow runtime result therefore meant scene-linear was valid but the G-buffer specular semantic was not, and SSR was gated off before ray tracing.

**v0.6 SnapshotTimingFix**

Fixed two bridge faults:

1. `specular_snapshot_ready` could be cleared in `present` before ReShade consumed it in `begin_effects`.
2. Specular snapshot success incorrectly depended on `glGetError()`, so unrelated pre-existing Firestorm GL errors could make a successful copy look failed.

v0.6 also made `Ray hit mask` and `Raw hit color` independent of material validity.

Runtime after v0.6: bridge cyan, ray-hit mask alive, raw reflected scene color alive. This isolated the remaining problem to material G-buffer acquisition rather than the ray tracer.

**v0.7 DirectGBuffer**

Published the live Firestorm `specularRect` attachment directly as the preferred `SL_GBUFFER_SPECULAR` source, retaining snapshot fallback. Runtime showed semantic binding but material diagnostics remained suspicious: RGB/PBR diagnostics were black while at least some alpha/gloss structure appeared. Conclusion: binding alone did not prove the payload was the authoritative Firestorm G-buffer.

## Current v0.8 SourceProof test

v0.8 numerically compares the source attachment against the frozen snapshot and records source/capture metadata.

Important limitation: the analyzer is **not full-frame**. It samples nine 8x8 blocks on a 3x3 screen grid = **576 pixels total**. Put the known legacy-specular or PBR test object large in the viewport, preferably filling the center and a substantial part of the frame.

In Firestorm/ReShade, click:

`Analyze SL_GBUFFER_SPECULAR now`

Report these exact overlay lines:

```text
Source-proof sample...
source R...
source G...
source B...
source A...
snapshot R...
snapshot G...
snapshot B...
snapshot A...
Native Firestorm SSR post draws last frame...
Native SSR specular matches soften-light source...
```

### How to interpret the result

- **source RGB good + snapshot good + FX diagnostic black** -> ReShade live semantic/binding lifetime problem.
- **source RGB good + snapshot RGB bad** -> copy/snapshot path problem.
- **source RGB zero on a known material target** -> wrong source/draw identification, wrong timing, or an incorrect material-contract assumption.

## New upstream source finding worth retaining

At the currently inspected Firestorm commit `f0d4a81c5ded331fb35d19e88544f0d22723bee5`, Firestorm itself contains the same current `screenSpaceReflPostF.glsl` structure found in Black Dragon commit `b2ca434b39bcd93aff0e23414999dddd73527e05`.

That shader directly samples `specularRect`. For non-PBR pixels it uses `specularRect.rgb` as specular color. If the normal/G-buffer flag says PBR, it interprets `specularRect.rgb` as ORM, taking roughness from G and metallic from B, then derives specular F0 from base color/metallicity.

This reinforces the v0.8 strategy: **capture the authoritative attachment rather than reconstructing material response later.** See `UPSTREAM_RENDERER_NOTES.md` for pinned paths and exact contracts.

## Other recovered work — not the active task

These are preserved checkpoints, not necessarily what should be edited next:

- HybridGI: v0.14 BalancedAreaTemporal.
- HBAO: v0.5 SmoothAO.
- SSGI: v0.3 RayMarch.
- SLNativeBridge: v0.9a AlphaReplayMask.
- SLProbeBridge: v0.3b FBOAtlas.
- SLVolumetricBridge: v0.1d PrivateShadowCopies.
- SLSceneLayer/UI separation: v0.1.
- iMMERSE Firestorm Native integration: v0.6 RawAOAlphaReceiver.
- Firestorm standard DEPTH override: v0.2.1 historical SLProbeLighting infrastructure milestone.

The recovered prior `SL_Firestorm_Render_Extensions` Git history contains the HybridGI temporal/depth work through v0.14. Preserve it; do not flatten it into new history.

## Runtime-development rules

1. Every installable ZIP starts with `SL_` so `SL_InstallLatest.ps1` finds it.
2. FX-only package = hot install; Firestorm can remain open.
3. Native add-on/build package = Firestorm closed before install.
4. Debug screens/readouts are mandatory for experimental renderer work.
5. Our relationship is build -> user runs real Firestorm -> reports screenshots/readouts/errors -> next revision.
6. Never infer a renderer stage works merely because a semantic is bound.
7. New versions must have unambiguous visible version/technique identifiers; we previously lost time because an older ReShade technique was still running.
8. Whenever a test changes the conclusion, update this file in the same Git commit as the code/status change.

## Fresh-chat bootstrap

A new chat should read, in this order:

1. `docs/HANDOFF.md` — current state and next action.
2. `README.md` — project/install rules and subsystem index.
3. `docs/UPSTREAM_RENDERER_NOTES.md` — already-audited Firestorm/Black Dragon facts.
4. The README/source for the active package only.

Do not ask the user to retell the old conversation unless one of these files is demonstrably missing the needed runtime result.
