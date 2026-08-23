# FS-GBUF-001

## Question

What are the authoritative main-view Firestorm G-buffer resources and their ownership/lifetime semantics?

## Repository State

- Repository: `https://github.com/FirestormViewer/phoenix-firestorm`
- Branch: `master`
- Commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`
- Platform: Windows / OpenGL
- Accepted prior evidence: `FS-FRAME-001.md` establishes the normal main-view sequence `deferredScreen.bindTarget()` -> clear -> `renderGeomDeferred()` -> `deferredScreen.flush()` -> `renderDeferredLighting()`.
- This audit is source analysis only. It does not claim runtime capture/profiling proof.

## Attachment Map

```text
LLPipeline::mMainRT.deferredScreen
(main-view object; normal path reaches it through mRT == &mMainRT)
│
├── GL_COLOR_ATTACHMENT0 / LLRenderTarget::mTex[0]
│   ├── semantic: GBufferInfo.albedo / deferred diffuse-base-color-side payload
│   ├── requested internal-format token: GL_RGBA
│   ├── producer: deferred geometry MRT shaders
│   └── consumers: deferred lighting; buffer visualization/debug consumers
│
├── GL_COLOR_ATTACHMENT1 / LLRenderTarget::mTex[1]
│   ├── semantic: GBufferInfo.specular
│   │             legacy = specular RGB + glossiness/exponent A
│   │             PBR    = packed occlusion/roughness/metal RGB
│   ├── requested internal-format token: GL_RGBA
│   ├── producer: deferred geometry MRT shaders
│   └── consumers: deferred lighting; buffer visualization/debug consumers
│
├── GL_COLOR_ATTACHMENT2 / LLRenderTarget::mTex[2]
│   ├── semantic: encoded normal + G-buffer metadata
│   │             decoded as normal; raw B = envIntensity; raw A = gbufferFlag
│   ├── requested internal-format token: GL_RGBA16 when HDR-capable branch is active
│   │                                    GL_RGB10_A2 otherwise
│   ├── producer: deferred geometry MRT shaders
│   └── consumers: deferred lighting; luminance/environment-mask path; visualization
│
├── GL_COLOR_ATTACHMENT3 / LLRenderTarget::mTex[3]  [conditional]
│   ├── semantic: optional auxiliary emissive payload, exposed as GBufferInfo.emissive
│   ├── requested internal-format token: GL_RGB16F when HDR-capable branch is active
│   │                                    GL_RGB otherwise
│   ├── producer: deferred shaders compiled with HAS_EMISSIVE that write frag_data[3]
│   └── consumers: deferred lighting; buffer visualization/debug consumers
│
└── GL_DEPTH_ATTACHMENT / LLRenderTarget::mDepth
    ├── semantic: native main deferred depth, then shared/evolving main-scene depth
    ├── requested internal-format token: GL_DEPTH_COMPONENT24
    ├── producer: deferred geometry depth writes; later shared-depth writers can update it
    └── consumers: deferred lighting and later native depth-dependent scene/post paths
