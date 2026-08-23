# FS-FRAME-001

## Question

What is the authoritative main-view Firestorm frame/pass sequence?

## Repository State

- Repository: `https://github.com/FirestormViewer/phoenix-firestorm`
- Branch: `master`
- Commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`

## Findings

### Windows frame entry reaches `LLAppViewer::frame()` and then `display()`

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/llappviewerwin32.cpp`
- Windows application main loop: `while (! viewer_app_ptr->frame()) {}`
- `indra/newview/llappviewer.cpp`
- class `LLAppViewer`, method `LLAppViewer::frame()`; `// Render scene.` block calling `display()`
- `indra/newview/llviewerdisplay.cpp`
- global `display(bool rebuild, F32 zoom_factor, int subfield, bool for_snapshot)`

**Evidence:**
The Windows application runs `viewer_app_ptr->frame()` in its main loop. `LLAppViewer::frame()` contains the explicit render-scene block and calls `display()` when the app is not exiting/headless and a viewer window exists. `llviewerdisplay.cpp` defines `display(...)` under `// Paint the display!` and profiles it as `Render`. This establishes the authoritative high-level Windows frame-to-render handoff.

**Implication for SL-SHADERS:**
This provides a source-backed outer frame boundary for later mapping of native resources and effect insertion points, without relying on swap/interception heuristics.

### Main-view world rendering is prepared and entered inside `display()`

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/llviewerdisplay.cpp`
- `display(...)`
- symbols: `display_update_camera()`, `gPipeline.updateCull(...)`, `gPipeline.stateSort(...)`, `gSky.updateSky()`, `gPipeline.mRT->deferredScreen.bindTarget()`

**Evidence:**
For a normal started, connected frame, `display()` updates the world camera/environment/HUD state, updates geometry/GL state, sets `LLViewerCamera::CAMERA_WORLD`, culls with the main viewer camera, state-sorts visible objects, updates sky, and then enters the main scene render by binding and clearing `gPipeline.mRT->deferredScreen` immediately before `gPipeline.renderGeomDeferred(...)`.

**Implication for SL-SHADERS:**
This identifies the authoritative transition from frame preparation/culling into the main-view scene render and provides a reliable boundary for later native-state/resource work.

### Major offscreen/special work occurs before the main G-buffer pass

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/llviewerdisplay.cpp`
- `display(...)`
- symbols: `LLViewerDynamicTexture::updateAllInstances()`, `gPipeline.mHeroProbeManager.update()`, `gPipeline.mHeroProbeManager.renderProbes()`, `gPipeline.generateSunShadow(...)`, `LLVOAvatar::updateImpostors()`

**Evidence:**
Before the normal main-view `deferredScreen` bind/render, `display()` may update dynamic render-to-texture content. When mirrors are enabled and the frame is not a snapshot, it explicitly updates and renders hero probes “before we render the rest of the scene.” Later, before the main deferred target is bound, it generates sun shadows (after the first frame) and updates avatar impostors.

**Implication for SL-SHADERS:**
Main-view effects must not assume every renderer draw occurring before the G-buffer belongs to the visible camera image; probe, shadow, impostor, and dynamic-texture work can precede it.

### The main G-buffer population window is the `deferredScreen` + `renderGeomDeferred()` interval

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/llviewerdisplay.cpp`
- `display(...)`
- symbols: `gPipeline.mRT->deferredScreen.bindTarget()`, `.clear()`, `gPipeline.renderGeomDeferred(...)`, render-target `.flush()`
- `indra/newview/pipeline.cpp`
- class `LLPipeline`, methods `renderGeomDeferred(...)`, `bindDeferredShader(...)`

**Evidence:**
`display()` binds and clears `mRT->deferredScreen`, then calls `LLPipeline::renderGeomDeferred(...)`. `renderGeomDeferred()` iterates draw pools with deferred passes and calls each pool's `beginDeferredPass() / renderDeferred() / endDeferredPass()`. After this call, `display()` flushes the active deferred target before deferred lighting. Separately, `LLPipeline::bindDeferredShader()` binds `mRT->deferredScreen` attachments as deferred diffuse, specular, normal, emissive, and depth inputs. This is sufficient to identify the high-level G-buffer population interval without attempting full ownership/lifetime analysis.

**Implication for SL-SHADERS:**
The authoritative “G-buffer being written” boundary is now source-located; exact attachment ownership, formats, and lifetimes remain a separate audit.

### Ordinary alpha-mask geometry participates in deferred/G-buffer rendering; some fullbright alpha-mask work is post-deferred

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/lldrawpoolsimple.cpp`
- classes/methods: `LLDrawPoolAlphaMask::renderDeferred(...)`, `LLDrawPoolFullbrightAlphaMask::renderPostDeferred(...)`, `LLDrawPoolGrass::renderDeferred(...)`

