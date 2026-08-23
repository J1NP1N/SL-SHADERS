# FS-POST-001

## Question

What is the authoritative main-view scene-color/post-processing resource lineage from deferred-lighting completion through final pre-UI scene output?

## Repository State

- Repository: `https://github.com/FirestormViewer/phoenix-firestorm`
- Branch: `master`
- Commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`
- Platform: Windows
- Renderer: OpenGL
- Rendering path: normal main-view rendering
- Accepted prior evidence: `FS-FRAME-001.md`, `FS-GBUF-001.md`
- Audit type: source analysis only. No runtime capture/profiling proof is claimed.

The pinned commit was directly retrievable. No revision substitution was required.

## Executive Resource Map

```text
accepted prior boundary:
LLPipeline::mMainRT.deferredScreen G-buffer complete
    ↓
LLPipeline::renderDeferredLighting()
    ↓
LLPipeline::mMainRT.screen / color 0
requested format: GL_RGBA16F
shared depth: mMainRT.deferredScreen.mDepth
    ├─ deferred lighting writes scene lighting here
    └─ renderGeomPostDeferred() continues writing here
         ├─ fullbright/post-deferred geometry
         ├─ forward alpha PRE water
         ├─ transparent-water copy:
         │    mMainRT.screen color + deferredScreen depth
         │       → LLPipeline::mWaterDis       [AUXILIARY COPY ONLY]
         │    water then samples mWaterDis and writes back into mMainRT.screen
         └─ forward alpha POST water
    ↓
completed world scene = mMainRT.screen / color 0
ordinary HUD/UI not yet present
    ↓
LLPipeline::renderFinalize()
    ↓
HDR-capable branch:
    ├─ mMainRT.screen + deferred depth
    │      → mSceneMap                         [SSR AUXILIARY COPY; NOT AUTHORITY]
    ├─ mMainRT.screen
    │      → mLuminanceMap → mExposureMap     [ANALYSIS; NOT SCENE COLOR]
    └─ tonemap:
         ├─ CAS active:
         │    mMainRT.screen → mMainRT.deferredLight
         │    → applyCAS → mPostPingMap
         └─ CAS inactive:
              mMainRT.screen → mPostPingMap

legacy/non-HDR branch:
    mMainRT.screen → gammaCorrect → mPostPingMap
    ↓
authoritative post scene = mPostPingMap
    ↓
generateGlow(mPostPingMap) → mGlow[0..2]       [AUXILIARY]
combineGlow(mPostPingMap, mPostPongMap)
    ↓
authoritative post scene = mPostPongMap
    ↓
optional DoF: sourceBuffer → targetBuffer; swap pointers
    ↓
optional FXAA: sourceBuffer → targetBuffer; swap pointers
or optional SMAA:
    sourceBuffer → mFXAAMap/mSMAABlendBuffer   [HELPERS]
    sourceBuffer → targetBuffer; swap pointers
    ↓
optional Firestorm/RLVa effects:
    active source → alternate target
    (target starts as mMainRT.screen when FSAA is enabled,
     otherwise mPostPingMap; successful effects rotate active/target)
    ↓
optional debug buffer visualization can overwrite the active post target
    ↓
final active sourceBuffer
    → full-screen final post/noise draw
    → OpenGL default framebuffer 0 / GL_BACK
    ↓
FINAL PRE-ORDINARY-UI RESOURCE = default framebuffer/backbuffer
    ├─ renderFinalize() may still add special snapshot-guide/focus/debug overlays
    └─ ordinary HUD / HUD attachments / 3D UI / 2D UI have not yet run
    ↓
ordinary HUD/UI composition (some 2D UI may use mUIScreen as an auxiliary cache)
    ↓
swap()
    ↓
LLWindowWin32::swapBuffers()
    ↓