```

Attachment 3 is present only when `RenderEnableEmissiveBuffer` causes `addDeferredAttachments()` to append it. The normal/emissive format branch uses `RenderHDREnabled && (gGLManager.mGLVersion > 4.05f)`. For `GL_RGBA` and `GL_RGB`, this document records the exact internal-format token Firestorm requests; it does not infer a driver-resolved sized internal format.

### Per-attachment ownership/lifetime summary

| Attachment | Firestorm C++ owner / member | Allocation and FBO attachment | Resize/reallocation | Destruction | Becomes authoritative | Ceases to be valid as this frame's G-buffer payload |
|---|---|---|---|---|---|---|
| Color 0 | `LLPipeline::mMainRT.deferredScreen`; backing `LLRenderTarget::mTex[0]` | `LLPipeline::allocateScreenBufferInternal()` -> `deferredScreen.allocate(..., GL_RGBA, true)` -> `LLRenderTarget::addColorAttachment()` -> `GL_COLOR_ATTACHMENT0` | Main screen resize/recreation calls `releaseScreenBuffers()` then `allocateScreenBuffer()`; allocation failure can release and retry at lower resolution | `releaseScreenBuffers()` -> `LLRenderTarget::release()`; destructor also calls `release()` | After the main-view `renderGeomDeferred()` completes and `deferredScreen.flush()` returns | Hard invalidators are the next main-view clear/repopulation or earlier explicit release/reallocation. No later normal main-view color rewrite was identified in this bounded trace; see Finding 9 (`LIKELY`). |
| Color 1 | same object; `mTex[1]` | `addDeferredAttachments()` -> `addColorAttachment(GL_RGBA)` -> `GL_COLOR_ATTACHMENT1` | same as Color 0 | same as Color 0 | same G-buffer completion boundary | same as Color 0 |
| Color 2 | same object; `mTex[2]` | `addDeferredAttachments()` -> `addColorAttachment(GL_RGBA16 or GL_RGB10_A2)` -> `GL_COLOR_ATTACHMENT2` | same as Color 0 | same as Color 0 | same G-buffer completion boundary | same as Color 0 |
| Color 3, conditional | same object; `mTex[3]` | `addDeferredAttachments()` conditionally -> `addColorAttachment(GL_RGB16F or GL_RGB)` -> `GL_COLOR_ATTACHMENT3` | toggling emissive/HDR recreates GL buffers and shaders; ordinary resize follows same release/reallocate path | same as Color 0 | same G-buffer completion boundary, when the attachment exists | same as Color 0; the attachment itself ceases to exist across a recreation with emissive buffer disabled |
| Depth | same object; `LLRenderTarget::mDepth`; also attached to `mMainRT.screen` by sharing | `deferredScreen.allocate(..., depth=true)` -> `allocateDepth()` -> `GL_DEPTH_ATTACHMENT`; then `deferredScreen.shareDepthBuffer(screen)` attaches the same texture to `screen` | same release/reallocate family as the color attachments | owned/deleted by `deferredScreen.release()`; `screen.release()` only detaches the shared depth | At the same deferred flush it is authoritative as the completed deferred-geometry depth | Its interpretation as a frozen deferred/G-buffer depth snapshot is not guaranteed once later depth-writing work begins on the shared `screen` FBO. The exact earliest conditional post-deferred writer is intentionally `UNRESOLVED`; as an evolving native scene-depth resource it remains valid until next clear/repopulation or release. |

## Ownership and Lifetime

```text
static LLPipeline gPipeline
   ↓
LLPipeline::mMainRT
   ↓
RenderTargetPack::deferredScreen  (LLRenderTarget value member)
   ↓
LLPipeline::init(): mRT = &mMainRT
   ↓
initial/recreated GL-buffer path
LLPipeline::createGLBuffers() / allocateScreenBuffer(...)
   ↓
LLPipeline::allocateScreenBufferInternal(resX,resY)
   ↓
deferredScreen.allocate(resX,resY,GL_RGBA,true)
   ├─ LLRenderTarget::release() when reconfiguration requires new storage
   ├─ allocateDepth() -> GL_DEPTH_COMPONENT24 -> GL_DEPTH_ATTACHMENT
   ├─ addColorAttachment(GL_RGBA) -> GL_COLOR_ATTACHMENT0
   └─ FBO creation
   ↓
addDeferredAttachments(deferredScreen)
   ├─ GL_COLOR_ATTACHMENT1: GL_RGBA
   ├─ GL_COLOR_ATTACHMENT2: GL_RGBA16 or GL_RGB10_A2
   └─ GL_COLOR_ATTACHMENT3: optional GL_RGB16F or GL_RGB
   ↓
deferredScreen.shareDepthBuffer(screen)
   └─ same depth texture also becomes mMainRT.screen's GL_DEPTH_ATTACHMENT
   ↓
normal main-view binding
   ↓
deferredScreen.bindTarget() -> clear()
   ↓
LLPipeline::renderGeomDeferred(...)
   ↓
