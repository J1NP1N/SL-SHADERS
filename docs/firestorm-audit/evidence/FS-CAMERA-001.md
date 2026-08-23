# FS-CAMERA-001

## Question

What camera, matrix, viewport, and depth-space state does Firestorm use for a normal main-view Windows/OpenGL frame, and how does that state move from application ownership to rendering/shader consumption?

## Repository State

- Repository: `https://github.com/FirestormViewer/phoenix-firestorm`
- Branch: `master`
- Commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`
- Platform: Windows
- Renderer: OpenGL
- Render scope: normal visible-camera main-view frame
- Accepted prior evidence: `FS-FRAME-001.md`, `FS-GBUF-001.md`, `FS-POST-001.md`
- Audit type: source analysis only; no runtime capture or experimentation is claimed.

The pinned commit was retrievable directly through the repository source interface. No revision substitution was required.

Status vocabulary used below:

- `SOURCE-PROVEN` — the implementation directly establishes the stated relationship.
- `LIKELY` — the examined implementation strongly supports the statement, but a requested identity or boundary is not completely closed in this bounded trace.
- `UNRESOLVED` — the requested detail was not source-proven within this audit.

## Executive State Map

```text
application / behavioral camera state
LLAgentCamera gAgentCamera
  - global camera/focus targets and smoothing
  - camera mode / zoom behavior
  - mDrawDistance
        |
        | LLAgentCamera::updateCamera()
        | global -> agent-space conversion
        v
render-facing viewer camera
LLViewerCamera singleton : LLCamera : LLCoordFrame
  - agent-space origin + at/left/up basis
  - vertical FOV, aspect, near, camera/culling far
  - frustum planes
        |
        | display_update_camera()
        | LLViewerWindow::setup3DRender()
        | LLViewerCamera::setPerspective(...)
        |
        +------------------------------+
        |                              |
        | culling/frustum far          | active render projection far
        | = LLViewerCamera::getFar()   | = MAX_FAR_CLIP * 2 (normal main view)
        |                              |
        v                              v
main cull state                  active renderer matrix state
LLPipeline::updateCull()         thread_local LLRender gGL
                                 - MM_MODELVIEW stack
                                 - MM_PROJECTION stack
                                 - current matrix hashes
                                      |
                                      +--> gGLModelView / gGLProjection
                                      |
                                      | LLRender::syncMatrices()
                                      v
                                 shader-visible matrices
                                 modelview_matrix
                                 projection_matrix
                                 inv_modelview
                                 inv_proj
                                 normal_matrix
                                 modelview_projection_matrix

main render-target binding is a separate state axis:

mWorldViewRectRaw / gGLViewport
  = raw main-world window viewport
        |
        | deferredScreen.bindTarget()
        v
OpenGL viewport = (0, 0, deferred RT width, deferred RT height)
  - RT dimensions may be resolution-scaled
  - gGLViewport is not rewritten by LLRenderTarget::bindTarget()
        |
        | LLRenderTarget::flush()
        v
restore previous RT, or raw gGLViewport for default framebuffer

main deferred depth path:

mMainRT.deferredScreen.mDepth (accepted prior evidence: GL_DEPTH_COMPONENT24)
        |
        | shader samples depthMap
        v
sampled depth d -> NDC z = 2*d - 1
        |
        | inv_proj
        v
eye/view-space position reconstruction

main-view temporal side path:

get_last_modelview() + get_current_modelview()
        |
        | LLPipeline::updateCull(main LLViewerCamera)
        v
gGLDeltaModelView / gGLInverseDeltaModelView
        |
        | LLPipeline::bindDeferredShader()
        v
modelview_delta / inv_modelview_delta