Win32 SwapBuffers(mhDC)
```

The central identity/content distinction is:

- `mMainRT.screen` is the authoritative world-scene object through deferred lighting and post-deferred geometry.
- `mWaterDis` and `mSceneMap` can hold valid scene copies without becoming authoritative scene color.
- After tonemap/gamma, authoritative scene color moves into the post chain and is represented by the current `sourceBuffer` pointer, not by a permanently fixed texture name.
- After the final full-screen presentation draw in `renderFinalize()`, authoritative pre-ordinary-UI scene color is in the default framebuffer/backbuffer, not in an `LLRenderTarget`.

## Resource Inventory

### `LLPipeline::mMainRT.screen`

- **Owner:** static `LLPipeline gPipeline` → `LLPipeline::mMainRT` → `RenderTargetPack::screen`.
- **Type:** `LLRenderTarget` value member.
- **Purpose:** authoritative main-view lit/composited world-scene color during deferred lighting and post-deferred geometry; can later be reused as a post-effect destination.
- **Color attachment(s):** one managed color attachment, `LLRenderTarget::mTex[0]` / `GL_COLOR_ATTACHMENT0`.
- **Requested format:** `GL_RGBA16F` in `LLPipeline::allocateScreenBufferInternal()`.
- **Depth relationship:** owns no separate depth texture in this path. `mMainRT.deferredScreen.shareDepthBuffer(mMainRT.screen)` attaches the exact deferred-screen depth texture to `screen`.
- **Allocation:** `LLPipeline::allocateScreenBufferInternal(U32,U32)` → `mRT->screen.allocate(resX,resY,GL_RGBA16F)`.
- **Resize/recreation:** normal screen resize path calls `releaseScreenBuffers()` and then `allocateScreenBuffer()`; allocation failure can release partial state and retry lower resolutions.
- **Destruction:** `releaseScreenBuffers()` → `screen.release()`; `LLRenderTarget::~LLRenderTarget()` also calls `release()`.
- **Main-view or auxiliary:** main-view only when the current pack is `mMainRT`; accepted prior evidence establishes normal visible-camera rendering uses `mRT == &mMainRT` and that `mRT` can be temporarily replaced for auxiliary rendering.
- **Configuration dependence:** the main screen target itself is required; its GL object identity can change across resize, GL-buffer recreation, teardown, or reallocation.

### `LLPipeline::mMainRT.deferredLight`

- **Owner:** `LLPipeline::mMainRT` → `RenderTargetPack::deferredLight`.
- **Type:** `LLRenderTarget` value member.
- **Purpose:** deferred-lighting/intermediate scratch; also the temporary tonemap destination when HDR CAS is active.
- **Color attachment(s):** one color attachment.
- **Requested format:** `screenFormat`, where source defines `screenFormat = hdr ? GL_RGBA16F : GL_RGBA`.
- **Depth relationship:** no requested depth in this allocation.
- **Allocation:** `allocateScreenBufferInternal()` conditionally allocates it when HDR, shadow detail, SSAO, DoF, or RLVa post processing requires it.
- **Resize/recreation:** same screen-buffer release/reallocate family as `screen`.
- **Destruction:** `releaseScreenBuffers()` → `deferredLight.release()`; destructor also releases.
- **Main-view or auxiliary:** member of the main render-target pack when `mRT == &mMainRT`, but semantically an intermediate rather than persistent scene authority.
- **Configuration dependence:** may be released entirely when its enabling conditions are absent.

### `LLPipeline::mWaterDis`

- **Owner:** `LLPipeline` value member outside `RenderTargetPack`.
- **Type:** `LLRenderTarget`.
- **Purpose:** water distortion/refraction scratch; source comment in allocation calls it water reflection scratch space. Transparent water copies scene color/depth here for sampling.
- **Color attachment(s):** one color attachment.
- **Requested format:** `screenFormat` = HDR-capable `GL_RGBA16F`, otherwise `GL_RGBA`.
- **Depth relationship:** allocated with `depth=true`, giving it its own `GL_DEPTH_COMPONENT24` depth texture through `LLRenderTarget::allocateDepth()`.
- **Allocation:** `allocateScreenBufferInternal()` → `mWaterDis.allocate(resX,resY,screenFormat,true)`.
- **Resize/recreation:** released/reallocated with screen buffers.
- **Destruction:** `releaseScreenBuffers()` → `mWaterDis.release()`; destructor also releases.
- **Main-view or auxiliary:** auxiliary sampling target. It is not the authoritative scene target.
- **Configuration dependence:** allocation is source-commented as always needed as scratch space whether or not transparent water is enabled; actual transparent-water copy is conditional.

### `LLPipeline::mSceneMap`

- **Owner:** `LLPipeline` value member.
- **Type:** `LLRenderTarget`.
- **Purpose:** source comment: copy of color/depth just before gamma correction for SSR use.
- **Color attachment(s):** one color attachment.
- **Requested format:** `screenFormat` = HDR-capable `GL_RGBA16F`, otherwise `GL_RGBA`.
- **Depth relationship:** allocated with its own depth texture (`depth=true`). `copyScreenSpaceReflections()` copies `mRT->screen` color and `mRT->deferredScreen` depth into it using `gCopyDepthProgram`.
- **Allocation:** `allocateScreenBufferInternal()` only when `RenderScreenSpaceReflections` is enabled; otherwise `mSceneMap.release()`.
- **Resize/recreation:** released/reallocated with screen buffers; topology can change when settings cause screen/GL-buffer recreation.
- **Destruction:** `releaseScreenBuffers()` → `mSceneMap.release()`; destructor also releases.
- **Main-view or auxiliary:** auxiliary SSR/reflection sampling copy. It does not become current authoritative scene color.
- **Configuration dependence:** conditional on `RenderScreenSpaceReflections`; the copy operation in `renderFinalize()` is additionally under the HDR-capable branch and rejects cube snapshots.

### `LLPipeline::mLuminanceMap`, `mExposureMap`, `mLastExposure`

- **Owner:** `LLPipeline` value members.
- **Type:** `LLRenderTarget`.
- **Purpose:** luminance/exposure analysis and temporal exposure history, not scene-color storage.
- **Requested formats:** `mLuminanceMap` = `GL_R16F` at 256×256 with automatic mip generation; `mExposureMap` = `GL_R16F` at 1×1; `mLastExposure` = `GL_R16F` at 1×1.
- **Depth relationship:** none requested.
- **Allocation:** `createLUTBuffers()`.
- **Resize/recreation:** independent of main full-resolution screen size; `releaseLUTBuffers()` / `createLUTBuffers()` recreate them. `generateExposure()` copies the prior exposure into `mLastExposure` when history is enabled.
- **Destruction:** `releaseLUTBuffers()` releases all three; object destruction also releases.
- **Main-view or auxiliary:** auxiliary analysis/history resources.
- **Configuration dependence:** used by HDR exposure path; they are not authoritative scene color at any stage.

### `LLPipeline::mPostPingMap` / `mPostPongMap`

- **Owner:** `LLPipeline` value members.
- **Type:** `LLRenderTarget`.
- **Purpose:** full-resolution post-processing ping-pong targets. Header comment identifies them as the tonemapped/gamma-corrected render ready for post.
- **Color attachment(s):** one each.
- **Requested format:** exact requested token `GL_RGBA` for both; no sized driver-resolved format is inferred here.
- **Depth relationship:** no requested depth.
- **Allocation:** `allocateScreenBufferInternal()` → `mPostPingMap.allocate(resX,resY,GL_RGBA)` and `mPostPongMap.allocate(resX,resY,GL_RGBA)`.
- **Resize/recreation:** released/reallocated with screen buffers.
- **Destruction:** `releaseScreenBuffers()` releases both; destructors also release.
- **Main-view or auxiliary:** main-view post chain for the normal path, but the current authoritative one is whichever object the local `sourceBuffer` pointer names after each transition.
- **Configuration dependence:** allocated for the normal non-cube screen-buffer path; contents are overwritten/reused frame to frame.

### `LLPipeline::mGlow[0..2]`

- **Owner:** `LLPipeline` value-member array.
- **Type:** `LLRenderTarget` array.
- **Purpose:** glow extraction and blur ping-pong scratch only. `generateGlow()` writes these; `combineGlow()` writes the combined scene into a post target.
- **Color attachment(s):** one each.
- **Requested format:** `RenderGlowHDR ? GL_RGBA16F : GL_RGBA`.
- **Resolution:** 512 × `glow_res`, where `glow_res` is derived from `RenderGlowResolutionPow` and clamped by source.
- **Depth relationship:** none requested.
- **Allocation:** `createGLBuffers()` allocates all three.
- **Resize/recreation:** ordinary full-screen resize does not source-prove a reallocation of these fixed-size glow targets; GL-buffer recreation and glow-resolution/HDR setting changes do.
- **Destruction:** `releaseGLBuffers()` releases the array; destructors also release.
- **Main-view or auxiliary:** auxiliary glow scratch; never authoritative full scene color.
- **Configuration dependence:** `RenderGlowHDR` changes format; `RenderGlowResolutionPow` changes resolution; `sRenderGlow` controls whether glow is generated, but the no-glow path clears the result target so `combineGlow()` can still run.

### `LLPipeline::mFXAAMap` / `mSMAABlendBuffer`

- **Owner:** `LLPipeline` value members.
- **Type:** `LLRenderTarget`.
- **Purpose:** anti-aliasing helper targets, not persistent authoritative scene color.
- **Requested format:** `GL_RGBA`.
- **Depth relationship:** none requested.
- **Allocation:** full-resolution in `allocateScreenBufferInternal()` when `RenderFSAAType > 0`; `mSMAABlendBuffer` exists only for SMAA (`RenderFSAAType == 2`).
- **Resize/recreation:** released/reallocated with screen buffers; `RenderFSAAType` is registered to a GL-buffer recreation callback.
- **Destruction:** `releaseScreenBuffers()` releases the helper targets; destructors also release.
- **Main-view or auxiliary:** post-process helpers.
- **Configuration dependence:** FXAA helper only when FSAA is enabled; SMAA blend helper only in SMAA mode.

### `LLPipeline::mUIScreen`

- **Owner:** `LLPipeline` value member.
- **Type:** `LLRenderTarget`.
- **Purpose:** optional UI cache/composition target after the scene-post boundary; not a scene-color authority.
- **Requested format:** `GL_RGBA`.
- **Depth relationship:** none requested in the allocation shown.
- **Allocation:** `allocateScreenBufferInternal()` only when `RenderUIBuffer` is enabled.
- **Resize/recreation:** `RenderUIBuffer` uses the screen-resize callback; the target is released/reallocated with screen buffers.
- **Destruction:** `releaseScreenBuffers()` → `mUIScreen.release()`; destructor also releases.
- **Main-view or auxiliary:** UI auxiliary target downstream of final scene post-processing.
- **Configuration dependence:** conditional on `RenderUIBuffer`.

### OpenGL default framebuffer / backbuffer

- **Owner:** platform/window OpenGL context rather than an `LLRenderTarget` member.
- **Type:** default framebuffer (`GL_FRAMEBUFFER` 0), normal draw/read back buffer (`GL_BACK`) in the `LLRenderTarget::flush()` fallback state.
- **Purpose:** final presented scene destination and subsequent ordinary UI composition destination.
- **Color attachment(s):** platform default framebuffer attachment details are outside this audit.
- **Requested format:** `UNRESOLVED` by this task; no inference is made from window defaults.
- **Depth relationship:** not required for the resource-lineage conclusion here.
- **Allocation/destruction:** platform/window/context managed; not allocated by `LLRenderTarget::allocate()`.
- **Main-view or auxiliary:** final main-view presentation surface.
- **Configuration dependence:** window/context recreation can change platform resources; there is no stable scene-color texture GL name to cache here.

## Scene-Color Lineage

### Transition 1 — deferred lighting begins producing main scene color

**Before:** completed G-buffer in `mMainRT.deferredScreen` (accepted prior evidence).

**Operation:** `LLPipeline::renderDeferredLighting()` sets `screen_target = &mRT->screen`. After light-buffer setup it binds `screen_target`, clears its color buffer, and executes the deferred scene-lighting passes.

**After:** `mMainRT.screen` color attachment 0 contains the evolving lit scene.

**Authority:** destination becomes authoritative main-view scene color.

**Status:** SOURCE-PROVEN.

### Transition 2 — post-deferred fullbright/alpha/water evolve the same scene target in place

**Before:** `mMainRT.screen` lit scene.

**Operation:** while `screen_target` is active, `renderDeferredLighting()` calls `renderGeomPostDeferred()`. Accepted frame evidence establishes this phase includes post-deferred fullbright/glow categories, forward alpha, water, and the pre-/post-water ordering boundaries.

**After:** the same `mMainRT.screen` color attachment contains progressively more complete world-scene contents.

**Authority:** unchanged object; contents evolve in place.

**Status:** SOURCE-PROVEN.

### Transition 3 — transparent-water scene copy

**Before:** `mMainRT.screen` contains scene color up to the water pass; `mMainRT.deferredScreen` provides depth.

**Operation:** `LLDrawPoolWater::beginPostDeferredPass()` binds `mWaterDis`, binds `screen` as diffuse and `deferredScreen` as depth, and draws a full-screen copy. `mWaterDis.flush()` restores the previously active render target. Water then samples `mWaterDis` and draws water geometry.

**After:** `mWaterDis` holds a color/depth sampling copy; the authoritative evolving scene remains `mMainRT.screen`, now updated by the water draw.

**Authority:** `mWaterDis` remains auxiliary; authority does not move.

**Status:** SOURCE-PROVEN.

### Transition 4 — completed world scene at `renderFinalize()` entry

**Before:** `mMainRT.screen` after the final post-deferred draw pools.

**Operation:** `renderDeferredLighting()` flushes `screen_target` only after `renderGeomPostDeferred()`. `render_ui()` later calls `gPipeline.renderFinalize()` before ordinary HUD/3D UI/2D UI.

**After:** `mMainRT.screen` color 0 is the completed world-scene input to final post processing.

**Authority:** `mMainRT.screen` remains authoritative until a post-processing destination has been produced.

**Status:** SOURCE-PROVEN.

### Transition 5 — HDR SSR copy is auxiliary

**Before:** authoritative scene = `mMainRT.screen`.

**Operation:** in the HDR-capable branch, `renderFinalize()` calls `copyScreenSpaceReflections(&mRT->screen, &mSceneMap)`. The copy function binds/clears `mSceneMap` and samples both source scene color and deferred depth.

**After:** `mSceneMap` contains a pre-gamma scene/depth copy for SSR/reflection sampling.

**Authority:** remains `mMainRT.screen`; `mSceneMap` is auxiliary.

**Status:** SOURCE-PROVEN.

**Clarification relative to accepted frame evidence:** within `renderFinalize()` specifically, the source proves an SSR scene/depth **copy**. This audit does not infer that `mSceneMap` itself becomes the current scene or that the SSR sampling/composition use occurs at that exact call site.

### Transition 6 — luminance/exposure analysis does not move scene authority

**Before:** authoritative scene = `mMainRT.screen`.

**Operation:** HDR path calls `generateLuminance(&mRT->screen,&mLuminanceMap)` and `generateExposure(&mLuminanceMap,&mExposureMap)`. Exposure history can copy the previous exposure into `mLastExposure`.

**After:** scene authority is still `mMainRT.screen`; luminance/exposure resources contain analysis/state only.

**Authority:** unchanged.

**Status:** SOURCE-PROVEN.

### Transition 7 — tonemap/gamma moves authority into the post chain

**Before:** authoritative scene = `mMainRT.screen`.

**Operation:** source branches:

- HDR + CAS active: `tonemap(screen,deferredLight,false)` then `applyCAS(deferredLight,mPostPingMap)`; source comment identifies CAS as performing gamma correction in this branch.
- HDR + CAS inactive: `tonemap(screen,mPostPingMap,true)`.
- non-HDR: `gammaCorrect(screen,mPostPingMap)`.

**After:** `mPostPingMap` is the authoritative tonemapped/gamma-corrected scene. In the CAS branch, `mMainRT.deferredLight` is a brief authoritative intermediate only between tonemap and CAS.

**Authority:** moves from `mMainRT.screen` to `mPostPingMap` after the branch completes.

**Status:** SOURCE-PROVEN.

### Transition 8 — glow generation is auxiliary; glow combine moves authority to pong

**Before:** authoritative scene = `mPostPingMap`.

**Operation:** `generateGlow(&mPostPingMap)` builds glow scratch in `mGlow[0..2]`. `renderFinalize()` then initializes `sourceBuffer=&mPostPingMap`, `targetBuffer=&mPostPongMap`, calls `combineGlow(sourceBuffer,targetBuffer)`, and swaps the pointers.

**After:** authoritative scene = `mPostPongMap`; the local `sourceBuffer` pointer names it.

**Authority:** glow scratch never becomes full-scene authority; `combineGlow()` destination does.

**Status:** SOURCE-PROVEN.

### Transition 9 — optional DoF ping-pongs the authoritative scene

**Before:** current authoritative post scene = `sourceBuffer`.

**Operation:** when enabled by the source condition, `renderDoF(sourceBuffer,targetBuffer)` is called, then `std::swap(sourceBuffer,targetBuffer)`.

**After:** the prior `targetBuffer` becomes authoritative and is now named by `sourceBuffer`.

**Authority:** follows `sourceBuffer`.

**Status:** SOURCE-PROVEN.

### Transition 10 — FXAA/SMAA ping-pong the authoritative scene

**Before:** current authoritative post scene = `sourceBuffer`.

**Operation:**

- FXAA (`RenderFSAAType == 1`): `applyFXAA(sourceBuffer,targetBuffer)` then swap.
- SMAA (`RenderFSAAType == 2`): `generateSMAABuffers(sourceBuffer)` populates AA helpers, then `applySMAA(sourceBuffer,targetBuffer)` and swap.

**After:** the prior target becomes authoritative scene color, named by `sourceBuffer`.

**Authority:** helper buffers do not become scene authority; the final AA destination does.

**Status:** SOURCE-PROVEN.

### Transition 11 — Firestorm/RLVa post effects can rotate authority through an alternate target

**Before:** current authoritative post scene = `sourceBuffer` after DoF/AA.

**Operation:** source creates `auxActiveBuffer = sourceBuffer` and chooses `auxTargetBuffer = RenderFSAAType ? &mRT->screen : &mPostPingMap`. RLVa sphere processing can replace the active/target pair from returned parameters. `renderVignette()` and `renderSnapshotFrame()` each render from active to target when enabled and swap the pointers after success. Finally `sourceBuffer = auxActiveBuffer`.

**After:** authoritative scene is whichever render target `sourceBuffer` names after the enabled effect sequence. `mMainRT.screen` may therefore be reused as post scratch after it has ceased being the authoritative pre-tonemap world scene.

**Authority:** follows the active/source pointer, not resource naming.

**Status:** SOURCE-PROVEN for the pointer/resource transitions.

**Bounded unresolved edge:** the source-level alias behavior of every combination of no-AA/DoF/RLVa/vignette/snapshot settings is not exhaustively enumerated here. The source-defined active/target pointer logic is recorded; detailed post-effect correctness/alias analysis is proposed as a separate task if needed.

### Transition 12 — optional buffer visualization mutates contents without necessarily changing identity

**Before:** current authoritative post scene = `sourceBuffer`.

**Operation:** when `RenderBufferVisualization > -1`, `visualizeBuffers()` renders selected deferred/luminance/AA diagnostic data into the current post destination.

**After:** the same active post resource can hold visualization contents rather than the normal world scene.

**Authority:** resource identity can stay the same while semantic contents change.

**Status:** SOURCE-PROVEN.

### Transition 13 — final post source is rendered to the default backbuffer

**Before:** final authoritative offscreen scene = current `sourceBuffer`.

**Operation:** under source comment `Present the screen target`, `gDeferredPostNoDoFNoiseProgram` samples `sourceBuffer` plus deferred depth and draws the full-screen triangle. No destination `LLRenderTarget::bindTarget()` is performed for this final draw. In the normal path, the preceding render-target operations have been flushed. `LLRenderTarget::flush()` restores the prior target, and when no prior target exists it binds framebuffer 0, sets read/draw buffers to `GL_BACK`, and restores the window viewport.

**After:** final post-processed scene color resides in OpenGL default framebuffer 0 / the backbuffer.

**Authority:** moves from offscreen `sourceBuffer` to the backbuffer.

**Status:** SOURCE-PROVEN for the normal main-view path.

### Transition 14 — ordinary UI is downstream of the backbuffer scene

**Before:** default backbuffer contains final post-processed scene. `renderFinalize()` may additionally draw its own special snapshot-guide/focus/physics-debug overlays before returning.

**Operation:** `render_ui()` proceeds into ordinary HUD elements/HUD attachments, 3D UI, 2D UI, and debug text. When `RenderUIBuffer` is enabled, parts of the 2D UI can be rendered to `mUIScreen` and then composited, but `mUIScreen` is an auxiliary UI cache rather than a replacement scene authority.

**After:** backbuffer contains UI-complete frame contents.

**Authority:** final presentation surface remains the default backbuffer.

**Status:** SOURCE-PROVEN at the resource boundary; detailed UI renderer ownership is intentionally outside scope.

## Findings

### Finding 1 — `mMainRT.screen`, not `deferredLight`, is the authoritative main lit/world scene target

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.h`
- Class: `LLPipeline`
- Symbols: `RenderTargetPack::screen`, `deferredScreen`, `deferredLight`, `mMainRT`, `mRT`
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `allocateScreenBufferInternal()`, `renderDeferredLighting()`