deferredScreen.flush()
   └─ completed deferred G-buffer is authoritative here
   ↓
LLPipeline::renderDeferredLighting()
   ├─ samples G-buffer color/depth
   └─ renders later scene work to mMainRT.screen using shared depth
   ↓
post-deferred/depth-dependent work
   ├─ colors remain the completed deferred payload in the bounded normal path
   └─ shared depth can be written again; it is no longer guaranteed to be a frozen opaque/deferred snapshot
   ↓
remainder of frame / presentation
   ↓
next main-view clear+population
   └─ previous frame payload loses logical validity

Alternative lifetime terminators before reuse:
   resize/requested recreation -> releaseScreenBuffers() -> allocateScreenBuffer(...)
   graphics setting recreation -> releaseGLBuffers() -> createGLBuffers()
   GL teardown/destruction -> releaseScreenBuffers()/LLRenderTarget::release()/~LLRenderTarget()
```

## Findings

### Finding 1 — The authoritative main-view object is `LLPipeline::mMainRT.deferredScreen`, not an arbitrary current `mRT->deferredScreen`

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.h`
- Class: `LLPipeline`
- Symbols: nested `RenderTargetPack`; `mMainRT`; `mAuxillaryRT`; `mHeroProbeRT`; `mRT`
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method/symbol: `LLPipeline::init()`; assignments to `mRT`

**What the source proves:** `RenderTargetPack` owns `screen`, `deferredScreen`, and `deferredLight`. `mMainRT` is explicitly the main full-resolution pack; auxiliary and hero-probe packs are separate objects. `LLPipeline::init()` points `mRT` at `mMainRT`, but other source paths temporarily point `mRT` at auxiliary/hero targets and restore it. Therefore the stable architectural identity of the main G-buffer is `mMainRT.deferredScreen`; `mRT->deferredScreen` is only main-view while `mRT == &mMainRT`.

**SL-SHADERS heuristic affected:** YES — replaces identifying the main-view target by dimensions or by assuming every `deferredScreen` reached through the current render-target pointer is the visible-camera target.

### Finding 2 — `deferredScreen` allocation creates color 0 plus owned depth, then appends the deferred MRT data attachments

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method/symbol: `LLPipeline::allocateScreenBufferInternal(U32,U32)`; `addDeferredAttachments(LLRenderTarget&, bool)`
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Methods: `allocate()`, `addColorAttachment()`, `allocateDepth()`

**What the source proves:** Firestorm calls `mRT->deferredScreen.allocate(resX,resY,GL_RGBA,true)` and then `addDeferredAttachments(mRT->deferredScreen)`. `LLRenderTarget::allocate()` owns the first color attachment and requested depth; additional attachments are appended afterward.

**SL-SHADERS heuristic affected:** YES — replaces guessing attachment count/order from observed GL object creation.

### Finding 3 — FBO attachment indices are deterministic and source-defined

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Methods: `allocate()`, `addColorAttachment()`, `bindTarget()`

**What the source proves:** `addColorAttachment()` uses `mTex.size()` as the next attachment offset and calls `glFramebufferTexture2D(..., GL_COLOR_ATTACHMENT0 + offset, ...)`. `bindTarget()` enables draw buffers `GL_COLOR_ATTACHMENT0` through `3` according to `mTex.size()`. `allocate()` attaches owned depth at `GL_DEPTH_ATTACHMENT`.

**SL-SHADERS heuristic affected:** YES — replaces inference from MRT draw-buffer state or texture creation order.