**Evidence:**
`LLDrawPoolAlphaMask::renderDeferred()` uses the deferred alpha-mask shader and submits `PASS_ALPHA_MASK` / rigged mask batches during the deferred draw-pool phase. Grass likewise uses a deferred alpha-mask shader. By contrast, `LLDrawPoolFullbrightAlphaMask::renderPostDeferred()` is explicitly a post-deferred pass. Therefore “alpha mask” is not a single universal phase: ordinary masked geometry is represented in the deferred/G-buffer phase, while at least fullbright masked geometry is handled later.

**Implication for SL-SHADERS:**
Later integration work must not equate all cutout/masked surfaces with the transparent forward-alpha phase; effect inputs may already contain ordinary alpha-mask surfaces at G-buffer completion.

### Deferred lighting follows G-buffer completion, then the renderer enters post-deferred geometry

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/llviewerdisplay.cpp`
- `display(...)`
- symbol: `gPipeline.renderDeferredLighting()`
- `indra/newview/pipeline.cpp`
- `LLPipeline::renderDeferredLighting()`

**Evidence:**
After `deferredScreen` is flushed, `display()` calls `renderDeferredLighting()` when deferred rendering is active. `renderDeferredLighting()` performs deferred sun/shadow/SSAO handling, atmospheric/full-screen lighting contribution, and local/projected lights into the scene/light targets. Near the end, it enters a block explicitly commented `render non-deferred geometry (alpha, fullbright, glow)`, masks the applicable render types, and calls `renderGeomPostDeferred(...)`.

**Implication for SL-SHADERS:**
This establishes a source-backed separation between G-buffer completion/deferred lighting and later forward/post-deferred geometry, which is a critical boundary for effects that require opaque-only versus composited scene inputs.

### Alpha-blended geometry is forward-rendered in post-deferred passes

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/lldrawpoolalpha.cpp`
- class `LLDrawPoolAlpha`
- methods: `getNumPostDeferredPasses()`, `renderPostDeferred(...)`, `forwardRender(...)`
- `indra/newview/pipeline.cpp`
- `LLPipeline::renderGeomPostDeferred(...)`

**Evidence:**
`LLDrawPoolAlpha` reports one post-deferred pass. Its source explicitly notes that transparency is forward rendering post deferred and that it does not need a G-buffer for that transparency pass. `renderPostDeferred()` prepares deferred-environment forward shaders, performs a rigged-depth pass where applicable, then calls `forwardRender()` for regular forward alpha rendering. `LLPipeline::renderGeomPostDeferred()` is explicitly described as rendering geometry required after the deferred pass, “stuff like alpha, water, etc.”

**Implication for SL-SHADERS:**
The source confirms that a G-buffer-complete interception point precedes blended transparency; later effects can reason separately about opaque/deferred data and final transparent composition.

### Water is a post-deferred pass bracketed by pre-water and post-water alpha pools

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/lldrawpool.h`
- `LLDrawPool` pool-order enum: `POOL_ALPHA_PRE_WATER`, `POOL_VOIDWATER`, `POOL_WATER`, `POOL_ALPHA_POST_WATER`
- `indra/newview/pipeline.cpp`
- `LLPipeline::renderGeomPostDeferred(...)`
- `indra/newview/lldrawpoolwater.cpp`
- class `LLDrawPoolWater`, methods `getNumPostDeferredPasses()`, `beginPostDeferredPass(...)`, `renderPostDeferred(...)`

**Evidence:**
The draw-pool enum explicitly controls render order and places pre-water alpha before void/water and post-water alpha after water. `renderGeomPostDeferred()` iterates these pool types in pool order and injects water exclusion/haze/atmospherics at defined thresholds. `LLDrawPoolWater` provides a post-deferred pass; for transparent water its `beginPostDeferredPass()` copies the scene color plus deferred depth into `mWaterDis` for water reflection/refraction sampling before `renderPostDeferred()` draws the water planes.

**Implication for SL-SHADERS:**
Water is not part of opaque G-buffer population. Any later effect integration that needs “before water,” “after water,” or final-alpha scene color has source-backed ordering points to investigate further.

### Post-processing occurs before HUD attachments and normal UI composition

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/llviewerdisplay.cpp`
- functions: `render_ui(...)`, `render_hud_attachments()`, `render_ui_3d()`, `render_ui_2d()`
- `indra/newview/pipeline.cpp`
- `LLPipeline::renderFinalize()`