Temporal caveat: the delta calculation and upload are source-proven, but this audit does not
close the writer identity that makes the global "last" model-view slot the immediately previous
visible main-view frame; shadow code temporarily reuses and restores the same global slots.
```

## Camera State Inventory

| Object / owner | Purpose | Position / origin | Orientation | FOV | Aspect | Near / far | Update point | Main-view relevance | Configuration / conditional behavior | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|
| `gAgentCamera` / `LLAgentCamera` | Application/behavioral camera controller: camera mode, focus, smoothing, FOV zoom, draw distance | Holds global and agent-space camera/focus-related state; `updateCamera()` converts computed global camera/focus positions to agent space before updating `LLViewerCamera` | Owns behavioral up vector and camera-mode/preset/roll state used to derive the render camera | Owns FOV zoom factors; writes effective viewer-camera FOV | Does not own the final render aspect field | `mDrawDistance` is the configured/behavioral draw distance; initializes viewer-camera far | `LLAppViewer::idle()` -> `gAgentCamera.updateCamera()` once per frame | Direct producer of the normal visible viewer-camera transform and FOV | Camera mode, smoothing, focus/zoom, RLVa and other viewer behavior can alter computed position/FOV | `SOURCE-PROVEN` |
| `LLViewerCamera` singleton | Render-facing viewer camera and frustum object | Inherited `LLCoordFrame::mOrigin`; `updateCameraLocation()` sets agent-space origin | Inherited basis axes; `updateCameraLocation()` constructs normalized at/left/up and calls `setAxes()` | Inherited `LLCamera::mView`; `LLAgentCamera::updateCamera()` sets it from default FOV divided by current FOV zoom factor | Inherited `mAspect`; kept from raw main-world viewport width/height | Inherited `mNearPlane` and `mFarPlane`; initialized to near `0.1f` and far `mDrawDistance`; `display_update_camera()` updates far | Position/orientation/FOV in `LLAgentCamera::updateCamera()`; far and active 3D render state in `display_update_camera()` | Authoritative render-facing main camera when `sCurCameraID == CAMERA_WORLD` | Also reused as infrastructure adjacent to snapshots/selection; other camera IDs denote non-main contexts | `SOURCE-PROVEN` |
| `LLCamera` base of `LLViewerCamera` | Frustum parameters and planes | Inherits `LLCoordFrame` | Inherits `LLCoordFrame` | `mView`, vertical radians | `mAspect`, width/height | `mNearPlane`, `mFarPlane`; frustum calculations use them | Setters recalculate frustum; `updateFrustumPlanes()` reconstructs planes from active matrices and viewport | Supplies culling/frustum parameters for the viewer camera | `mLastAgentPlanes` tracks prior plane state for `isChanged()`; this is not proven to be temporal render-matrix history | `SOURCE-PROVEN` |
| `LLCoordFrame` base | Coordinate frame underlying the camera | `mOrigin` | `mXAxis`, `mYAxis`, `mZAxis`, exposed as at/left/up | n/a | n/a | n/a | Written by camera update | Source coordinate frame for view/model-view construction | `getMatrixToLocal()` builds a local-space transform from origin/basis | `SOURCE-PROVEN` |

Additional source-backed ownership facts:

- `LLAgentCamera::init()` initializes `mDrawDistance` from `RenderFarClip`, sets the viewer-camera default FOV, sets near to `0.1f`, far to the draw distance, and initializes aspect/view-height defaults. This makes `LLAgentCamera` the higher-level policy/controller and `LLViewerCamera` the render-facing frustum/frame object rather than interchangeable names for one object.
- `LLViewerWindow` updates `LLViewerCamera::setAspect()` and `setViewHeightInPixels()` when the raw world-view rectangle changes. `getWorldViewAspectRatio()` is explicitly raw world-view width divided by raw world-view height.
- `LLViewerCamera::updateCameraLocation()` rejects invalid basis construction, then stores origin and basis; it also derives pixel-meter/screen-area quantities from view height and FOV. These are camera-derived application values, not active GL matrix state.

## Matrix Inventory

| Source name | Owner | Semantic meaning | Type | Construction | Update point / activation | Active lifetime | Inverse relationship | Consumers | Shader-visible form | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|
| `LLViewerCamera::mModelviewMatrix` | `LLViewerCamera` | Cached camera-to-local/OpenGL-style model-view convenience matrix | `LLMatrix4`, mutable cache | `getMatrixToLocal(mModelviewMatrix)` then multiply by `OGL_TO_CFR_ROTATION` in `getModelview()` | On `getModelview()` call | Cache value until recalculated; not proven to be the currently active draw matrix | No persistent inverse member paired with it | CPU callers of `getModelview()` | None directly proven; active shader matrix comes from `LLRender` | `SOURCE-PROVEN` |
| active model-view stack entry | `thread_local LLRender gGL` | Current lower-level model-view used for rendering/draw state | `glm::mat4` in `mMatrix[MM_MODELVIEW][...]` | `LLViewerCamera::setPerspective()` builds OpenGL camera transform from `OGL_TO_CFR_ROTATION` and `getOpenGLTransform()`; later per-object/pass matrix operations can modify stack | Loaded in `setPerspective()` before main cull/render; draw code may push/load/multiply/pop | Mutable per draw/pass; base camera matrix is restored/reloaded around auxiliary and object work where source does so | `LLRender::syncMatrices()` computes cached inverse when matrix hash changes | Vertex transforms, light transforms, renderer infrastructure | `modelview_matrix`; optional `inv_modelview`; `normal_matrix`; contributes to MVP | `SOURCE-PROVEN` |
| `gGLModelView` | llrender global helper state | Copy of the source-designated “current modelview” for CPU-side consumers | `F32[16]` | `set_current_modelview()` copies a `glm::mat4` | Normal non-selection, non-zoom camera setup writes it; other specialized paths can write/restore it explicitly | Global helper state; not identical to every transient top-of-stack object matrix | `get_current_modelview()` can be inverted by consumers | Frustum reconstruction, culling temporal delta, render helpers | Not uploaded by this array directly; related active matrix is uploaded by `LLRender` | `SOURCE-PROVEN` |
| `LLViewerCamera::mProjectionMatrix` | `LLViewerCamera` | Cached perspective projection convenience matrix | `LLMatrix4`, mutable cache | `calcProjection(far_distance)` fills perspective coefficients from FOV/aspect/near/far | `getProjection()` recalculates with `getFar()`; `setPerspective()` also calls `calcProjection(z_far)` | Cache only; can differ from active render projection | No stored inverse member | CPU callers of `getProjection()` | None directly; shader projection comes from active `LLRender` state | `SOURCE-PROVEN` |
| active projection stack entry | `thread_local LLRender gGL` | Current lower-level projection used by draws | `glm::mat4` in `mMatrix[MM_PROJECTION][...]` | Normal path: optional zoom/subregion transform multiplied by `glm::perspective(fov, aspect, z_near, z_far)` | `LLViewerWindow::setup3DRender()` -> `LLViewerCamera::setPerspective()` | Base main projection through main world work, subject to push/pop/replacement by special passes and later screen-space post setup | `LLRender::syncMatrices()` computes `glm::inverse(mat)` transiently if shader requests it | Geometry, deferred reconstruction, post/shader infrastructure | `projection_matrix`; optional `inv_proj`; contributes to MVP | `SOURCE-PROVEN` |
| `gGLProjection` | llrender global helper state | Copy of source-designated current projection | `F32[16]` | `set_current_projection()` | `setPerspective()` writes it; auxiliary paths explicitly replace/restore it | Global helper state | Consumers can invert separately; automatic shader inverse uses LLRender stack, not this array directly | Frustum CPU work, helper projection/unprojection | Indirect only | `SOURCE-PROVEN` |
| `cached_inv_mdv` | function-static state in `LLRender::syncMatrices()` | Inverse of current active LLRender model-view | `glm::mat4` | `glm::inverse(active modelview)` when matrix hash changes | On matrix synchronization for a bound shader | Cached across sync calls until model-view hash changes | Inverse model-view | Normal-matrix calculation and shader upload | `inv_modelview` | `SOURCE-PROVEN` |
| local `inv_proj` | `LLRender::syncMatrices()` stack-local | Inverse of current active LLRender projection | `glm::mat4` | `glm::inverse(active projection)` | Calculated only when projection changed and shader exposes inverse-projection uniform | Transient | Inverse projection | Shader upload | `inv_proj` | `SOURCE-PROVEN` |
| `cached_mvp` | function-static state in `LLRender::syncMatrices()` | Projection × model-view | `glm::mat4` | active projection multiplied by active model-view, hash-cached | On matrix sync when requested | Cached until either source hash changes | No inverse MVP is built here | Vertex shaders | `modelview_projection_matrix` | `SOURCE-PROVEN` |
| `gGLDeltaModelView` | llrender global, computed by `LLPipeline::updateCull()` | Transform described by implementation as last camera space -> current camera space | `glm::mat4` | `current_modelview * inverse(last_modelview)` for the main `LLViewerCamera` | During main-camera cull | Persists until next assignment | `gGLInverseDeltaModelView = inverse(delta)` | Deferred/SSR-capable shader infrastructure | `modelview_delta` | `SOURCE-PROVEN` for computation/upload; temporal source identity is separately unresolved |
| `gGLInverseDeltaModelView` | llrender global | Inverse camera-space delta | `glm::mat4` | inverse of `gGLDeltaModelView` | Same as above | Same as above | Inverse of delta | Deferred/SSR-capable shader infrastructure | `inv_modelview_delta` | `SOURCE-PROVEN` |
| `mShadowModelview[]`, `mShadowProjection[]`, `mSunShadowMatrix[]` | `LLPipeline` | Auxiliary shadow-camera state | `glm::mat4` arrays | Shadow-specific view/projection construction | Shadow generation before main G-buffer | Auxiliary shadow lifetime/history | Shadow code also uses global current/last helper slots transiently | Shadow rendering/shader state | Shadow-specific uniforms, not normal main projection identity | `SOURCE-PROVEN` |
| explicit inverse view-projection | — | Requested conceptual inverse VP | — | No explicit normal-main source object was established in examined matrix infrastructure | — | — | Would be inverse of view-projection if it existed | — | No generic shader-visible inverse VP was source-proven | `UNRESOLVED` |

Two matrix identities must not be collapsed:

1. `LLViewerCamera`’s `mProjectionMatrix`/`mModelviewMatrix` are lazily/repeatedly derived CPU-side caches.
2. The matrices active for a draw are the `LLRender` matrix-stack entries. `LLRender::syncMatrices()` uploads those active entries, not the `LLViewerCamera` cache members.

This distinction is material for projection. `LLViewerCamera::getProjection()` calls `calcProjection(getFar())`, while normal `LLViewerWindow::setup3DRender()` calls `setPerspective()` with an explicit far clip of `MAX_FAR_CLIP * 2.f`. The normal active main render projection can therefore differ from the convenience projection cache derived from the viewer camera's culling/draw-distance far value.

## Viewport Inventory

| State | Dimensions / origin | Ownership / source | OpenGL application point | Render-target relationship | Restoration | Conditional scaling | Confidence |
|---|---|---|---|---|---|---|---|
| Raw main-world viewport | `mWorldViewRectRaw` left/bottom/width/height | `LLViewerWindow` | `setup3DViewport()` writes `gGLViewport[0..3]` then calls `glViewport(...)`; `setPerspective()` also sets viewport in normal non-selection path | Represents the world-view area in the window, not necessarily a render-target texture size | Re-established by `setup3DViewport()` and by render-target flush to default framebuffer | Not itself reduced by Firestorm render-resolution scaling | `SOURCE-PROVEN` |
| `gGLViewport` | Copy of raw/current source-designated viewport | llrender global | Read by frustum projection/unprojection and by `LLRenderTarget::flush()` when returning to default framebuffer | Deliberately distinct from the viewport selected by `LLRenderTarget::bindTarget()` | Used to restore default framebuffer viewport | Can remain raw-window-sized while bound RT is scaled | `SOURCE-PROVEN` |
| Bound `LLRenderTarget` viewport | Origin `(0,0)`, dimensions `mResX × mResY` | `LLRenderTarget` | `bindTarget()` calls `glViewport(0,0,mResX,mResY)` | Main `mMainRT.deferredScreen` and other targets therefore render using target dimensions | `flush()` binds previous target; if none, restores `glViewport(gGLViewport...)` | Main screen/deferred RT may be smaller than raw world view | `SOURCE-PROVEN` |
| Main RT allocation size | Starts from raw world-view width/height | `LLPipeline::resizeScreenTexture()` | Applied indirectly when target is bound | `scaledResX/Y` are used to decide release/reallocation of screen targets | Recreated on size/scaling changes | `RenderResolutionDivisor` divides dimensions; otherwise `RenderResolutionMultiplier` in `(0,1)` scales dimensions down | `SOURCE-PROVEN` |

Source-backed consequence: window/world-view aspect and render-target raster dimensions are separate concepts. `LLViewerCamera::mAspect` is derived from the raw world-view rectangle. Binding the main deferred render target can then set a smaller `(0,0,scaledWidth,scaledHeight)` GL viewport without changing the camera aspect field.

The prior G-buffer audit establishes that normal main-view deferred rendering uses `LLPipeline::mMainRT.deferredScreen`; therefore the target-sized viewport behavior above applies directly to the normal G-buffer stage when the main render-target pack is active.

## Depth-Space Findings

### Projection convention

**Status:** `SOURCE-PROVEN`

`LLViewerCamera::calcProjection()` constructs a perspective matrix with:

```text
m[0][0] = f / aspect
m[1][1] = f
m[2][2] = (z_far + z_near) / (z_near - z_far)
m[3][2] = (2 * z_far * z_near) / (z_near - z_far)
m[2][3] = -1
```

The active normal path uses `glm::perspective(fov_y, aspect, z_near, z_far)` inside `setPerspective()`.

### Sampled depth -> NDC -> eye/view position

**Status:** `SOURCE-PROVEN`

`class1/deferred/deferredUtil.glsl` explicitly reconstructs position as:

```text
depth = texture(depthMap, uv).r
ndc.xy = uv * 2 - 1
ndc.z  = depth * 2 - 1
pos    = inv_proj * vec4(ndc, 1)
pos   /= pos.w
```

The same shader utility's `linearDepth()` first remaps sampled depth with `d = d * 2.0 - 1.0`. This source directly establishes the deferred reconstruction convention without relying on generic OpenGL assumptions.

### Near and far identities

**Status:** `SOURCE-PROVEN`

There are multiple materially different “far” concepts:

- `LLAgentCamera::mDrawDistance` is the higher-level configured draw distance.
- `display_update_camera()` computes `final_far` and writes it to `LLViewerCamera::setFar(final_far)` for main camera/frustum use.
- normal `LLViewerWindow::setup3DRender()` activates a perspective matrix with far `MAX_FAR_CLIP * 2.f`, not `LLViewerCamera::getFar()`.
- `LLViewerCamera::updateFrustumPlanes()` reconstructs near/far rays from active projection/viewport, then on the ordinary perspective path places far frustum corners at `camera.getOrigin() + direction * camera.getFar()`. Thus the culling/frustum far can remain the viewer draw distance even though the raster projection extends farther.

The normal active near passed to `setPerspective()` is `LLViewerCamera::getNear()`. `LLAgentCamera::init()` sets that viewer near to `0.1f` with an implementation comment that it remains there pending real near-clip management; this audit did not find a normal-main dynamic near-management path that supersedes that initialization.

### Native depth resource

**Status:** `SOURCE-PROVEN` from accepted `FS-GBUF-001`

The main native deferred depth is `LLPipeline::mMainRT.deferredScreen.mDepth`, requested as `GL_DEPTH_COMPONENT24`. The same depth texture is attached to `mMainRT.screen` through `shareDepthBuffer()`, so later post-deferred depth-writing work can evolve the same native scene-depth resource rather than preserving a frozen opaque-only snapshot.

### Reversed/logarithmic depth and explicit depth-range state

- `LIKELY`: the examined normal deferred path is not reversed-Z. The source-built projection and the shader reconstruction both use the non-reversed relation represented above; no reversed-depth branch was found in the bounded main path.
- `LIKELY`: no logarithmic depth transform is used in the examined normal deferred reconstruction path; depth is sampled and inverse-projected directly.
- `UNRESOLVED`: an explicit normal-main `glDepthRange`/`glDepthRangef` state-setting point was not established. Repository search found function loading/declarations but no source-proven normal-main setter in this bounded trace. No default range is asserted from generic OpenGL behavior.
- `UNRESOLVED`: a source-level proof that no `glClipControl` call can affect the context anywhere outside the traced path was not established. No normal-main use was located, so no alternate clip-control convention is claimed.

## Shader-State Flow

| Source state | Calculation / transformation | Upload / binding | Shader-visible state | Confidence |
|---|---|---|---|---|
| active `LLRender` model-view stack entry | none | `LLRender::syncMatrices()` when matrix hash differs for bound shader | `modelview_matrix` | `SOURCE-PROVEN` |
| active model-view | `glm::inverse(modelview)`; cached by model-view hash | `LLRender::syncMatrices()` | `inv_modelview` | `SOURCE-PROVEN` |
| active model-view inverse | transpose; upper-left 3×3 extracted | `LLRender::syncMatrices()` | `normal_matrix` | `SOURCE-PROVEN` |
| active `LLRender` projection stack entry | none | `LLRender::syncMatrices()` | `projection_matrix` | `SOURCE-PROVEN` |
| active projection | `glm::inverse(projection)` | `LLRender::syncMatrices()` | `inv_proj` | `SOURCE-PROVEN` |
| active projection + model-view | `projection * modelview` | `LLRender::syncMatrices()` | `modelview_projection_matrix` | `SOURCE-PROVEN` |
| main deferred target dimensions | width/height of current `mRT->deferredScreen` | `LLPipeline::bindDeferredShader()` | `screen_res` | `SOURCE-PROVEN` |
| `LLViewerCamera::getNear()` | multiplied by `2.f` | `LLPipeline::bindDeferredShader()` | `near_clip` | `SOURCE-PROVEN` |
| `LLViewerCamera::getOrigin()` | no additional transform at this upload point | `LLSettingsVOSky::applySpecial()` | `camPosLocal` (`WL_CAMPOSLOCAL`) for applicable sky/atmospheric shader groups | `SOURCE-PROVEN` |
| `get_last_modelview()` + `get_current_modelview()` | `current * inverse(last)` | `LLPipeline::updateCull()` computes; `bindDeferredShader()` uploads | `modelview_delta` | `SOURCE-PROVEN` for arithmetic/upload; prior-frame identity `UNRESOLVED` |
| `gGLDeltaModelView` | inverse | `LLPipeline::bindDeferredShader()` | `inv_modelview_delta` | `SOURCE-PROVEN` |
| main deferred native depth | texture sample -> `depth*2-1` -> `inv_proj` | texture binding + automatic inverse projection matrix | eye/view position in deferred shader helpers | `SOURCE-PROVEN` |

The reserved-uniform registry in `LLShaderMgr::initAttribsAndUniforms()` names the generic camera/matrix slots (`modelview_matrix`, `projection_matrix`, `inv_proj`, `modelview_projection_matrix`, `inv_modelview`, `normal_matrix`) and deferred camera/depth-related slots (`screen_res`, `near_clip`, `modelview_delta`, `inv_modelview_delta`). The registry establishes names; `LLRender::syncMatrices()` and `LLPipeline::bindDeferredShader()` establish the corresponding upload behavior.

No single global “camera block” or uniform buffer was established for these values in the examined path. The source instead shows a mixture of automatic renderer matrix synchronization and explicit per-pipeline/per-environment uniform uploads.

## Frame/Pass State Timeline

```text
LLAppViewer::doFrame()
  |
  +-- idle()
  |     |
  |     +-- gAgentCamera.updateCamera()
  |           - computes behavioral/global camera/focus state
  |           - converts camera/focus to agent space
  |           - LLViewerCamera::updateCameraLocation(...)
  |           - updates effective FOV
  |
  +-- display()
        |
        +-- display_update_camera()
        |     - computes final_far
        |     - LLViewerCamera::setFar(final_far)
        |     - gViewerWindow->setup3DRender()
        |           |
        |           +-- LLViewerCamera::setPerspective(...,
        |                 near = camera.getNear(),
        |                 far  = MAX_FAR_CLIP*2)
        |                 - sets base main projection/model-view
        |                 - sets raw world GL viewport / current matrix helpers
        |
        +-- pre-main auxiliary rendering as applicable
        |     - shadows / impostors / probes use non-main camera/matrix/viewport state
        |     - source paths save/restore main matrices/viewport where required
        |
        +-- LLViewerCamera::sCurCameraID = CAMERA_WORLD
        +-- gPipeline.updateCull(main LLViewerCamera)
        |     - consumes main camera/frustum
        |     - computes modelview delta for main camera
        |
        +-- main deferredScreen.bindTarget()
        |     - OpenGL viewport becomes (0,0,main deferred RT dimensions)
        |     - camera aspect/state does not become RT-owned
        |
        +-- renderGeomDeferred(...)
        |     - per-object model-view changes occur on LLRender stack
        |     - shaders receive active matrices through syncMatrices()
        |
        +-- deferredScreen.flush()
        |     - G-buffer complete (accepted FS-FRAME/FS-GBUF boundary)
        |
        +-- renderDeferredLighting()
        |     - binds deferred textures/depth
        |     - bindDeferredShader() uploads screen_res, 2*near,
        |       temporal model-view delta, etc.
        |     - deferredUtil reconstructs view-space position from depth + inv_proj
        |
        +-- renderGeomPostDeferred(...)
        |     - same viewer-camera ownership remains applicable
        |     - active lower-level matrices can change/reload per draw/pass
        |     - water/alpha are later world passes (accepted FS-FRAME/FS-POST)
        |
        +-- render_ui(...)
              |
              +-- renderFinalize()
              |     - post targets repeatedly bind target-sized viewports
              |     - post/full-screen matrix state is not a new viewer camera
              |     - final pre-ordinary-UI scene reaches default framebuffer
              |
              +-- ordinary HUD/UI
              +-- swap()