### Finding 4 — Firestorm requests exact per-attachment format tokens in `addDeferredAttachments()`

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline` / file-scope helper
- Symbol: `addDeferredAttachments(LLRenderTarget&, bool)`
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Method: `addColorAttachment(U32)`

**What the source proves:** Color 0 is requested as `GL_RGBA`; color 1 as `GL_RGBA`; color 2 as `GL_RGBA16` in the HDR-capable branch and `GL_RGB10_A2` otherwise; color 3, if present, as `GL_RGB16F` in the HDR-capable branch and `GL_RGB` otherwise. `LLRenderTarget` passes those tokens to `LLImageGL::setManualImage()` and stores them in `mInternalFormat`. This is source proof of Firestorm's requested internal-format tokens, not runtime proof of a driver's resolved sized format for unsized tokens.

**SL-SHADERS heuristic affected:** YES — replaces format guessing from texture dimensions, sampling behavior, or interception-time metadata heuristics.

### Finding 5 — The native depth texture is requested as `GL_DEPTH_COMPONENT24`

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Methods: `allocate()`, `allocateDepth()`
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method: `bindDeferredShader()`

**What the source proves:** `allocateDepth()` creates `mDepth` using `GL_DEPTH_COMPONENT24`, `GL_DEPTH_COMPONENT`, `GL_UNSIGNED_INT`; `allocate()` attaches it to `GL_DEPTH_ATTACHMENT`. `bindDeferredShader()` binds the deferred target itself as the `DEFERRED_DEPTH` source when no override depth target is supplied.

**SL-SHADERS heuristic affected:** YES — replaces guessing which same-sized texture is native depth and guessing its requested depth format.

### Finding 6 — C++ shader binding maps texture indices 0/1/2/3 to diffuse/specular/normal/emissive inputs

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method: `bindDeferredShader(LLGLSLShader&, LLRenderTarget*, LLRenderTarget*)`

**What the source proves:** `bindDeferredShader()` binds `deferredScreen` texture index 0 to `LLShaderMgr::DEFERRED_DIFFUSE`, index 1 to `DEFERRED_SPECULAR`, index 2 to `NORMAL_MAP`, and index 3 to `DEFERRED_EMISSIVE`; the source comments identify these as `frag_data[0..3]` respectively.

**SL-SHADERS heuristic affected:** YES — replaces semantic attachment identification based on visual inspection or trial sampling.

### Finding 7 — Shader source defines the payload semantics, including the PBR/legacy multiplexing

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/app_settings/shaders/class1/deferred/pbropaqueF.glsl`
- Shader/symbol: deferred opaque PBR `main()`; `frag_data[0..3]`
- Path: `indra/newview/app_settings/shaders/class3/deferred/materialF.glsl`
- Shader/symbol: deferred non-blend branch of `main()`; `frag_data[0..3]`
- Path: `indra/newview/app_settings/shaders/class1/deferred/gbufferUtil.glsl`
- Shader/symbol: `GBufferInfo getGBuffer(vec2)`

**What the source proves:** PBR writes base/diffuse color to 0, packed occlusion/roughness/metal to 1, encoded normal plus PBR flag metadata to 2, and optional emissive to 3. The examined legacy material deferred path writes diffuse RGB plus emissive/fullbright factor in attachment-0 alpha, specular RGB plus glossiness/exponent in attachment 1, and encoded normal with environment intensity and G-buffer flags in attachment 2. `getGBuffer()` exposes these as `albedo`, `specular`, decoded `normal`, `envIntensity`, `gbufferFlag`, and optional `emissive`.

**SL-SHADERS heuristic affected:** YES — replaces assumptions that attachment 1 is always “specular” in one fixed model or that attachment 2 is only a plain normal texture.

### Finding 8 — Attachment 3 is conditional, and Firestorm couples its existence to shader compilation

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Symbol: `addDeferredAttachments()`; setting `RenderEnableEmissiveBuffer`
- Path: `indra/newview/llviewershadermgr.cpp`
- Class: `LLViewerShaderMgr`
- Symbol: `add_common_permutations(LLGLSLShader*)`; permutation `HAS_EMISSIVE`
- Path: `indra/newview/llviewercontrol.cpp`
- Symbols: `handleEnableEmissiveChanged()`, `setting_setup_signal_listener(... "RenderEnableEmissiveBuffer" ...)`

