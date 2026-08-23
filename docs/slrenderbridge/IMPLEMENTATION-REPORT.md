# SLRenderBridge Phase 1 Implementation Report

## Implemented

- Greenfield `src/SLRenderBridge/` source tree independent of `SLNativeBridge`.
- ReShade API 20 Windows/OpenGL add-on entrypoint and event registration.
- Resource/view observation for bound render targets and depth.
- Explicit deferred-like candidate tracking without authoritative promotion.
- Source-backed marker receiver ABI for future main/auxiliary classification.
- Main-view classifier with `MAIN_CANDIDATE`, `MAIN_CONFIRMED`, `AUXILIARY_CONFIRMED`, and `AMBIGUOUS` outcomes.
- Separate candidate-stage and semantic-stage tracking.
- Confirmed semantic resource generation and immediate stale-handle invalidation.
- ReShade present-epoch frame ID.
- Transient ReShade shader-resource views for confirmed main G-buffer semantics during effect rendering.
- Scalar uniform publication for stage/classification/confidence/frame/generation/validity.
- Optional matrix publication path that remains invalid unless the future native marker supplies all fields.
- Non-invasive ReShade overlay diagnostics and counters.
- Deterministic bridge-core unit/state-machine tests.
- Observation-only passthrough: bridge core records zero image writes; add-on code issues no draw, clear, copy, resolve, barrier, or render-target-changing command.

## Source-Backed Contracts

The implementation represents the following accepted Firestorm semantics without changing their qualification:

- normal main semantic truth is tied to the main render-target pack, not superficial GL shape (`FS-AUX-001` / renderer map);
- authoritative main G-buffer object is `mMainRT.deferredScreen` (`FS-GBUF-001`);
- attachments 0/1/2 are albedo-side, material (legacy spec/gloss or PBR ORM), and encoded normal+metadata (`FS-GBUF-001`);
- completed G-buffer boundary is the normal-main deferred bind/build/flush sequence (`FS-FRAME-001`, `FS-GBUF-001`);
- deferred depth identity is shared into `mMainRT.screen` and can evolve later (`FS-GBUF-001`, `FS-DEPTHSTATE-001`, `FS-ALPHA-001`);
- main scene color authority moves through `mMainRT.screen` and later post-processing (`FS-POST-001`);
- shader-visible model-view/projection/inverses and temporal deltas exist in Firestorm, but auxiliary work can share/mutate the same renderer infrastructure (`FS-CAMERA-001`, `FS-TEMPORAL-001`, `FS-AUX-001`).

The bridge does not claim that ReShade-only observation exposes these high-level Firestorm symbols.

## Remaining Heuristics

Two heuristics remain, both explicitly non-authoritative:

1. A deferred-like candidate requires at least three color resources plus depth with matching nonzero dimensions for the first three color attachments and depth.
2. Candidate completion is observed when binding moves away from that deferred-like set.

They exist only for diagnostics and to give a future native semantic marker a ReShade resource set to latch. Neither can publish `SL_MAIN_*` resources.

Known false positives include standard and hero/mirror probe G-buffers. Known false negatives include layout/configuration variants that do not satisfy the minimal structural rule.

## ReShade API Limitations

Reviewed current official ReShade source assumptions:

- source review commit: `aae2b7ecc18096ccddca2c073b50727541220292`;
- add-on API: `20`;
- `bind_render_targets_and_depth_stencil` provides OpenGL resource views corresponding to framebuffer binding activity;
- device API can resolve views to resources/descriptions and create shader-resource views;
- effect runtime can bind textures by semantic with `update_texture_bindings` and update uniform variables;
- `present` provides a supported presentation boundary.

The supported external API does not expose Firestorm `RenderTargetPack*`, `gCubeSnapshot`, `mRenderingMirror`, or equivalent semantic viewer state. It therefore cannot by itself distinguish the accepted normal-main/probe cases authoritatively.

## Firestorm-Side Opportunities

The smallest useful native interface is semantic markers, not a duplicate renderer or a raw-GL-name export layer.

Phase 1 already implements the receiving ABI. A future Firestorm change can resolve the core ambiguity by calling `SLRenderBridge_Notify` at source-backed boundaries:

- normal main begin;
- main `deferredScreen` bound;
- main G-buffer complete immediately after its flush;
- main deferred-lighting/post-deferred/scene-complete/post-process boundaries as needed;
- standard probe / hero probe / impostor auxiliary begin/end;
- renderer-resource invalidation;
- active main matrices after authoritative renderer state is established.

The marker should carry semantics and matrices while allowing ReShade to remain responsible for mapping actual OpenGL resources through its supported API.

No Firestorm patch is included in this commit.

## Validation Performed

### Performed

Linux-hosted deterministic core build/test, with the Windows/ReShade add-on target disabled:

```text
cmake -S src/SLRenderBridge -B build-core -DSLRB_BUILD_ADDON=OFF -DSLRB_BUILD_TESTS=ON
cmake --build build-core
ctest --test-dir build-core --output-on-failure
```

Result:

```text
1/1 SLRenderBridgeCoreTests: Passed
100% tests passed, 0 failed
```

The tests cover:

- external normal-looking candidate remains unconfirmed/unpublished;
- source-backed main marker sequence and semantic stages;
- standard probe cannot replace confirmed main resources;
- repeated hero-probe faces cannot replace confirmed main resources;
- resize/reset invalidation and resource-generation increments;
- resource-destruction stale-handle clearing;
- ambiguous external candidates prefer not published;
- observation-only passthrough image-write counter remains zero;
- complete matrix-marker ingestion.

### Not performed

- Windows/MSVC compilation of `SLRenderBridge.addon64` (this execution environment is Linux and could not clone the ReShade SDK over network DNS).
- Firestorm runtime load/unload.
- ReShade overlay runtime inspection.
- shader-resource-view publication against live Firestorm resources.
- pixel-equivalence/native Firestorm passthrough runtime proof.

According to repository policy these are therefore source-reviewed/locally unit-tested only, not runtime-proven.

### Next Firestorm runtime test after a Windows build

Run with ordinary effects disabled and no Firestorm marker patch:

```text
Bridge: SLRenderBridge 0.1.0
Expected image writes: 0
Expected authoritative main publications: 0
Expected classification: MAIN_CANDIDATE and/or AMBIGUOUS as deferred-like targets are observed
Expected SL_MAIN_GBUFFER_* bindings: null / SL_MAIN_GBUFFER_VALID=0
Resize test: resource generation increments and stale confirmed handles remain empty
Report: overlay values, load/runtime errors, and whether native Firestorm image changes with add-on loaded vs unloaded
```

A pure external run that does not publish main resources is a correct safe result, not a failure of the classifier.

## Recommended Next Step

Implement the smallest Firestorm-side semantic-marker patch that calls the already-defined bridge ABI at main/probe context boundaries and the normal-main deferred G-buffer bind/flush boundary, then runtime-validate that only `mMainRT.deferredScreen` becomes `SL_MAIN_GBUFFER_*`.