```

Pass-consistency findings:

- `SOURCE-PROVEN`: the application-level `LLViewerCamera` is made current as `CAMERA_WORLD` before main culling. No second normal visible-camera update was established between main cull and the main G-buffer/deferred/post-deferred world stages.
- `SOURCE-PROVEN`: active lower-level matrices are not numerically immutable across those stages. Object draws, full-screen passes, shadow/auxiliary contexts, and post-processing can push/load/replace matrices. Camera identity must therefore be inferred from source ownership/restoration boundaries, not from a claim that every draw has one identical matrix value.
- `SOURCE-PROVEN`: auxiliary shadow rendering constructs independent view/projection matrices, assigns shadow camera IDs, changes render-target viewport, and restores saved matrix/history state around that work. It must not be classified as the main visible camera merely because it uses the same LLRender matrix infrastructure.
- `SOURCE-PROVEN`: avatar-impostor work similarly saves current projection/model-view, uses an auxiliary `512×512` viewport, and restores the saved matrices before the normal main-view boundary.
- `SOURCE-PROVEN`: post-processing repeatedly changes the actual GL viewport as different `LLRenderTarget`s are bound. This is target/raster state, not evidence of a changed viewer-camera aspect or ownership.

## Findings

### Finding 1 — Firestorm has distinct application-camera, viewer-camera, and renderer-matrix ownership layers

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llagentcamera.h`, `indra/newview/llagentcamera.cpp`
- Class: `LLAgentCamera`
- Functions/symbols: `updateCamera()`, `init()`, `mDrawDistance`, focus/zoom/camera-mode state
- Path: `indra/newview/llviewercamera.h`, `indra/newview/llviewercamera.cpp`
- Class: `LLViewerCamera`
- Functions/symbols: `updateCameraLocation()`, `setPerspective()`, `getModelview()`, `getProjection()`
- Path: `indra/llrender/llrender.h`, `indra/llrender/llrender.cpp`
- Class: `LLRender`
- Symbols: `mMatrix`, `MM_MODELVIEW`, `MM_PROJECTION`, `syncMatrices()`