**What the source proves:** `screen_target` is explicitly assigned `&mRT->screen`; that target is bound/cleared for scene lighting and remains the target around post-deferred rendering. `deferredLight` is an intermediate/scratch target.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** identifying lit scene color by FBO dimensions, texture activity, or naming guesses.

### Finding 2 — main `screen` color is requested as `GL_RGBA16F` and shares deferred depth

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `allocateScreenBufferInternal()`
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Functions: `allocate()`, `shareDepthBuffer()`

**What the source proves:** Firestorm calls `mRT->screen.allocate(resX,resY,GL_RGBA16F)` and then attaches `deferredScreen`'s depth texture to `screen`. This records the exact requested color token; it is not runtime proof of driver storage details beyond that token.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** guessing the scene-color texture format or pairing scene color with a same-sized but unrelated depth texture.

### Finding 3 — post-deferred world rendering evolves `mMainRT.screen` in place

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `renderDeferredLighting()`, `renderGeomPostDeferred()`
- Accepted prior evidence: `FS-FRAME-001.md`

**What the source proves:** `renderGeomPostDeferred()` runs while the main `screen_target` is active, and `screen_target` is flushed afterward. Therefore fullbright/forward/water-stage world draws evolve the same scene-color resource rather than moving the scene to a separate persistent target.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** assuming a separate “post-alpha scene texture” must exist.

