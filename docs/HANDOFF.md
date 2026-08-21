# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-22

This is the live project checkpoint. Fresh chats should start from the branch HEAD of `agent/ssr-background-depth` and treat **SSR v0.49 AvatarThicknessTrace** as the current backbone unless the user explicitly asks to revisit an older experiment.

## Current backbone

Native Firestorm + ReShade SSR data path:

- `D0 = SL_DEPTH_PRIMARY_NATIVE` — ordinary nearest visible camera depth.
- `Dstatic = SL_DEPTH_BACKGROUND` — nearest non-rigged/static world depth from the same camera.
- `Cstatic = SL_COLOR_BACKGROUND` — avatar-free/static scene color from the same camera.
- `DavatarBack = SL_DEPTH_AVATAR_BACK` — back-facing/exit depth of rigged/avatar geometry.

The native scene pair (`Dstatic + Cstatic`) is proven aligned and avatar-free. The avatar back-depth diagnostic is also proven: `Valid backface mask` produced a clean cyan avatar silhouette aligned with the avatar.

Current SSR FX backbone: `SL_SSR_v0_49_AvatarThicknessTrace.fx` (archived in `addons/SLSSR/current-fx/v0.49-source/`; run the restore script there to reconstruct the exact `.fx`).

Current bridge source: `addons/SLSSR/avatar-thickness-v0.3.6b/SLBackgroundSceneLink_v0_4.cpp`.

## The original target bug is structurally fixed

The long-running defect was a **secondary white/pale avatar-shaped ghost** on reflective floors/walls. It appeared inside the reflective receiver's reflection of another surface. The good skin-colored avatar reflection under/on the receiver was always supposed to remain.

The root problem was camera-space avatar silhouette ambiguity. A single front depth (`D0`) let reflected rays accept geometry after they had already passed behind the avatar's real volume.

v0.49 fixes that structurally:

- WORLD trace: `Dstatic + Cstatic` only.
- AVATAR trace: uses the real native interval `[D0, DavatarBack]`.
- A reflected ray may count as avatar geometry only while it lies inside that front/back interval.
- Samples behind `DavatarBack` are empty for the avatar trace.

Runtime result: the original secondary avatar ghost is essentially gone while the legitimate avatar reflection remains.

Do **not** reintroduce the discarded stretch-threshold, confidence-gate, screen-flip, or foreground-substitution approaches.

## Current remaining visual issue

The current visible defect is different from the old ghost:

- ragged / stippled / aliased boundaries in the **static-world** SSR trace, especially at grazing angles, corners, and long reflective transitions;
- `Static-world accepted-hit mask` already contains this ragged boundary;
- `Avatar-only accepted-hit mask` looks clean;
- therefore the new avatar thickness path should be left alone.

The user does **not** want screen-pixel DDA. Keep `Use Screen-Pixel DDA = 0` unless the user explicitly asks to retest it.

A line previously seen in `Scene linear source (direct)` was verified to come from the active EEP/environment, not SSR. Do not chase that as an SSR regression.

## Parallel workstreams now allowed

### A. Roughness-aware spatial resolve / AA

Target only the SSR resolve/filter. Preserve v0.49 tracing and native thickness. Use depth/normal-aware bilateral weighting; widen blur with roughness while keeping true mirrors sharp. Do not Gaussian-blur the final frame indiscriminately.

### B. Temporal accumulation + reprojection

Preserve v0.49 hit logic. Add jitter/history, reprojection, disocclusion rejection, depth/normal validation, camera-cut handling, neighborhood clamping, and anti-trailing protection for avatar motion.

### C. Hi-Z static-world trace

Replace/improve the current non-DDA static-world marcher using `Dstatic`; preserve `Cstatic` color resolve and the avatar `[D0,DavatarBack]` branch. Add hierarchical traversal and precise refinement. Correctness before performance.

Future but not immediate:

- SSR **on the avatar as a receiver** (world reflected on shiny avatar materials);
- cleaner native material/G-buffer inputs;
- static-world thickness/backface extension where useful;
- performance optimization only after visual correctness.

## v0.35-v0.49 lineage summary