**What the source proves:** The same `RenderEnableEmissiveBuffer` setting that conditionally appends color attachment 3 also adds the `HAS_EMISSIVE` shader permutation. Its registered setting callback recreates GL buffers and reloads shaders. Attachment 3 is therefore an explicit configuration-dependent part of the main G-buffer topology, not a permanently present texture whose contents can merely be ignored.

**SL-SHADERS heuristic affected:** YES — replaces assuming a fixed four-color-attachment G-buffer across graphics-setting changes.

### Finding 9 — The principal producers are the draw pools dispatched inside `LLPipeline::renderGeomDeferred()`

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method: `renderGeomDeferred(LLCamera&, bool)`
- Path: `indra/newview/lldrawpoolsimple.cpp`
- Classes/methods: `LLDrawPoolSimple::renderDeferred()`, `LLDrawPoolAlphaMask::renderDeferred()`, `LLDrawPoolGrass::renderDeferred()`
- Path: `indra/newview/lldrawpoolmaterials.cpp`
- Class/methods: `LLDrawPoolMaterials::beginDeferredPass()`, `renderDeferred()`
- Path: `indra/newview/lldrawpoolpbropaque.cpp`
- Class/method: `LLDrawPoolGLTFPBR::renderDeferred()`
- Path: `indra/newview/lldrawpoolterrain.cpp`
- Class/methods: `LLDrawPoolTerrain::renderDeferred()`, `renderFullShader()`

**What the source proves:** `renderGeomDeferred()` iterates each draw pool's deferred passes. Source-confirmed producers include simple opaque, ordinary alpha-mask, grass, legacy material variants, GLTF/PBR opaque/masked work, and terrain through deferred shader programs. This audit intentionally does not expand detailed alpha ordering beyond identifying source-proven deferred producers.

**SL-SHADERS heuristic affected:** NO — this establishes producer provenance; attachment identity is already replaced by stronger ownership/binding evidence above.

### Finding 10 — Deferred lighting is a direct native consumer of all semantic G-buffer inputs and depth

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Methods: `renderDeferredLighting()`, `bindDeferredShader()`
- Path: `indra/newview/app_settings/shaders/class3/deferred/softenLightF.glsl`
- Shader/symbol: `main()`
- Path: `indra/newview/app_settings/shaders/class1/deferred/gbufferUtil.glsl`
- Shader/symbol: `getGBuffer()`

**What the source proves:** Deferred-lighting passes use `bindDeferredShader()`. `softenLightF.glsl` obtains native depth and a `GBufferInfo`, then consumes albedo, specular/ORM, decoded normal, environment intensity, G-buffer flags, and emissive. This proves the mapped attachments are the renderer's actual deferred-lighting inputs, not merely conveniently named textures.

**SL-SHADERS heuristic affected:** YES — replaces validation-by-correlation such as “the texture that changes with surface orientation is probably normals.”

### Finding 11 — Attachment 2 has an additional source-proven environment-mask consumer

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method/symbol: luminance-generation path using `gLuminanceProgram`; `mRT->deferredScreen.bindTexture(2, ...)`

**What the source proves:** Firestorm explicitly binds `deferredScreen` texture 2 to the luminance shader's normal-map input with the source comment that it is bound “to get the environment mask.” This independently corroborates that attachment 2 carries more than a plain decoded normal image.

**SL-SHADERS heuristic affected:** YES — replaces treating the native normal attachment as semantically normal-only.

### Finding 12 — The completed G-buffer becomes authoritative at the main-view `deferredScreen.flush()` after `renderGeomDeferred()`

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/llviewerdisplay.cpp`
- Function: global `display(...)`
- Symbols: `mRT->deferredScreen.bindTarget()`, `.clear()`, `renderGeomDeferred()`, `.flush()`, `renderDeferredLighting()`
- Accepted prior evidence: `FS-FRAME-001.md`

**What the source proves:** In the normal main-view sequence, Firestorm clears the bound deferred target, runs deferred geometry, flushes `deferredScreen`, and only then enters deferred lighting. The post-`renderGeomDeferred()` flush is the source-backed completion boundary for the current frame's G-buffer.

**SL-SHADERS heuristic affected:** YES — replaces timing heuristics based on draw counts, FBO dimensions, or detecting a later full-screen lighting pass.

### Finding 13 — The color attachments' hard invalidation/recreation boundaries are source-proven; their exact no-write interval after flush is `LIKELY`

**Confidence:** LIKELY

**Source:**
- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display(...)`
- Symbols: per-frame `deferredScreen.clear()` before `renderGeomDeferred()`
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Methods: `releaseScreenBuffers()`, `resizeScreenTexture()`, `releaseGLBuffers()`
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Method: `release()`