### Finding 4 — `mWaterDis` is an auxiliary pre-water copy, not authoritative scene color

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/lldrawpoolwater.cpp`
- Class: `LLDrawPoolWater`
- Functions: `beginPostDeferredPass()`, `renderPostDeferred()`
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Functions: `bindTarget()`, `flush()`

**What the source proves:** transparent water copies `mRT->screen` color and deferred depth into `mWaterDis`, then samples `mWaterDis` while water is drawn into the restored parent scene target. The copy is sampling state, not scene authority.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** mistaking the water/refraction copy for the current main scene texture.

### Finding 5 — `mMainRT.screen` is the completed world-scene input to `renderFinalize()`

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `renderDeferredLighting()`, `renderFinalize()`
- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `render_ui()`
- Accepted prior evidence: `FS-FRAME-001.md`

**What the source proves:** the scene target is flushed after post-deferred geometry; final post processing later reads `mRT->screen`. `render_ui()` invokes `renderFinalize()` before ordinary HUD/3D/2D UI composition.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** guessing whether a sampled scene texture is pre-alpha, post-water, or UI-contaminated.

### Finding 6 — `mSceneMap` is an SSR auxiliary copy and does not take current-scene authority

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.h`
- Class: `LLPipeline`
- Symbol/comment: `mSceneMap` — copy of color/depth just before gamma correction for SSR
- Path: `indra/newview/pipeline.cpp`
- Functions: `allocateScreenBufferInternal()`, `copyScreenSpaceReflections()`, `renderFinalize()`, reflection-probe shader binding path

