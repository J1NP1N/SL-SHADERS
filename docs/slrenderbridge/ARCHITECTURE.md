# SLRenderBridge Architecture

## Scope

`SLRenderBridge` is a greenfield Firestorm-aware ReShade bridge. It does not derive its architecture from `SLNativeBridge` and does not modify the existing bridge/recovery lineage.

Phase 1 is observation-only. It contains no GTAO, SSR, HybridGI, composite pass, debug tint, or identity-copy effect. The bridge's render-write counter is structurally fixed at zero.

The renderer semantics in this design are based on the accepted Firestorm audit set pinned to:

- Firestorm branch: `master`
- Firestorm commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`
- platform/API: Windows / OpenGL

ReShade API review for this implementation used the official ReShade source at commit `aae2b7ecc18096ccddca2c073b50727541220292`, add-on API `20`.

## Architectural rule

The bridge separates two questions that older GL-discovery approaches tend to collapse:

1. What Firestorm semantic context is active?
2. Which ReShade-observed OpenGL resources correspond to that context?

The external add-on API can answer the second question only after Firestorm has supplied enough evidence to answer the first one. A structurally plausible deferred framebuffer is therefore only a candidate.

```text
Firestorm source-backed semantic context
        |  (future optional marker ABI)
        v
MainViewClassifier --------------------+
                                       |
ReShade OpenGL events                  |
        |                              |
        v                              v
RuntimeObserver -> ResourceTracker -> BridgeCore -> BridgeContract publication
                       |                  |
                       v                  v
                 generation          StageTracker
                                           |
                                           v
                                      Diagnostics
```

Without the future marker ABI, the path is deliberately shorter:

```text
ReShade OpenGL events
        |
        v
structural candidate tracking
        |
        +--> MAIN_CANDIDATE / AMBIGUOUS
        |
        +--> no authoritative SL_MAIN_* resource publication
