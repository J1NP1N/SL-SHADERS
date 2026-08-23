# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-23

Fresh chats should start from branch `agent/ssr-background-depth` and treat **SSR v0.49 AvatarThicknessTrace** as the integration backbone.

## Backbone

Native Firestorm + ReShade semantics:

- `D0 = SL_DEPTH_PRIMARY_NATIVE` — nearest visible camera depth.
- `Dstatic = SL_DEPTH_BACKGROUND` — avatar-free/static world depth from the same camera.
- `Cstatic = SL_COLOR_BACKGROUND` — avatar-free/static world color from the same camera.
- `DavatarBack = SL_DEPTH_AVATAR_BACK` — avatar/rigged back-facing exit depth.

Exact v0.49 FX source is archived at `addons/SLSSR/current-fx/v0.49-source/`. Run `restore_v0.49.py`; expected SHA-256 is `354dd1deafedaabf25e7345632ce95c7b3f0627f5b1722ba6d8ce5e2037a6a7c`.

Exact validated native source/tooling is archived at `addons/SLSSR/native-backbone-v0.49/`. Run `restore_native_backbone.py`; expected archive SHA-256 is `2a7cf9fe266bb165b85c63ffe7b2520c563ef0ec223a0b93594ad59463ad4c52`.

The native archive restores the v0.3.5 Dstatic/Cstatic scene pair, bridge v0.3, v0.3.6b avatar-back patch, bridge v0.4, build scripts, and proof diagnostics.

## Original ghost — fixed structurally

GOOD = legitimate skin-colored/normal avatar reflection on the reflective receiver. Preserve it.

BAD = secondary white/pale avatar-shaped ghost/silhouette on reflective floors/walls. It appeared in the reflective receiver's reflection of another surface; it was not merely caused by avatar proximity to a wall.

Root cause: a front-depth-only avatar trace could accept a reflected ray after it had already passed behind the avatar's real volume.

v0.49 architecture:

- WORLD trace: `Dstatic + Cstatic` only.
- AVATAR trace: real native interval `[D0, DavatarBack]`.
- Avatar geometry is valid only while the reflected ray lies inside that interval.
- Samples behind `DavatarBack` are empty for the avatar branch.

Runtime result: the original secondary avatar ghost is essentially gone while the good avatar reflection remains.

Do not revive confidence-only culling, accepted-stretch thresholds, screen-flipped avatar reflection, D0/Dstatic substitution, or other pre-v0.49 silhouette heuristics.

## Current remaining visual issue

The current defect is different from the old ghost:

- ragged/stippled/aliased **static-world** SSR boundaries at grazing angles, corners, and long transitions;
- `Static-world accepted-hit mask` already contains the ragged boundary;
- `Avatar-only accepted-hit mask` looks clean;
- therefore leave the v0.49 avatar-thickness branch alone.

`Use Screen-Pixel DDA = 0` is the current user preference. Do not re-enable DDA unless explicitly requested.

A line previously observed in `Scene linear source (direct)` was verified to come from the active EEP/environment, not SSR.

## Required ReShade technique naming

All new experimental FX must make their role obvious in ReShade. Use these prefixes in `ui_label` / technique names:

- `CORE — ...` for the v0.49-derived main SSR trace/composite.
- `SPATIAL — ...` for roughness/AA resolve passes.
- `TEMPORAL PRE — ...` for capture/history input before CORE.
- `TEMPORAL POST — ...` for temporal resolve after CORE.
- `HIZ DEBUG — ...` for standalone Hi-Z diagnostics.
- `AVATAR RECEIVER — ...` for SSR applied ON avatar materials as receivers.

Do not use ambiguous labels such as `v0.49 Backbone` without the subsystem role. Each worker must document exact ReShade technique order and which effects should be disabled during isolated runtime tests.

## Parallel workstreams

### A. Roughness-aware spatial resolve / AA

Modify the resolve/filter only. Preserve v0.49 tracing/native thickness. Use depth/normal-aware bilateral filtering; roughness widens the footprint while mirror-like surfaces remain sharp. Do not globally blur the final frame.

### B. Temporal accumulation + reprojection

Preserve v0.49 hit logic. Add jitter/history, reprojection, disocclusion/depth/normal validation, camera-cut reset, neighborhood radiance clamping, and avatar-motion anti-trailing diagnostics.

### C. Hi-Z static-world trace

Improve/replace only the non-DDA static-world marcher using `Dstatic`, with `Cstatic` as world-hit color. Preserve the avatar `[D0,DavatarBack]` branch. Add hierarchical traversal and precise refinement. Correctness before performance.

### D. Avatar as SSR receiver

Restore SSR **on the avatar itself** as a receiver while preserving the v0.49 avatar-as-hit/source path. This means shiny avatar materials may reflect the static world; it does not mean changing the `[D0,DavatarBack]` volume used when the world reflects the avatar.