**What the source proves:** `LLAgentCamera` computes behavioral camera state; `LLViewerCamera` stores the render-facing agent-space frame/frustum; `LLRender` owns the active lower-level matrix stacks used by draws and shader synchronization. Similar camera/matrix names do not denote one state object.

### Finding 2 — The render-facing camera position/orientation is agent-space origin plus an orthonormal at/left/up basis

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llagentcamera.cpp`
- Class: `LLAgentCamera`
- Function: `updateCamera()`
- Path: `indra/newview/llviewercamera.cpp`
- Class: `LLViewerCamera`
- Function: `updateCameraLocation()`
- Path: `indra/llmath/llcoordframe.h`, `indra/llmath/llcoordframe.cpp`
- Class: `LLCoordFrame`
- Symbols: `mOrigin`, `mXAxis`, `mYAxis`, `mZAxis`, `setOrigin()`, `setAxes()`

**What the source proves:** the higher-level camera/focus positions are converted from global to agent coordinates, then `updateCameraLocation()` constructs normalized at/left/up vectors and stores them in the inherited coordinate frame. No additional normal-main large-world origin-rebase object was established in this bounded trace.

### Finding 3 — FOV, aspect, near, and camera/culling far are viewer-camera fields, but their producers differ

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/llmath/llcamera.h`
- Class: `LLCamera`
- Symbols: `mView`, `mAspect`, `mNearPlane`, `mFarPlane`
- Path: `indra/newview/llagentcamera.cpp`
- Class: `LLAgentCamera`
- Functions: `init()`, `updateCamera()`
- Path: `indra/newview/llviewerwindow.cpp`
- Class: `LLViewerWindow`
- Symbols: world-view reshape/update paths, `getWorldViewAspectRatio()`
- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display_update_camera()`

**What the source proves:** `LLAgentCamera` supplies draw distance and effective FOV; `LLViewerWindow` supplies raw world-view aspect; near is initialized to `0.1f`; `display_update_camera()` makes `final_far` current on the viewer camera before main rendering.

### Finding 4 — The viewer-camera far plane and the normal active raster projection far plane are not the same state

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display_update_camera()`
- Path: `indra/newview/llviewerwindow.cpp`
- Class: `LLViewerWindow`
- Function: `setup3DRender()`
- Path: `indra/newview/llviewercamera.cpp`
- Class: `LLViewerCamera`
- Functions: `setPerspective()`, `updateFrustumPlanes()`
- Path: `indra/llmath/llcamera.h`
- Symbol: `MAX_FAR_CLIP`