**What the source proves / supports:** The next main G-buffer population begins by clearing `deferredScreen`; release/reallocation destroys the backing color textures outright. The bounded normal main-view trace identifies downstream reads of the color G-buffer and no later normal main-view bind intended to repopulate those color attachments after the deferred flush. Therefore it is **LIKELY** that the completed color payload remains unchanged through the remainder of that normal frame and ceases to be the current frame's payload at the next clear, unless explicit buffer recreation occurs first. This is not runtime proof and is deliberately weaker than the hard clear/release boundaries.

**SL-SHADERS heuristic affected:** YES — can replace assuming that native G-buffer color names/contents remain valid indefinitely after first discovery; consumers should key validity to frame population and recreation boundaries.

### Finding 14 — `mMainRT.screen` shares the exact `deferredScreen` depth texture

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method: `allocateScreenBufferInternal(U32,U32)`
- Symbol: `mRT->deferredScreen.shareDepthBuffer(mRT->screen)`
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Method: `shareDepthBuffer(LLRenderTarget&)`

**What the source proves:** After allocating both render targets, Firestorm attaches `deferredScreen`'s `mDepth` texture to `screen`'s `GL_DEPTH_ATTACHMENT`. `screen` marks the depth as shared and does not own a second copy. The native depth object at G-buffer completion is therefore also the later main scene-depth attachment.

**SL-SHADERS heuristic affected:** YES — replaces the assumption that the deferred depth texture is a private immutable G-buffer-only resource.

### Finding 15 — The G-buffer-depth snapshot is not guaranteed frozen after deferred completion

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method: `renderDeferredLighting()` / its call to `renderGeomPostDeferred(...)` while the main `screen` target is active
- Path: `indra/newview/lldrawpoolalpha.cpp`
- Class: `LLDrawPoolAlpha`
- Methods: `renderPostDeferred(S32)`, `forwardRender(bool)`

**What the source proves:** The main `screen` target uses the shared depth from Finding 14 during post-deferred geometry. `LLDrawPoolAlpha::renderPostDeferred()` includes a first `forwardRender(true)` pass described by source as rendering rigged objects to the depth buffer; `forwardRender(bool)` enables depth writes for that rigged pass. Thus Firestorm has post-deferred paths that can write the same GL depth texture after G-buffer completion. The audit does **not** claim every frame changes a pixel, and it does not chase detailed alpha ordering. The exact first possible post-deferred writer in all configurations is therefore `UNRESOLVED` by scope.

**SL-SHADERS heuristic affected:** YES — replaces treating “native deferred depth” as a frozen opaque-depth snapshot for the entire rest of the frame.

### Finding 16 — The exact earliest post-deferred writer of shared depth is unresolved by this task's scope

**Confidence:** UNRESOLVED

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method: `renderGeomPostDeferred(LLCamera&)`
- Path: `indra/newview/lldrawpoolalpha.cpp`
- Class: `LLDrawPoolAlpha`
- Methods: `renderPostDeferred(S32)`, `forwardRender(bool)`

**What the source proves / does not prove:** Finding 15 proves at least one later depth-write-capable path. Determining whether another post-deferred pool can write the shared depth earlier requires a complete post-deferred depth-writer ordering audit. That would cross into the detailed alpha/order work explicitly excluded from `FS-GBUF-001`. Therefore the strict earliest loss of the *frozen deferred-depth snapshot* is left unresolved rather than inferred. The hard end of resource validity remains next clear/repopulation or release/reallocation.