**Evidence:**
At the end of the main scene, `display()` calls `render_ui()` (for non-snapshot frames). Despite the name, `render_ui()` first calls `gPipeline.renderFinalize()` under the comment `apply gamma correction and post effects`. `renderFinalize()` performs the final scene post chain, including HDR SSR copy/composition, luminance/exposure/tonemap (or legacy gamma correction), glow, optional DoF, FXAA/SMAA, Firestorm vignette/snapshot-frame effects, and then renders the final post-processed source buffer to the screen target. Only after `renderFinalize()` returns does `render_ui()` render the normal HUD elements, HUD attachments, 3D UI, 2D UI, and debug text. A few special helper/debug overlays (for example snapshot guides/focus-point/physics debug) are drawn inside `renderFinalize()` itself, so the boundary is specifically for the ordinary viewer HUD/UI composition.

**Implication for SL-SHADERS:**
The native frame separates scene post-processing from UI composition: normal UI/HUD composition is downstream of `renderFinalize()`, which matters when deciding whether an effect should include or exclude UI.

### Final frame presentation on Windows is UI-complete `swap()` -> Win32 `SwapBuffers(HDC)`

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/llviewerdisplay.cpp`
- `display(...)`, `swap()`
- `indra/llwindow/llwindowwin32.cpp`
- class `LLWindowWin32`, method `LLWindowWin32::swapBuffers()`

**Evidence:**
For the normal non-snapshot path, `display()` calls `render_ui()` and then `swap()`. `swap()` calls `gViewerWindow->getWindow()->swapBuffers()` when `gDisplaySwapBuffers` is set, then sets that flag true. On Windows/OpenGL, the virtual implementation is `LLWindowWin32::swapBuffers()`, which calls the Win32 OpenGL buffer-swap API `SwapBuffers(mhDC)`.

**Implication for SL-SHADERS:**
This establishes the authoritative platform presentation boundary and confirms that normal UI composition precedes the Windows OpenGL swap.

### Standard reflection-map manager update is adjacent to, but outside, the main-view `display()` composition

**Status:** SOURCE-PROVEN

**Source:**

- `indra/newview/llappviewer.cpp`
- `LLAppViewer::frame()`
- symbol: `gPipeline.mReflectionMapManager.update()`
- `indra/newview/llreflectionmapmanager.cpp`
- class `LLReflectionMapManager`; methods `update()`, `doProbeUpdate()`, `updateProbeFace(...)`

**Evidence:**
In `LLAppViewer::frame()`, after the `// Render scene.` block calls `display()`, the started-state block calls `gPipeline.mReflectionMapManager.update()` before snapshot-floater updates. Normal `display()` has already run UI and `swap()` by that point. `LLReflectionMapManager::update()` manages a dedicated probe render target and can call `doProbeUpdate()`; `updateProbeFace()` explicitly hot-swaps `gPipeline.mRT` to `gPipeline.mAuxillaryRT` for probe-face rendering. This source-proves that reflection-map probe rendering is separate render-target work adjacent to, but outside, the main-view color-composition sequence mapped above.

**Implication for SL-SHADERS:**
External interception must distinguish main-view rendering from reflection-probe/cubemap activity that can occur in the same application-frame iteration.

## Proposed Frame Order