**What the source proves:** the viewer camera receives `final_far` for camera/frustum use, while normal `setup3DRender()` passes an explicit `MAX_FAR_CLIP*2.f` far value to the active perspective matrix. Frustum reconstruction then uses `camera.getFar()` for far corners on the ordinary perspective path. Culling/draw distance and projection depth range must not be collapsed.

### Finding 5 — Normal main-view camera state becomes current through `idle()` camera update followed by `display_update_camera()` and `setup3DRender()`

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llappviewer.cpp`
- Class: `LLAppViewer`
- Functions: `doFrame()`, `idle()`
- Path: `indra/newview/llagentcamera.cpp`
- Class: `LLAgentCamera`
- Function: `updateCamera()`
- Path: `indra/newview/llviewerdisplay.cpp`
- Functions: `display()`, `display_update_camera()`
- Path: `indra/newview/llviewerwindow.cpp`
- Class: `LLViewerWindow`
- Function: `setup3DRender()`

**What the source proves:** `doFrame()` idles/updates application state before entering its explicit render-scene `display()` block. The camera controller updates position/orientation/FOV during idle; `display_update_camera()` then makes final far state current and calls `setup3DRender()` before the main camera cull and G-buffer stage.

### Finding 6 — The normal main model-view is derived from the camera coordinate frame and an explicit OpenGL/CFR basis conversion

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewercamera.cpp`
- Class: `LLViewerCamera`
- Functions: `getModelview()`, `setPerspective()`
- Path: `indra/llmath/llcoordframe.cpp`
- Class: `LLCoordFrame`
- Functions: `getMatrixToLocal()`, `getOpenGLTransform()`
- Path: `indra/llrender/llrender.h`
- Symbol: `OGL_TO_CFR_ROTATION`