```

## Components

### RuntimeObserver

Implemented in `src/Addon.cpp` using supported ReShade events:

- `bind_render_targets_and_depth_stencil`
- `destroy_resource`
- `init_swapchain` (resize invalidation)
- `destroy_device`
- `present`
- `init_effect_runtime` / `destroy_effect_runtime`
- `reshade_begin_effects` / `reshade_finish_effects`

The observer converts ReShade resource views into opaque resource identity plus width, height, format, and usage. It does not read native Firestorm C++ pointers and does not claim access to native framebuffer object IDs that ReShade does not expose as a first-class supported event value.

### MainViewClassifier

`MainViewClassifier` owns classification state:

- `UNINITIALIZED`
- `OBSERVING`
- `MAIN_CANDIDATE`
- `MAIN_CONFIRMED`
- `AUXILIARY_CONFIRMED`
- `AMBIGUOUS`

A ReShade-only deferred-like observation can reach only `MAIN_CANDIDATE` or `AMBIGUOUS`. `MAIN_CONFIRMED` and `AUXILIARY_CONFIRMED` require the versioned source-backed marker ABI defined in `NativeSemanticInterface.hpp`.

This is intentional. `FS-AUX-001` source-proves that main, standard-probe, and hero-probe packs can share the same deferred structure and can reuse the singleton viewer camera and deferred pipeline.

### ResourceTracker

`ResourceTracker` maintains three distinct resource concepts:

- current ReShade-bound target set;
- latest deferred-like candidate set;
- confirmed semantic main G-buffer set.

It tracks two monotonically increasing epochs:

- candidate epoch: diagnostic-only, changes when a different deferred-like candidate is observed;
- semantic resource generation: public contract value, changes when the confirmed semantic main set is replaced or invalidated.

A probe-like candidate cannot increment the semantic generation or replace the confirmed main set.

### StageTracker

The stage tracker deliberately has two layers:

- candidate stage: `DEFERRED_LIKE_BUILDING` / `DEFERRED_LIKE_COMPLETE`, based on observation only;
- semantic stage: the public `SL_RENDER_STAGE` values, which require source-backed markers for named Firestorm stages.

A fullscreen draw is not a stage transition.

### BridgeContract

At `reshade_begin_effects`, the bridge updates matching scalar uniforms by name and ReShade texture semantics using `effect_runtime::update_texture_bindings`.

Main G-buffer texture semantics are bound only when:

1. a source-backed main marker confirmed the currently observed target set; and
2. ReShade can create a supported shader-resource view of the underlying OpenGL resource.

The views are transient for the ReShade effect-render interval and are removed/destroyed at `reshade_finish_effects`. The bridge does not issue render commands, copies, barriers, clears, or draws.

### Diagnostics

The named ReShade overlay `SLRenderBridge` reports:

- semantic classification and confidence;
- semantic stage and candidate stage;
- current native-marker context;
- ReShade present-frame ID;
- resource generation and candidate epoch;
- current observed resource/view identities and descriptions;
- confirmed main resource identities;
- main publication / auxiliary / ambiguity counters;
- last invalidation reason;
- semantic stage history;
- image-write count.

The diagnostics are UI/log metadata only and do not alter the rendered image.

## Future Firestorm semantic marker boundary

`include/slrenderbridge/NativeSemanticInterface.hpp` defines a small bridge-side C ABI receiver. Phase 1 exports:

```text
SLRenderBridge_Notify(const SLRB_NativeEventV1*)
```

No Firestorm modification is included.

A future minimal Firestorm patch can call this function at source-proven semantic boundaries while normal OpenGL calls continue to be observed through ReShade. The marker carries semantic context/stage and optional matrices, not raw `GLuint` texture names. This avoids depending on undocumented conversion from Firestorm GL names to ReShade opaque handles.

The important marker is `MAIN_GBUFFER_BOUND`: it should be emitted while/after `mMainRT.deferredScreen` is the active Firestorm target so the bridge can attach semantic meaning to the ReShade-observed target set already in its tracker.

## Ownership and lifecycle

- `BridgeCore` owns classification, resource, stage, counters, and matrix snapshots.
- Render/overlay access is serialized by a mutex because the ReShade UI and render callbacks must not race.
- ReShade effect runtimes own a small private `RuntimeBindings` structure.
- Shader-resource views created by the bridge exist only between ReShade begin/finish-effects callbacks.
- `destroy_resource`, swapchain resize, device destruction, and future Firestorm invalidation markers clear stale semantic resource handles immediately.
- A semantic invalidation increments `SL_RESOURCE_GENERATION`.

## Frame identity

`SL_FRAME_ID` is explicitly defined as the 64-bit ReShade present epoch, encoded to effects as `uint2 {low32, high32}`.

It is not claimed to equal Firestorm `gFrameCount` or to identify a semantic main render by itself. Its purpose is to group repeated ReShade callbacks between presentation boundaries. The optional native ABI separately carries `native_frame_id` for a future Firestorm-provided semantic frame identity.

## Build and deployment

Compiler/toolchain target:

- Windows x64
- MSVC (Visual Studio 2022 toolchain is the intended compiler)
- CMake 3.20+
- ReShade source/SDK with add-on API 20

Build:

```bat
src\SLRenderBridge\build-msvc.bat C:\path\to\reshade
```

Equivalent CMake configuration:

```bat
cmake -S src\SLRenderBridge -B build\SLRenderBridge -A x64 ^
  -DSLRB_BUILD_ADDON=ON -DSLRB_BUILD_TESTS=ON ^
  -DRESHADE_SDK_DIR=C:\path\to\reshade
cmake --build build\SLRenderBridge --config Release
ctest --test-dir build\SLRenderBridge -C Release --output-on-failure
```

Output:

```text
build\SLRenderBridge\Release\SLRenderBridge.addon64
```

Deployment is the existing repository native-add-on convention: place the `.addon64` in the Firestorm application root where ReShade loads add-ons. Firestorm should be closed while replacing a native add-on file.