**What the source proves:** when enabled, `mSceneMap` receives copied scene color and depth for SSR/reflection sampling. No authority transfer to `mSceneMap` occurs in `renderFinalize()`.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** treating an SSR scene copy as the renderer's authoritative current scene.

### Finding 7 — luminance/exposure targets are analysis state, not scene-color lineage nodes

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.h`
- Class: `LLPipeline`
- Symbols: `mLuminanceMap`, `mExposureMap`, `mLastExposure`
- Path: `indra/newview/pipeline.cpp`
- Functions: `createLUTBuffers()`, `generateLuminance()`, `generateExposure()`, `releaseLUTBuffers()`

**What the source proves:** these R16F targets downsample/analyze luminance and preserve exposure history. They never become full-scene color.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** classifying every full-screen render-target transition in `renderFinalize()` as a scene-color ping-pong step.

### Finding 8 — tonemap/gamma is the authoritative transfer from world-scene `screen` into the post chain

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `renderFinalize()`, `tonemap()`, `gammaCorrect()`, `applyCAS()`

**What the source proves:** all normal finalize branches converge on `mPostPingMap`: HDR without CAS writes there directly; HDR with CAS uses `mRT->deferredLight` as an intermediate and then writes post ping; non-HDR gamma correction writes post ping.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** guessing the post-processing scene target from full-screen draw ordering.

### Finding 9 — `mPostPingMap` / `mPostPongMap` carry post authority through explicit pointer swaps

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.h`
- Class: `LLPipeline`
- Symbols: `mPostPingMap`, `mPostPongMap`
- Path: `indra/newview/pipeline.cpp`
- Function: `renderFinalize()`