- v0.35 LegacyResolve — existing roughness/glossiness-aware resolve lineage.
- v0.36 BackgroundLayer — introduced paired-depth/background experimentation.
- v0.37 BackgroundVeto — continued background-layer gating.
- v0.38 BackgroundScenePair — Dstatic hits resolve `Cstatic`; converted dark contamination into a bright background-colored lobe, proving color alone was not the root cause.
- v0.39 StaticWorldTrace — clean static-only world trace; removed bad contamination but also removed valid avatar reflection.
- v0.40 DualLayerAA — fake screen-space mirrored avatar source; wrong vertical/translucent smear. Dead end.
- v0.41 ForegroundSubstitute — per-sample D0→Dstatic substitution. Wrong target. Dead end.
- v0.42 StretchComposite — direct use of stretch scalar as final opacity was not the right abstraction.
- v0.43 StretchSelection — stretch eligibility caused regressions and white lobes. Dead end.
- v0.44 RawHitSupport — raw accepted-hit support clamp did not remove white lobes.
- v0.45 BackgroundHitContinue — successfully removed accepted Dstatic/background-hit path while artifact survived, proving another accepted path caused it.
- v0.46 PrimaryHoldRelease — short-travel primary foreground release mask stayed essentially black; not the culprit.
- v0.47 DualTrace — independent world and avatar traces. Diagnostic isolated the bad tall band entirely to the avatar-only D0 trace.
- v0.48 AvatarStretchGate — rejected too much valid avatar reflection. Discarded.
- v0.49 AvatarThicknessTrace — uses native `[D0,DavatarBack]`; original secondary avatar ghost effectively solved. Current backbone.

## Native plumbing checkpoints

### v0.3.5 scene pair

Firestorm exports simultaneously:

- `SL_GetSSRPrimaryDepthInfo` → D0
- `SL_GetSSRBackgroundDepthInfo` → Dstatic
- `SL_GetSSRBackgroundColorInfo` → Cstatic

The background/static pass excludes rigged/avatar geometry. `SL_BackgroundScenePair_v0_1c.fx` visually proved recognizable Dstatic geometry and continuous avatar-free Cstatic.

### v0.3.6b avatar back depth

Adds:

- `SL_GetSSRAvatarBackDepthInfo` → DavatarBack

The bridge v0.4 copies/publishes it as `SL_DEPTH_AVATAR_BACK` in addition to the existing three resources.

`SL_AvatarThicknessProof_v0_1.fx` with `Valid backface mask` produced the expected cyan avatar silhouette. This is a proven native input and should not be replaced with an FX heuristic.

## Runtime-development rules

1. GOOD = skin-colored/normal avatar reflection on the reflective receiver. Preserve it.
2. BAD = secondary white/pale avatar-shaped ghost/silhouette. v0.49 structurally addresses it.
3. Do not call the good avatar reflection a bug.
4. Do not describe the old bug as merely "avatar near a wall"; it appeared in the reflective receiver's reflection of a wall/surface.
5. `Use Screen-Pixel DDA = 0` is the current user preference.
6. Do not optimize FPS until the SSR is visually correct.
7. FX-only changes should not trigger a Firestorm rebuild.
8. Native data unavailable to ReShade must be produced in Firestorm, then published through the bridge.
9. Debug views are required for experimental renderer changes.
10. Change one subsystem at a time and preserve the v0.49 avatar-thickness branch unless that branch is the explicit target.

## Fresh-chat bootstrap

Read in this order:

1. `docs/HANDOFF.md`
2. `docs/BACKBONE_v0.49.md`
3. restore/read v0.49 under `addons/SLSSR/current-fx/v0.49-source/`
4. Native files under `addons/SLSSR/background-scene-pair-v0.3.5/` and `addons/SLSSR/avatar-thickness-v0.3.6b/` only if changing plumbing.
5. `history/ssr/SSR_v0.35-v0.49_SESSION_RUNTIME.md` only if historical diagnosis is needed.

Do not ask the user to reconstruct the v0.35-v0.49 debugging sequence unless these files are demonstrably missing a needed observation.