```text
Windows app loop: viewer_app_ptr->frame()
  ↓
LLAppViewer::frame() — "Render scene"
  ↓
display(...)
  ↓
frame/world preparation
  ├─ dynamic render-to-texture updates (conditional)
  ├─ hero/mirror probe update + render (conditional, before rest of scene)
  ├─ main camera/environment/geometry update
  ├─ main-camera cull
  ├─ sun-shadow generation (normal non-snapshot path, after first frame)
  ├─ avatar impostor update
  ├─ image/material maintenance
  ├─ stateSort
  └─ sky update
  ↓
main `deferredScreen` bind + clear
  ↓
LLPipeline::renderGeomDeferred(...)
  ├─ opaque/deferred draw pools
  └─ ordinary alpha-mask/grass deferred passes
  ↓
`deferredScreen` flush  ← main G-buffer complete at high level
  ↓
LLPipeline::renderDeferredLighting()
  ├─ shadow/SSAO/direct-light work
  ├─ atmospheric/full-screen deferred contribution
  └─ local/projected deferred lights
  ↓
LLPipeline::renderGeomPostDeferred(...)
  ├─ post-deferred fullbright/glow/etc.
  ├─ alpha PRE water (forward)
  ├─ water / void water (post-deferred)
  └─ alpha POST water (forward)
  ↓
end of 3D scene render
  ↓
render_ui(...)
  ↓
LLPipeline::renderFinalize()
  ├─ SSR copy/composition when HDR path is enabled
  ├─ tonemap/gamma
  ├─ glow
  ├─ optional DoF
  ├─ optional FXAA/SMAA
  ├─ Firestorm post effects (e.g. vignette/snapshot frame)
  └─ final post source rendered to screen target
  ↓
HUD elements + HUD attachments
  ↓
3D UI
  ↓
2D UI + debug text
  ↓
swap()
  ↓
LLWindowWin32::swapBuffers()
  ↓
Win32 `SwapBuffers(mhDC)`

Adjacent after `display()` in LLAppViewer::frame():
  └─ mReflectionMapManager.update() [probe render-target work; not main-view composition]
```

Uncertain/conditional edges:

- The exact per-material ordering inside all deferred and post-deferred draw-pool categories is intentionally not expanded here.
- Ordinary alpha-mask is source-proven deferred; fullbright alpha-mask is source-proven post-deferred. A complete taxonomy of every material/PBR mask variant belongs in FS-ALPHA-001 or FS-GBUF-001.
- The exact contents, formats, lifetime, resize policy, and ownership of `deferredScreen` attachments are intentionally deferred to FS-GBUF-001.

## Open Questions

- FS-GBUF-001 — authoritative main-view G-buffer ownership, attachment semantics/formats, lifetime, and exact completion boundaries.
- FS-CAMERA-001 — main-view camera/projection/inverse-projection ownership and update timing.
- FS-ALPHA-001 — detailed alpha-mask/blend/material/PBR ordering, including pre-water/post-water and depth-write behavior.
- FS-POST-001 — exact post-processing resource ping-pong, SSR inputs/outputs, UI target ownership, and presentation-adjacent lifetimes.
- FS-PROBE-001 — distinguish standard reflection-map, hero/mirror probe, cube-snapshot, and main-view render invocations/resources.

## Recommended Next Agent Task

- Proposed task ID: **FS-GBUF-001**
- Exact bounded question: **What are the authoritative main-view `deferredScreen` G-buffer attachments (semantic, GL/internal format, producer, consumer, creation/resize site, and lifetime) at commit `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`?**
- Why highest-value dependency: FS-FRAME-001 now proves the G-buffer write and lighting boundaries, but SL-SHADERS still cannot reliably use that boundary without knowing which native attachments are authoritative and when they are valid. This is the narrowest next dependency for GTAO/SSR/HybridGI resource decisions without drifting into effect implementation.
- Likely starting files/symbols: `indra/newview/pipeline.cpp` (`LLPipeline::createGLBuffers`, `allocateScreenBuffer`, `bindDeferredShader`, `renderGeomDeferred`, `renderDeferredLighting`), `indra/newview/pipeline.h` render-target members, and the render-target implementation under `indra/llrender/`.

## Handoff Summary

- Firestorm `master` is pinned at `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294` for this audit.
- Windows runs `viewer_app_ptr->frame()`; `LLAppViewer::frame()` calls `display()` for the render scene.
- `display()` owns the normal main-view high-level sequence.
- Hero/mirror probes, sun shadows, and avatar impostors can render before the main G-buffer pass.
- Main G-buffer population is `deferredScreen` bind/clear -> `renderGeomDeferred()` -> flush.
- Ordinary alpha-mask geometry is deferred; fullbright alpha-mask has a post-deferred path.
- `renderDeferredLighting()` follows G-buffer completion, then invokes post-deferred geometry.
- Blended alpha is forward/post-deferred; pool order brackets water with pre/post-water alpha.
- Water is post-deferred and samples copied scene/deferred depth for reflection/refraction.
- `render_ui()` first runs `renderFinalize()` post-processing, then HUD/3D UI/2D UI.
- Normal presentation is `swap()` -> `LLWindowWin32::swapBuffers()` -> Win32 `SwapBuffers(mhDC)`.
- Standard reflection-map manager updates after `display()` in the app-frame loop, outside main-view composition.
- Exact G-buffer attachment ownership/formats/lifetimes remain intentionally unresolved.
- Next task: FS-GBUF-001.