**What the source proves:** Firestorm creates local `sourceBuffer`/`targetBuffer` pointers, performs a post operation, and swaps the pointers after each output-producing stage. Therefore “authoritative post scene” is a stage-dependent pointer identity, not a fixed ping or pong member.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** pinning an interceptor to one post texture name across DoF/AA/effect setting changes.

### Finding 10 — glow scratch is separate from the authoritative post scene

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `generateGlow()`, `combineGlow()`, `createGLBuffers()`

**What the source proves:** glow is extracted/blurred in `mGlow[0..2]`; `combineGlow()` samples the post scene plus the glow result and writes a complete scene into the alternate post target. The glow targets themselves are never the full scene.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** mistaking glow buffers for downscaled authoritative scene-color textures.

### Finding 11 — DoF and AA preserve authority by output-target swap, while AA helper targets remain auxiliary

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `renderFinalize()`, `renderDoF()`, `applyFXAA()`, `generateSMAABuffers()`, `applySMAA()`
- Path: `indra/newview/pipeline.h`
- Symbols: `mFXAAMap`, `mSMAABlendBuffer`

**What the source proves:** optional DoF/AA stages write to the current alternate target and then swap scene pointers. FXAA/SMAA helpers support the operation but do not become persistent scene authority.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** identifying the final scene by observing an AA helper texture or assuming the same ping target wins every frame.

### Finding 12 — Firestorm/RLVa effects can reuse `mMainRT.screen` as post scratch after scene authority has left it

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions/symbols: `renderFinalize()`, `renderVignette()`, `renderSnapshotFrame()`, RLVa `LLVfxManager::runEffect()`, `auxActiveBuffer`, `auxTargetBuffer`

**What the source proves:** after DoF/AA, Firestorm sets the effect target to `mRT->screen` when FSAA is enabled, otherwise `mPostPingMap`. Thus the architectural object `mMainRT.screen` can later hold post-effect output even though its earlier contents were the completed pre-post world scene.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** assuming a resource's semantic role is fixed for the whole frame solely because its C++ identity is stable.