**What the source proves:** Firestorm does not store a separate persistent high-level “view matrix” object for normal rendering. It constructs camera-to-eye/model-view forms from the `LLCoordFrame` origin/basis plus the CFR/OpenGL basis conversion, then loads the result into renderer model-view state.

### Finding 7 — `LLViewerCamera`'s cached matrices are not the authoritative active matrices for every draw

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewercamera.h`, `indra/newview/llviewercamera.cpp`
- Class: `LLViewerCamera`
- Symbols: `mModelviewMatrix`, `mProjectionMatrix`, `getModelview()`, `getProjection()`, `calcProjection()`, `setPerspective()`
- Path: `indra/llrender/llrender.h`, `indra/llrender/llrender.cpp`
- Class: `LLRender`
- Symbols: matrix stack, `loadMatrix()`, `multMatrix()`, `pushMatrix()`, `popMatrix()`

**What the source proves:** the viewer-camera members are derived caches, while the active draw state lives in `LLRender`. The projection cache can use `camera.getFar()` even when the active normal main projection was built with `MAX_FAR_CLIP*2`, and active matrices can change per object/pass.

### Finding 8 — The normal main projection is perspective, with conditional pick/zoom operations in `setPerspective()`

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewercamera.cpp`
- Class: `LLViewerCamera`
- Functions: `setPerspective()`, `calcProjection()`