**SL-SHADERS heuristic affected:** YES — the unresolved external assumption is the exact interception point after which native depth can no longer be treated as opaque/deferred-only depth.

### Finding 17 — Screen resize uses release-and-reallocate, not `LLRenderTarget::resize()`

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Methods: `requestResizeScreenTexture()`, `resizeScreenTexture()`, `releaseScreenBuffers()`, `allocateScreenBuffer()`, `doAllocateScreenBuffer()`, `allocateScreenBufferInternal()`
- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display(...)`
- Path: `indra/llrender/llrendertarget.h`
- Class: `LLRenderTarget`
- Symbols: `resize()`, its screen-space warning comment

**What the source proves:** A resize request sets `gResizeScreenTexture`. `display()` services it before normal main rendering. `resizeScreenTexture()` compares the effective scaled resolution and, when recreation is required, calls `releaseScreenBuffers()` and then `allocateScreenBuffer()`. Allocation failure can release partial state and retry smaller resolutions. Firestorm's own `LLRenderTarget::resize()` comment says not to use that method for screen-space buffers, and this main path does not use it.

**SL-SHADERS heuristic affected:** YES — replaces assumptions that a main-view texture object is resized in place and retains its GL name across viewport/render-resolution changes.

### Finding 18 — Emissive/HDR setting changes are explicit resource-recreation boundaries

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/newview/llviewercontrol.cpp`
- Symbols: `handleReleaseGLBufferChanged()`, `handleEnableEmissiveChanged()`, `handleEnableHDR()`, `setting_setup_signal_listener(...)`
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Methods: `releaseGLBuffers()`, `createGLBuffers()`
- Path: `indra/newview/llviewershadermgr.cpp`
- Class: `LLViewerShaderMgr`
- Symbol: `add_common_permutations()`

**What the source proves:** `RenderEnableEmissiveBuffer` is registered to `handleEnableEmissiveChanged()`, which recreates GL buffers and reloads shaders. `RenderHDREnabled` is registered to `handleEnableHDR()`, which likewise recreates GL buffers and shaders. These changes can alter attachment count or requested formats and therefore terminate the prior attachment identities/lifetimes.

**SL-SHADERS heuristic affected:** YES — replaces assuming resource topology and GL names survive graphics-feature toggles.

### Finding 19 — `LLRenderTarget` owns the GL lifetime; release and destruction delete the attachments/FBO

**Confidence:** SOURCE-PROVEN

**Source:**
- Path: `indra/llrender/llrendertarget.h`
- Class: `LLRenderTarget`
- Members: `mTex`, `mInternalFormat`, `mFBO`, `mDepth`, `mUseDepth`
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Methods: `~LLRenderTarget()`, `release()`
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Method: `releaseScreenBuffers()`; GL-buffer teardown path through `releaseGLBuffers()`

**What the source proves:** `release()` deletes the owned depth texture, all owned color textures, and the FBO and clears bookkeeping. `~LLRenderTarget()` calls `release()`. `releaseScreenBuffers()` releases `screen`, `deferredScreen`, and `deferredLight` for the active/main-related packs, and the pipeline GL-buffer teardown uses this release family. Native GL names are lifetime-local handles, not durable semantic identifiers.

**SL-SHADERS heuristic affected:** YES — replaces assuming a texture ID discovered once remains the same across renderer teardown/context/resource recreation.

## Implications for SL-SHADERS

This audit supplies authoritative source facts that could eventually replace these categories of external runtime inference, without prescribing an implementation:

- guessing which attachment is native main-view depth;
- guessing which attachment contains native normals;
- guessing specular versus PBR ORM semantics from sampled appearance;
- identifying the main-view G-buffer only by dimensions;
- confusing `mMainRT` resources with auxiliary/hero-probe render-target packs that use the same member names;
- assuming a fixed attachment count when the emissive buffer is configuration-dependent;
- assuming texture/FBO object names survive resize, HDR/emissive toggles, graphics-buffer recreation, or teardown;
- assuming deferred depth is frozen after the G-buffer flush, despite Firestorm sharing it with the later `screen` FBO;
- guessing the G-buffer-complete moment from interception behavior rather than the source-defined deferred-target flush.