### Finding 13 — final pre-ordinary-UI scene is the OpenGL default backbuffer, not an offscreen `LLRenderTarget`

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `renderFinalize()`; final `Present the screen target` full-screen draw
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Function: `flush()`

**What the source proves:** the final post shader samples the current `sourceBuffer` and draws without binding another `LLRenderTarget`. In the normal render-target-stack state, `flush()` has returned rendering to framebuffer 0 and explicitly sets `GL_BACK` as read/draw buffer. Therefore the final presented scene is written into the default backbuffer.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** assuming Firestorm keeps final post-processed scene color in an offscreen texture until swap.

### Finding 14 — ordinary HUD/UI is downstream of the backbuffer scene boundary

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/llviewerdisplay.cpp`
- Functions: `render_ui()`, `render_hud_attachments()`, `render_ui_3d()`, `render_ui_2d()`
- Path: `indra/newview/pipeline.cpp`
- Function: `renderFinalize()`
- Accepted prior evidence: `FS-FRAME-001.md`

**What the source proves:** `renderFinalize()` runs before ordinary viewer HUD/UI composition. The same default backbuffer is then evolved by UI work. Conditional `mUIScreen` use is an auxiliary UI cache/composite step, not a scene-color ownership transfer.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** inferring the scene/UI boundary from swap-adjacent draw counts or fullscreen-pass heuristics.

### Finding 15 — full-resolution scene/post GL names are not stable across resize and GL-buffer recreation

**Confidence:** SOURCE-PROVEN

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `resizeScreenTexture()`, `allocateScreenBuffer()`, `allocateScreenBufferInternal()`, `releaseScreenBuffers()`, `releaseGLBuffers()`, `createGLBuffers()`
- Path: `indra/newview/llviewercontrol.cpp`
- Functions/symbols: `handleReleaseGLBufferChanged()`, `handleEnableHDR()`, setting listeners for `RenderFSAAType`, `RenderDepthOfField`, `RenderGlowResolutionPow`, `RenderGlowHDR`, `RenderUIBuffer`, and related render settings
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Functions: `allocate()`, `release()`, destructor

**What the source proves:** resizing releases and reallocates screen-space targets; multiple graphics settings trigger broader GL-buffer recreation; `LLRenderTarget::release()` deletes FBOs/textures and `allocate()` creates fresh storage. Cached GL identities therefore require explicit invalidation handling.

**SL-SHADERS heuristic affected:** YES

**Potentially replaces:** assuming discovered scene/post texture names survive window-size or graphics-setting changes.

## Final Pre-UI Boundary

1. **What resource contains final post-processed scene color?**  
   The OpenGL default framebuffer/backbuffer after the final `renderFinalize()` full-screen draw. Immediately before that draw, the final offscreen source is whichever `LLRenderTarget* sourceBuffer` currently names.

2. **Is that resource offscreen or the default framebuffer?**  
   The final pre-ordinary-UI destination is the **default framebuffer**, framebuffer 0 / `GL_BACK`, not an offscreen `LLRenderTarget`.

3. **Has ordinary HUD/UI been drawn yet?**  
   No. `render_ui()` calls `renderFinalize()` first. Conditional special overlays implemented inside `renderFinalize()` (snapshot guides, focus point, physics debug) can already be present, but ordinary HUD elements/HUD attachments/3D UI/2D UI are downstream.

4. **What happens immediately afterward?**  
   Ordinary viewer UI composition proceeds. If `RenderUIBuffer` is enabled, portions of UI can be rendered to `mUIScreen` and then composited, but the presentation surface remains the backbuffer.

5. **What is the eventual Windows presentation call?**  
   Accepted prior evidence establishes `swap()` → `LLWindowWin32::swapBuffers()` → Win32 `SwapBuffers(mhDC)`.

## Lifetime and Invalidation

### `mMainRT.screen`

- Reused frame to frame as a C++ object and normally as GL storage until recreation.
- Its **contents** become the current lit scene during `renderDeferredLighting()` and the completed world scene after post-deferred geometry.
- Scene **authority** leaves it after tonemap/gamma produces the post-chain scene.
- Its old completed-world contents may persist physically, but source allows later Firestorm post effects to reuse `mRT->screen` as a destination, so consumers must not treat the pre-post contents as immutable through the remainder of the frame.
- Hard GL identity invalidators: screen-buffer release/reallocation, broader GL-buffer recreation, teardown/destruction.

### `mWaterDis`

- Full-resolution screen scratch allocated with screen buffers.
- Reused for copies/haze/water sampling; contents are stage-specific and explicitly non-authoritative.
- GL identity can change on screen-buffer/GL-buffer recreation.

### `mSceneMap`

- Exists only when SSR allocation is enabled; can be released entirely when disabled.
- Contents are a pre-gamma scene/depth copy when `copyScreenSpaceReflections()` runs.
- Not current-scene authority; consumers must not promote it based on matching dimensions or containing valid scene color.
- GL identity can change on screen-buffer/GL-buffer recreation.

### `mPostPingMap` / `mPostPongMap`

- Full-resolution, frame-to-frame reused post textures.
- Each frame's semantic authority alternates by local pointer swaps; cached “ping is final” or “pong is final” assumptions are invalid.
- GL names change when screen buffers are recreated.

### `mGlow[0..2]`

- Fixed glow-resolution scratch independent of ordinary full-screen resize in the source path examined.
- `RenderGlowResolutionPow` / `RenderGlowHDR` use GL-buffer recreation callbacks and can recreate them.
- Broader GL teardown/recreation also changes identities.

### `mFXAAMap` / `mSMAABlendBuffer`

- Conditional full-resolution helpers.
- `RenderFSAAType` uses a GL-buffer recreation callback; mode changes can create/release these objects and change other render-target names as part of the same recreation.

### Luminance/exposure targets

- Reused independently of full-screen post ping-pong.
- `mLastExposure` intentionally stores prior exposure state between frames when history is used.
- `releaseLUTBuffers()`/`createLUTBuffers()` recreate them; they are not scene-color identity candidates.

### Default framebuffer/backbuffer

- Has no Firestorm `LLRenderTarget` texture name to cache as the final scene.
- Window/context/presentation owns it.
- Exact default framebuffer color format is `UNRESOLVED` by this task because it is unnecessary to establish scene-color lineage.

## Implications for SL-SHADERS

This source evidence can eventually replace these categories of external inference without prescribing an implementation:

- guessing the authoritative lit scene texture from dimensions or recent FBO activity;
- assuming deferred-light scratch is the main scene;
- guessing whether scene color is pre-alpha/pre-water or fully composited world color;
- mistaking `mWaterDis` for authoritative scene color because it contains a valid scene copy;
- mistaking `mSceneMap` for current scene color because it contains pre-gamma color/depth for SSR;
- treating luminance/exposure or AA helpers as scene-color ping-pong resources;
- assuming one fixed post texture (`mPostPingMap` or `mPostPongMap`) is always final;
- assuming `mMainRT.screen` retains the same semantic contents throughout the whole frame;
- assuming the final world scene remains offscreen until `SwapBuffers`;
- identifying the scene/UI boundary only from swap-adjacent draw behavior;
- caching GL texture/FBO names across resize or graphics-setting recreation.

The source-backed ownership model is instead stage-based: architectural object identity and frame-stage contents must be tracked separately.

## Open Questions

- **FS-POST-002 — Firestorm post-effect alias audit:** For every supported no-AA/DoF/RLVa/vignette/snapshot combination, can `auxActiveBuffer` and `auxTargetBuffer` alias, and what exact resource is written by each enabled effect? This is a correctness/edge-case audit, not required for the main lineage established here.
- **FS-SSR-TEMPORAL-001 — SSR scene-map timing:** At what exact later render stage/frame is the `mSceneMap` copy produced in `renderFinalize()` consumed by reflection/SSR shading? This task proves the copy and its non-authoritative status but does not expand temporal SSR algorithm flow.
- **FS-BACKBUFFER-001 — Windows default framebuffer configuration:** What exact WGL pixel format/color-space characteristics back framebuffer 0 for the pinned Windows build? Not needed for scene-resource identity; left unresolved rather than inferred.

## Recommended Next Agent Task

- **Proposed task ID:** `FS-CAMERA-001`
- **Exact bounded question:** What are the authoritative normal main-view Firestorm camera, view, projection, inverse-view/projection, viewport, and depth-reconstruction inputs at commit `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`, who owns them, and at what frame/pass boundaries are they updated and bound to deferred/post shaders?
- **Why this is now the highest-value dependency:** `FS-GBUF-001` establishes authoritative native depth/normal/G-buffer resources and this task establishes authoritative scene-color/post lineage. Screen-space effects still require source-backed camera/projection reconstruction state to eliminate the remaining high-impact interception guesses without drifting into effect implementation.
- **Likely starting files/classes/symbols:** `indra/newview/llviewercamera.*` (`LLViewerCamera`); `indra/newview/llviewerdisplay.cpp` (`display_update_camera()`, `display()`, `render_ui()`); `indra/newview/llviewerwindow.*` (`setup3DRender()`); `indra/llrender/llrender.*` matrix state; `indra/llrender/llglslshader.*`; `indra/newview/pipeline.cpp` deferred/post shader binding and screen-resolution uniforms.

## Handoff Summary

- Pinned Firestorm commit `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294` was directly inspected.
- Main lit/composited world scene is `LLPipeline::mMainRT.screen` color 0, requested `GL_RGBA16F`.
- `mMainRT.screen` shares the exact depth texture owned by `mMainRT.deferredScreen`.
- Deferred lighting and post-deferred world geometry evolve `mMainRT.screen` in place.
- Transparent water copies screen color/deferred depth to `mWaterDis` only for sampling; authority stays on `screen`.
- `renderFinalize()` enters with completed world scene in `mMainRT.screen`, before ordinary HUD/UI.
- `mSceneMap` is an auxiliary SSR color/depth copy; luminance/exposure targets are analysis only.
- Tonemap/gamma moves scene authority into `mPostPingMap`; glow combine then moves it into the ping-pong chain.
- DoF/FXAA/SMAA and Firestorm effects move authority by explicit source/target pointer swaps.
- `mMainRT.screen` can later be reused as post scratch, so object identity does not imply fixed frame-stage contents.
- Final post source is drawn to OpenGL framebuffer 0 / `GL_BACK` before ordinary HUD/UI.
- Ordinary UI then modifies the backbuffer; Windows eventually presents via `SwapBuffers(mhDC)`.
- Screen/post GL names are invalidated by resize/reallocation and relevant GL-buffer recreation settings.
- Exact default-framebuffer pixel format and detailed post-effect alias combinations remain bounded open questions.
- Recommended next audit: `FS-CAMERA-001`.