**What the source proves:** the normal non-selection branch establishes the viewport, applies optional zoom/subregion scale/translation when `mZoomFactor > 1`, then multiplies by `glm::perspective(fov_y, aspect, z_near, z_far)` and loads it as active projection. Selection adds a pick matrix and is not the normal main path.

### Finding 9 — Inverse model-view and inverse projection are shader-support derivations, not persistent viewer-camera matrix objects

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/llrender/llrender.cpp`
- Class: `LLRender`
- Function: `syncMatrices()`

**What the source proves:** `syncMatrices()` hash-caches the inverse of active model-view in function-static `cached_inv_mdv`; it calculates inverse projection as a local `glm::inverse(mat)` when a bound shader requests `INVERSE_PROJECTION_MATRIX`. These are derived from active renderer matrices at synchronization time.

### Finding 10 — A generic explicit inverse view-projection object was not established

**Confidence:** `UNRESOLVED`

**Status:** `UNRESOLVED`

**Source:**

- Examined paths: `indra/llrender/llrender.h`, `indra/llrender/llrender.cpp`, `indra/llrender/llshadermgr.h`, `indra/llrender/llshadermgr.cpp`, main camera/pipeline paths
- Relevant symbols: generic matrix uniforms and `LLRender::syncMatrices()`

**What the source proves:** the audited infrastructure exposes model-view, projection, MVP, inverse model-view, and inverse projection. No generic normal-main inverse view-projection source object or reserved uniform was established. This audit does not manufacture one conceptually.

### Finding 11 — Raw world viewport state and the actual viewport of a bound render target are intentionally separate

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewerwindow.cpp`
- Class: `LLViewerWindow`
- Function: `setup3DViewport()`
- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Functions: `bindTarget()`, `flush()`
- Path: `indra/llrender/llrender.cpp`
- Symbol: `gGLViewport`

**What the source proves:** `setup3DViewport()` stores the raw world rectangle in `gGLViewport`. `LLRenderTarget::bindTarget()` instead calls `glViewport(0,0,targetWidth,targetHeight)` without rewriting `gGLViewport`. `flush()` restores the previous target or, for the default framebuffer, the saved `gGLViewport`.

### Finding 12 — Main render-target resolution can be lower than the raw world-view dimensions

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `resizeScreenTexture()`
- Symbols: `RenderResolutionDivisor`, `RenderResolutionMultiplier`
- Accepted prior path: `LLPipeline::mMainRT.deferredScreen`

**What the source proves:** screen-buffer sizing begins with raw world-view width/height and conditionally divides or multiplies them down before reallocating screen targets. The camera aspect remains tied to raw world-view width/height, while `deferredScreen.bindTarget()` uses the scaled target resolution for the actual GL viewport.

### Finding 13 — Deferred shaders reconstruct eye/view position from sampled depth with `inv_proj`

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/app_settings/shaders/class1/deferred/deferredUtil.glsl`
- Symbols: `getDepth()`, `getPosition()`, `getPositionWithDepth()`, `linearDepth()`
- Path: `indra/llrender/llrender.cpp`
- Class: `LLRender`
- Function: `syncMatrices()`

**What the source proves:** sampled depth is remapped to NDC with `2*depth-1`, then multiplied by shader uniform `inv_proj` and divided by `w`. `syncMatrices()` supplies `inv_proj` as the inverse of the active renderer projection.

### Finding 14 — Camera/matrix/depth shader state is split between automatic matrix synchronization and explicit pipeline/environment uploads

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/llrender/llrender.cpp`
- Class: `LLRender`
- Function: `syncMatrices()`
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `bindDeferredShader()`
- Path: `indra/newview/llsettingsvo.cpp`
- Class: `LLSettingsVOSky`
- Function: `applySpecial()`
- Path: `indra/llrender/llshadermgr.cpp`
- Class: `LLShaderMgr`
- Function: `initAttribsAndUniforms()`

**What the source proves:** generic matrices/inverses are uploaded automatically from `LLRender`; deferred screen resolution, `2*cameraNear`, and temporal delta matrices are uploaded explicitly by `bindDeferredShader()`; applicable environmental shader groups receive `camPosLocal` explicitly from `LLViewerCamera::getOrigin()`.