The receiver branch should start from avatar pixels, use available avatar material/specular/roughness and normals, and trace primarily against `Dstatic + Cstatic`. Keep it independently switchable/diagnostic so regressions in world receivers or avatar-hit thickness are obvious. Do not reintroduce the old secondary-avatar ghost.

Future work also includes cleaner native material/G-buffer inputs, optional static-world thickness/backface support, and performance optimization after visual correctness.

## Independent GTAO workstream

GTAO is independent of SSR. Do not modify CORE/Hi-Z/Spatial/Avatar SSR while working this stream.

Current coordinator branch: `agent/direct-gtao-integration`.

Validated runtime state:

- Firestorm straight-alpha boundary detection is working without nested ReShade technique execution.
- Direct GPU GTAO reaches the pre-alpha boundary and successfully applies once per frame.
- `SL_GTAO_D0`, `SL_GTAO_N0`, `SL_GTAO_RAW`, and `SL_GTAO_DENOISED` are bound for diagnostics.
- D0 is spatially coherent and is not the cause of the current failure.
- Raw and denoised AO are populated but currently overwhelmingly dark.
- Firestorm normal encoding/decoding matches the direct GTAO stereographic XY decode; do not replace the decode speculatively.

Current diagnostic build: v1.1e. It adds:

- `SL_GTAO_NV` — decoded-normal facing term `saturate(dot(N,V))`.
- `SL_GTAO_BASELINE` — unoccluded slice/basis visibility with horizon sampling removed.

Use those two views to isolate whether the collapse occurs in normal/view basis, slice integration, or horizon updates before any radius/strength/denoise tuning.

Exact status: `addons/SLGTAO/direct-prealpha-v1.1e-debug/PROJECT_STATUS.md`.

## Installable package handoff contract

`tools/installer/SL_InstallLatest.ps1` is the quick-install workflow. Follow `packages/README.md` exactly when producing handoff artifacts.

- Canonical installable packages go under `packages/latest/`.
- Every installable ZIP must begin with `SL_` because the installer discovers `SL_*.zip` in Downloads.
- Do not ask the user to rename packages to make the installer work; package naming is the coordinator's responsibility.
- Packages containing `build-msvc.bat` or an `.addon` require Firestorm closed; FX-only packages may be hot-installed.
- The current GTAO quick-install artifact is `packages/latest/SL_GTAO_Direct_v1_1e_Debug.zip`.

## Key runtime lineage

- v0.38: Dstatic hits resolving Cstatic changed dark contamination into a bright background-colored lobe; Cstatic color was not the root cause.
- v0.39: static-world-only trace removed contamination but also removed valid avatar reflection.
- v0.40-v0.44: fake screen flip, foreground substitution, stretch gates/composites, and raw-hit support were dead ends.
- v0.45: Dstatic/background accepted-hit path could be removed while artifact survived; culprit was another trace path.
- v0.46: tested short-travel primary-foreground hold branch was not the culprit.
- v0.47: dual trace isolated the entire bad tall band to the avatar-only D0 trace.
- v0.48: stretch threshold also removed valid avatar reflection; discarded.
- native v0.3.6b: `Valid backface mask` showed a clean cyan avatar silhouette aligned with avatar. PASS.
- v0.49: `[D0,DavatarBack]` avatar-volume trace structurally fixes the original ghost. Current backbone.

Full runtime record: `history/ssr/SSR_v0.35-v0.49_SESSION_RUNTIME.md`.

## Rules

1. Preserve GOOD avatar reflection.
2. Do not conflate the old avatar ghost with current static-world aliasing.
3. Keep DDA off by default.
4. Do not optimize FPS yet.
5. FX-only changes do not require a Firestorm rebuild.
6. Data ReShade cannot infer must be produced natively in Firestorm and published by the bridge.
7. Experimental renderer changes require useful debug views.
8. Change one subsystem at a time; v0.49 avatar thickness is immutable unless explicitly targeted.
9. Every experimental technique label must identify its subsystem role using the naming contract above.
10. Installable ZIP handoffs must follow `packages/README.md` and remain compatible with `tools/installer/SL_InstallLatest.ps1`.

## Fresh-chat bootstrap

Read:

1. `docs/HANDOFF.md`
2. `docs/BACKBONE_v0.49.md`
3. `packages/README.md` before producing any installable artifact
4. restore/read `addons/SLSSR/current-fx/v0.49-source/`
5. only if native plumbing is relevant, restore `addons/SLSSR/native-backbone-v0.49/`
6. `history/ssr/SSR_v0.35-v0.49_SESSION_RUNTIME.md` only when historical diagnosis is needed.

For GTAO work, also read `addons/SLGTAO/direct-prealpha-v1.1e-debug/PROJECT_STATUS.md` and continue from `agent/direct-gtao-integration`.

Do not ask the user to retell the v0.35-v0.49 debugging sequence unless these files are demonstrably insufficient.