The source does **not** provide runtime proof that an external interceptor has correctly matched these C++ objects to observed GL handles in a particular execution. That bridge remains a separate integration concern.

## Open Questions

- **FS-GBUF-DEPTH-002** — What is the exact earliest post-deferred main-view pass that can write the shared `mMainRT.deferredScreen` / `mMainRT.screen` depth texture under each relevant rendering configuration? This requires a deliberately bounded depth-writer ordering audit and is not pursued here because detailed alpha ordering is excluded.
- **FS-GBUF-EMISSIVE-002** — Which non-PBR deferred shader families, if any, write meaningful data to optional attachment 3? The C++ allocation comment mentions “material env intensity”, while the examined legacy material path stores environment intensity in attachment-2 metadata and writes zero to attachment 3.
- **FS-POST-001** — What are the authoritative main-view scene-color/post targets and their ownership/ping-pong validity from deferred-lighting completion through final scene presentation before ordinary HUD/UI composition?

## Recommended Next Agent Task

- **Task ID:** `FS-POST-001`
- **Exact bounded question:** What are the authoritative main-view `mMainRT.screen` and post-process render-target resources, ownership, formats, producer/consumer transitions, and validity boundaries from the end of `LLPipeline::renderDeferredLighting()` through `LLPipeline::renderFinalize()`, excluding detailed SSR/GTAO/HybridGI implementation?
- **Why this is now the highest-value dependency:** `FS-GBUF-001` identifies the native inputs and shows that depth continues as shared scene depth, but an external integration still needs a source-authoritative scene-color lineage after deferred lighting/post-deferred composition. That is the next resource boundary needed to distinguish G-buffer inputs from lit/composited scene outputs without relying on dimensions or FBO timing heuristics.
- **Likely starting files/classes/symbols:** `indra/newview/pipeline.h` (`RenderTargetPack`, post-process render-target members); `indra/newview/pipeline.cpp` (`LLPipeline::renderDeferredLighting()`, `renderFinalize()`, `copyRenderTarget()`, tonemap/AA/post target transitions); `indra/newview/llviewerdisplay.cpp` (`render_ui()` boundary); `indra/llrender/llrendertarget.*`.

## Handoff Summary

- Pinned source: Firestorm `master` at `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`, Windows/OpenGL scope.
- Main G-buffer object is `LLPipeline::mMainRT.deferredScreen`; `mRT` itself can point at non-main packs.
- Color 0: `GL_COLOR_ATTACHMENT0`, requested `GL_RGBA`, albedo/diffuse-side payload.
- Color 1: `GL_COLOR_ATTACHMENT1`, requested `GL_RGBA`, legacy specular+gloss or PBR ORM.
- Color 2: `GL_COLOR_ATTACHMENT2`, `GL_RGBA16` HDR-capable else `GL_RGB10_A2`, encoded normal+metadata.
- Color 3: conditional `GL_COLOR_ATTACHMENT3`, `GL_RGB16F` HDR-capable else `GL_RGB`, optional emissive payload.
- Depth: `GL_DEPTH_ATTACHMENT`, requested `GL_DEPTH_COMPONENT24`.
- G-buffer becomes authoritative after main `renderGeomDeferred()` and `deferredScreen.flush()`.
- Deferred lighting directly consumes the mapped G-buffer and depth.
- `mMainRT.screen` shares the exact `deferredScreen` depth texture.
- Later post-deferred work can write that shared depth; exact earliest writer is intentionally unresolved.
- Main screen resize and relevant setting changes release/recreate these resources; GL names are not stable.
- `LLRenderTarget::release()` / destruction deletes the owned textures and FBO.
- Remaining semantic question: optional attachment-3 non-PBR writers.
- Next task: `FS-POST-001` — authoritative main-view scene-color/post resource lineage.