### Finding 15 — Auxiliary cameras and render targets materially change matrices/viewports but are distinguishable and restored around the main path

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display()`; avatar-impostor update block
- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Shadow-generation functions/symbols: shadow cameras, `mShadowModelview`, `mShadowProjection`, camera IDs, saved/restored current/last matrices

**What the source proves:** shadow and impostor rendering use independent projections/viewports and can overwrite shared matrix helper state temporarily. Source saves/restores the relevant main state. These paths cannot be identified as main-view merely because they use `LLRender`, `LLCamera`, or similarly sized targets.

### Finding 16 — Firestorm computes and uploads a main-camera model-view delta

**Confidence:** `SOURCE-PROVEN`

**Status:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `updateCull()`, `bindDeferredShader()`
- Path: `indra/llrender/llrender.cpp`, `indra/llrender/llrender.h`
- Symbols: `gGLLastModelView`, `gGLDeltaModelView`, `gGLInverseDeltaModelView`, current/last matrix helpers

**What the source proves:** when `updateCull()` receives the singleton main `LLViewerCamera`, it computes `current_modelview * inverse(last_modelview)`, stores that result in `gGLDeltaModelView`, computes its inverse in `gGLInverseDeltaModelView`, and `bindDeferredShader()` uploads the two matrices as `modelview_delta` and `inv_modelview_delta`.

### Finding 17 — The immediately-previous-visible-frame identity of the global last model-view is not established

**Confidence:** `UNRESOLVED`

**Status:** `UNRESOLVED`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions/symbols: `updateCull()`, shadow-generation paths, `set_last_modelview()`, `set_last_projection()`
- Path: `indra/llrender/llrender.cpp`, `indra/llrender/llrender.h`
- Symbols: `gGLLastModelView`, `gGLLastProjection`, get/set current/last matrix helpers

**What the source proves:** shadow rendering temporarily writes the global last-matrix slots from shadow-history matrices and later restores saved last-matrix values. The bounded trace did not locate the normal-main writer boundary that advances those saved slots between visible frames. Therefore the arithmetic intent is clear, but the exact identity “immediately previous visible main-view frame” is not source-proven here.

### Finding 18 — Explicit global depth-range state is not source-proven by this bounded trace

**Confidence:** `UNRESOLVED`

**Status:** `UNRESOLVED`

**Source:**

- Examined paths/search: normal main camera setup, `LLRender`, `LLRenderTarget`, deferred shader utilities; repository-wide symbol search for `glDepthRange`/`glDepthRangef` and `glClipControl`

**What the source proves:** the projection and shader reconstruction establish the normal deferred NDC/depth relation needed by this audit, but no explicit normal-main depth-range setter was established. Function declarations/loader assignments are not evidence of active main-frame GL state.

## Unresolved Questions

1. **Temporal matrix advancement:** what exact normal-main source point advances the global “last” model-view/projection state used by `LLPipeline::updateCull()`? Shadow code proves those globals can be temporarily repurposed, so their immediately-previous-visible-frame identity remains unclosed here.
2. **Explicit depth-range state:** no normal-main `glDepthRange`/`glDepthRangef` setter was established. The shader/projective convention is known, but explicit context depth-range state remains unresolved.
3. **Generic inverse VP:** no explicit normal-main inverse view-projection object/uniform was found in the audited infrastructure. A broader shader-utility search could determine whether an isolated pass builds one under a pass-specific name, but this audit does not require that inventory.
4. **Zoomed/snapshot matrix helper semantics:** `setPerspective()` only updates the `gGLModelView` helper on the non-selection `mZoomFactor == 1.f` path. Snapshot/subregion semantics are auxiliary to the requested normal visible frame and were not expanded.
5. **Every post-process matrix mutation:** `renderFinalize()` contains many full-screen passes. Their target viewport behavior is established, but an exhaustive per-effect matrix-stack inventory would broaden beyond camera ownership and is intentionally not pursued.

## Recommended Next Audit

- **Proposed task ID:** `FS-TEMPORAL-001`
- **Exact question:** What exact source path advances and preserves `gGLLastModelView`, `gGLLastProjection`, `gGLDeltaModelView`, and `gGLInverseDeltaModelView` for the immediately previous normal visible main-view frame, and which deferred/SSR shader consumers rely on that temporal identity?
- **Why this is the next dependency:** `FS-CAMERA-001` proves that main culling computes and deferred binding uploads model-view delta matrices, but it also proves that shadow rendering temporarily reuses/restores the same global last-matrix slots. The remaining ambiguity is therefore a concrete source dependency created by the evidence, not a presumed downstream feature requirement.
- **Likely source starting points:** `indra/newview/pipeline.cpp` (`LLPipeline::updateCull()`, `bindDeferredShader()`, shadow-generation paths); `indra/llrender/llrender.cpp` / `llrender.h` (current/last matrix globals and helpers); `indra/newview/llviewerdisplay.cpp` (main-frame restoration boundaries); `indra/newview/app_settings/shaders/class3/deferred/screenSpaceReflUtil.glsl` and related deferred consumers.

## Handoff Summary

- Main camera policy/behavior is owned by `LLAgentCamera`; render-facing frame/frustum state is owned by `LLViewerCamera`/`LLCamera`.
- Camera global targets are converted to agent-space origin/basis before rendering.
- Main FOV/aspect/near/culling-far are viewer-camera state, but active projection far is separately `MAX_FAR_CLIP*2` in normal `setup3DRender()`.
- The active matrices used by draws belong to `LLRender`, not the `LLViewerCamera` cache members.
- `syncMatrices()` uploads model-view/projection/MVP and derives inverse model-view, inverse projection, and normal matrix on demand.
- Raw world viewport (`gGLViewport`) and bound render-target viewport are distinct; main RTs can be resolution-scaled.
- Deferred depth is the accepted main `GL_DEPTH_COMPONENT24` resource shared into the lit scene target.
- Deferred shaders remap sampled depth with `2*d-1` and reconstruct eye/view position with `inv_proj`.
- `bindDeferredShader()` explicitly uploads target `screen_res`, `2*cameraNear`, and model-view delta state.
- `camPosLocal` is explicitly sourced from `LLViewerCamera::getOrigin()` for applicable environment shader groups.
- Auxiliary shadow/impostor contexts change matrices/viewports but have source-backed restoration boundaries.
- Explicit normal-main GL depth-range state remains unresolved.
- Temporal delta computation/upload is proven; the exact immediately-previous-visible-frame writer identity is not.
- Next audit: `FS-TEMPORAL-001`, bounded to temporal matrix-history advancement and consumers.
