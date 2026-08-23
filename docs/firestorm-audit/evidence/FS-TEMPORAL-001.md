# FS-TEMPORAL-001

## Question

How does Firestorm advance, preserve, replace, restore, and consume current/last matrix state across normal visible main-view frames?

## Repository State

- Repository: `https://github.com/FirestormViewer/phoenix-firestorm`
- Branch: `master`
- Commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`
- Platform: Windows
- Renderer: OpenGL
- Render scope: normal visible-camera main-view frames
- Accepted prior evidence:
  - `FS-FRAME-001.md`
  - `FS-GBUF-001.md`
  - `FS-POST-001.md`
  - `FS-CAMERA-001.md`
- Audit type: source analysis only. No runtime capture or experimentation is claimed.

This is a new evidence record. It does not edit any accepted prior audit. Where current pinned-source evidence conflicts with an accepted record, the conflict is preserved explicitly below.

## Executive Temporal Map

```text
end of Frame N-1 normal non-cube 3D scene
LLPipeline::renderDeferredLighting()
    |
    | screen_target->flush()
    | if (!gCubeSnapshot)
    v
gGLLastModelView  <- gGLModelView(N-1)
gGLLastProjection <- gGLProjection(N-1)
    |
    | persists across frame boundary
    v
Frame N early auxiliary work, if present
    - cube/probe paths may touch shared current/delta state
    |
    v
normal main camera setup
LLViewerCamera::setPerspective(...)
    |
    +--> gGLProjection <- current main projection
    |
    +--> if !for_selection && mZoomFactor == 1:
         gGLModelView <- current main model-view
    |
    v
pre-main sun-shadow work
LLPipeline::generateSunShadow(...)
    - save main current + last
    - temporarily install shadow current + shadow last
    - update mShadowModelview[] / mShadowProjection[]
    - restore saved global last state
    - restore saved current state unless CameraOffset
    |
    v
LLPipeline::renderGeomDeferred(main LLViewerCamera)
    |
    | last = get_last_modelview()       = Frame N-1 main history
    | cur  = get_current_modelview()    = Frame N main current
    v
gGLDeltaModelView        = cur * inverse(last)
gGLInverseDeltaModelView = inverse(gGLDeltaModelView)
    |
    | LLPipeline::bindDeferredShader()
    v
modelview_delta / inv_modelview_delta shader uniforms
    |
    v
screenSpaceReflUtil.glsl
    inv_modelview_delta maps current camera-space ray data
    into the coordinate frame used by sceneMap/sceneDepth
    |
    v
end of Frame N normal non-cube 3D scene
LLPipeline::renderDeferredLighting() tail
    |
    v
gGLLastModelView  <- gGLModelView(N)
gGLLastProjection <- gGLProjection(N)
    |
    | IMPORTANT: from this point onward, "last" is Frame N, not N-1
    v
render_ui()
    - saves current model-view
    - temporarily loads gGLLastModelView (now Frame N) as current
    - restores saved current model-view
    |
    v
Frame N+1 main render consumes Frame N from gGLLastModelView
```

The central temporal result is point-dependent: immediately before the Frame N history-advance copy, `gGLLastModelView` is the previously completed normal non-cube scene's value; immediately after that copy, it is the just-completed Frame N value. The name `Last` does not mean “previous visible frame” at every point in execution.

## State Inventory

| Symbol | Type | Declaration | Initialization | Semantic role established by source | Material writers | Material readers | Lifetime / overwrite boundary | Confidence |
|---|---|---|---|---|---|---|---|---|
| `gGLModelView` | `F32[16]` | `indra/llrender/llrender.cpp`; extern in `llrender.h` | No explicit Firestorm initializer at declaration | CPU-side helper copy designated as current model-view | `set_current_modelview()`; normal `LLViewerCamera::setPerspective()`; shadow substitutions/restores; UI/HUD helper paths | `get_current_modelview()`; end-of-scene history copy; frustum helpers; delta construction | Persists until a helper writer replaces it; not automatically identical to every transient `gGL` stack matrix | `SOURCE-PROVEN` |
| `gGLProjection` | `F32[16]` | `indra/llrender/llrender.cpp`; extern in `llrender.h` | No explicit Firestorm initializer at declaration | CPU-side helper copy designated as current projection | `set_current_projection()`; normal `LLViewerCamera::setPerspective()`; shadow substitutions/restores; HUD-related helper paths | `get_current_projection()`; end-of-scene history copy; frustum helpers | Same helper-state lifetime model as `gGLModelView` | `SOURCE-PROVEN` |
| `gGLLastModelView` | `F32[16]` | `indra/llrender/llrender.cpp`; extern in `llrender.h` | No explicit Firestorm temporal-valid initializer at declaration | Shared “last” model-view slot; at normal-main deferred entry it holds the most recent completed normal non-cube scene copied by `renderDeferredLighting()` | Direct normal history copy in `renderDeferredLighting()`; shadow temporary replacement via `set_last_modelview()`; shadow restoration; no normal-main initialization writer found before first history copy | `renderGeomDeferred()`; shadow save; `render_ui()` | After normal history copy it persists until next normal non-cube history copy, except temporary shadow substitution that is restored | `SOURCE-PROVEN` for steady-state identity; first-valid-frame state `UNRESOLVED` |
| `gGLLastProjection` | `F32[16]` | `indra/llrender/llrender.cpp`; extern in `llrender.h` | No explicit Firestorm temporal-valid initializer at declaration | Shared “last” projection slot; advanced alongside `gGLLastModelView`; proven auxiliary shadow history infrastructure | Direct normal history copy; shadow temporary replacement via `set_last_projection()`; shadow restoration | Shadow save/restore path; no normal-main projection-delta consumer established in this audit | Same copy/substitute/restore pattern as last model-view | `SOURCE-PROVEN` for storage/advancement; normal-main temporal consumer beyond this trace `UNRESOLVED` |
| `gGLDeltaModelView` | `glm::mat4` | `indra/llrender/llrender.cpp`; extern in `llrender.h` | No explicit Firestorm initializer at declaration | Derived transform whose source comment describes last-camera-space -> current-camera-space | `LLPipeline::renderGeomDeferred()` when passed the singleton `LLViewerCamera` | `LLPipeline::bindDeferredShader()` | Persists until the next qualifying `renderGeomDeferred()` assignment; auxiliary cube-face use of the singleton can also overwrite it before later normal-main recomputation | `SOURCE-PROVEN` |
| `gGLInverseDeltaModelView` | `glm::mat4` | same | No explicit Firestorm initializer at declaration | Inverse of `gGLDeltaModelView`; current-camera-space -> prior-history camera-space under the proven normal-main operands | Same `renderGeomDeferred()` block | `bindDeferredShader()`; concrete SSR shader use through `inv_modelview_delta` | Same overwrite cadence as forward delta | `SOURCE-PROVEN` |
| `mShadowModelview[6]` | `glm::mat4[6]` | `indra/newview/pipeline.h`, member of `LLPipeline` | Not independently audited here | Per-shadow model-view history used to populate shared last-model-view temporarily during shadow rendering | `generateSunShadow()` writes current shadow view after installing prior shadow value into global last slot | `generateSunShadow()` | Per-shadow history across shadow updates; separate from normal-main history | `SOURCE-PROVEN` for role in substitution; initialization details out of scope |
| `mShadowProjection[6]` | `glm::mat4[6]` | `indra/newview/pipeline.h`, member of `LLPipeline` | Not independently audited here | Per-shadow projection history used analogously in the shadow path | `generateSunShadow()` | `generateSunShadow()` | Same as shadow model-view history | `SOURCE-PROVEN` for role in substitution; initialization details out of scope |

Primary declaration source:

- `indra/llrender/llrender.cpp`
- `indra/llrender/llrender.h`
- Permalink: `https://github.com/FirestormViewer/phoenix-firestorm/blob/3e20e83b3ea01bb5ae3156d301d0d76ca88dd294/indra/llrender/llrender.cpp`

`llrender.cpp` defines the four `F32[16]` helper arrays without explicit initializers and defines the two `glm::mat4` delta globals. It also defines `get_*`/`set_*` helpers whose setters copy a `glm::mat4` into the corresponding global array.

## Writer Map

| State | Writer | Source value | Context | Operation type | Confidence |
|---|---|---|---|---|---|
| `gGLProjection` | `LLViewerCamera::setPerspective()` -> `set_current_projection(proj_mat)` | `proj_mat` after perspective construction | Camera setup; normal main path comes through `display_update_camera()` -> `LLViewerWindow::setup3DRender()` | replace current | `SOURCE-PROVEN` |
| `gGLModelView` | `LLViewerCamera::setPerspective()` -> `set_current_modelview(modelview)` | constructed camera model-view | Only when `!for_selection && mZoomFactor == 1.f`; ordinary visible main view satisfies this bounded path | replace current | `SOURCE-PROVEN` |
| `gGLLastModelView` | `LLPipeline::renderDeferredLighting()` tail | `gGLModelView[i]` for all 16 elements | End of completed 3D scene after `screen_target->flush()`, guarded by `!gCubeSnapshot` | advance history | `SOURCE-PROVEN` |
| `gGLLastProjection` | same | `gGLProjection[i]` | same | advance history | `SOURCE-PROVEN` |
| `gGLModelView` | `LLPipeline::generateSunShadow()` | shadow `view[j]` / `view[i+4]` | Sun/spot shadow rendering | temporary replace | `SOURCE-PROVEN` |
| `gGLProjection` | `LLPipeline::generateSunShadow()` | shadow `proj[j]` / `proj[i+4]` | Sun/spot shadow rendering | temporary replace | `SOURCE-PROVEN` |
| `gGLLastModelView` | `LLPipeline::generateSunShadow()` -> `set_last_modelview(...)` | `mShadowModelview[...]` | Installs prior shadow-view history while rendering a shadow view | temporary replace | `SOURCE-PROVEN` |
| `gGLLastProjection` | same | `mShadowProjection[...]` | same | temporary replace | `SOURCE-PROVEN` |
| `mShadowModelview[]` | `LLPipeline::generateSunShadow()` | just-computed shadow `view[...]` | After prior shadow history has been installed into shared last slot | advance auxiliary shadow history | `SOURCE-PROVEN` |
| `mShadowProjection[]` | same | just-computed shadow `proj[...]` | same | advance auxiliary shadow history | `SOURCE-PROVEN` |
| `gGLModelView` | `LLPipeline::generateSunShadow()` teardown | saved pre-shadow current model-view, unless `CameraOffset`; `view[1]` if `CameraOffset` | Shadow completion | restore, or deliberate replacement under `CameraOffset` | `SOURCE-PROVEN` |
| `gGLProjection` | same | saved pre-shadow current projection, unless `CameraOffset`; `proj[1]` if `CameraOffset` | Shadow completion | restore, or deliberate replacement under `CameraOffset` | `SOURCE-PROVEN` |
| `gGLLastModelView` | `LLPipeline::generateSunShadow()` teardown | local `last_modelview` saved before shadow work | Shadow completion | restore | `SOURCE-PROVEN` |
| `gGLLastProjection` | same | local `last_projection` | Shadow completion | restore | `SOURCE-PROVEN` |
| `gGLDeltaModelView` | `LLPipeline::renderGeomDeferred()` | `get_current_modelview() * inverse(get_last_modelview())` | Any call passed exactly `LLViewerCamera::getInstance()`; includes the normal main G-buffer entry and can include cube-face auxiliary rendering that reuses the singleton | derive | `SOURCE-PROVEN` |
| `gGLInverseDeltaModelView` | same | `inverse(gGLDeltaModelView)` | same | derive | `SOURCE-PROVEN` |
| `gGLModelView` | `render_ui()` | `glm::make_mat4(gGLLastModelView)` | Non-snapshot UI/finalization wrapper after main scene | temporary replace | `SOURCE-PROVEN` |
| `gGLModelView` | `render_ui()` teardown | local `saved_view` | End of non-snapshot UI wrapper | restore | `SOURCE-PROVEN` |

No material Firestorm initialization writer for `gGLLastModelView`, `gGLLastProjection`, or the two delta matrices was established before their first semantic use. That absence is treated as a first-frame validity question rather than silently assigning a usable identity.

## Reader / Consumer Map

| State | Reader | Stage / context | Use | Confidence |
|---|---|---|---|---|
| `gGLModelView` | `LLPipeline::renderGeomDeferred()` via `get_current_modelview()` | Main deferred-geometry entry when camera pointer is singleton viewer camera | Current operand of temporal delta | `SOURCE-PROVEN` |
| `gGLLastModelView` | same via `get_last_modelview()` | same | Historical operand of temporal delta | `SOURCE-PROVEN` |
| `gGLModelView`, `gGLProjection` | `LLPipeline::renderDeferredLighting()` tail | End of 3D scene | Source values copied into `gGLLast*` | `SOURCE-PROVEN` |
| current + last model/projection | `LLPipeline::generateSunShadow()` | Pre-main shadow work | Saves global values so shadow-specific substitutions can be undone | `SOURCE-PROVEN` |
| `gGLLastModelView` | `render_ui()` | After normal scene completion, before ordinary UI completion | Loaded as temporary current model-view when `!gSnapshot` | `SOURCE-PROVEN` |
| current model/projection | `LLViewerCamera::updateFrustumPlanes()` | Camera/frustum update | `glm::unProject` inputs for frustum reconstruction | `SOURCE-PROVEN` |
| `gGLDeltaModelView` | `LLPipeline::bindDeferredShader()` | Deferred shader binding | Uploaded to `LLShaderMgr::MODELVIEW_DELTA_MATRIX` | `SOURCE-PROVEN` |
| `gGLInverseDeltaModelView` | same | Deferred shader binding | Uploaded to `LLShaderMgr::INVERSE_MODELVIEW_DELTA_MATRIX` | `SOURCE-PROVEN` |
| shader `inv_modelview_delta` | `class3/deferred/screenSpaceReflUtil.glsl::traceScreenRay()` | SSR ray tracing | Multiplies current position and reflected point before comparing/sampling against `sceneMap` / `sceneDepth`; shader comment says this aligns them to the scene-map/depth coordinate frame | `SOURCE-PROVEN` |
| shader `modelview_delta` | `screenSpaceReflUtil.glsl` | SSR utility declaration | Declared and documented as last-camera-space -> current-camera-space; no mathematical use of the forward uniform was established in this specific utility body | declaration `SOURCE-PROVEN`; concrete use here not established |
| `gGLLastProjection` | `generateSunShadow()` via `get_last_projection()` | Shadow setup | Saved, temporarily replaced by per-shadow projection history, then restored | `SOURCE-PROVEN` |

Deferred upload source:

- `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `bindDeferredShader(...)`
- Permalink: `https://github.com/FirestormViewer/phoenix-firestorm/blob/3e20e83b3ea01bb5ae3156d301d0d76ca88dd294/indra/newview/pipeline.cpp`

Concrete shader consumer:

- `indra/newview/app_settings/shaders/class3/deferred/screenSpaceReflUtil.glsl`
- Function: `traceScreenRay(...)`
- Permalink: `https://github.com/FirestormViewer/phoenix-firestorm/blob/3e20e83b3ea01bb5ae3156d301d0d76ca88dd294/indra/newview/app_settings/shaders/class3/deferred/screenSpaceReflUtil.glsl`

## Normal-Main Advancement

### 1. Is there a source-proven normal-main history advancement boundary?

Yes. `SOURCE-PROVEN`.

### 2. Where is it?

At the tail of `LLPipeline::renderDeferredLighting()` in `indra/newview/pipeline.cpp`, after `screen_target->flush()` and inside `if (!gCubeSnapshot)`.

The source directly loops across all 16 elements and performs:

```text
gGLLastModelView[i]  = gGLModelView[i]
gGLLastProjection[i] = gGLProjection[i]
```

The adjacent implementation comment labels this point the end of the 3D scene render and states that the copied matrices are for off-by-one-frame effects in the next frame.

### 3. What is copied/updated?

- source `gGLModelView` -> destination `gGLLastModelView`
- source `gGLProjection` -> destination `gGLLastProjection`

No swap is performed. The current slots remain current helper values; the last slots are overwritten by copies.

### 4. When does it occur?

For the accepted normal deferred frame sequence, it occurs after G-buffer completion, deferred lighting, and the post-deferred scene work contained in `renderDeferredLighting()`, at the function's final screen-target flush, before `display()` later enters `render_ui()`.

Accepted `FS-FRAME-001` establishes that auxiliary/probe/shadow work can occur before the main G-buffer, that the main G-buffer is populated by `deferredScreen` + `renderGeomDeferred()`, and that `renderDeferredLighting()` follows G-buffer completion.

### 5. What does the resulting history represent?

For an ordinary completed non-cube visible main scene whose current helper matrices still represent its main camera at this boundary, the newly written `gGLLastModelView`/`gGLLastProjection` are copies of that completed scene's current helper matrices.

Therefore, at the next ordinary main `renderGeomDeferred()` entry, before the next history advance, `gGLLastModelView` is source-proven to have been produced by the previous completed normal non-cube 3D scene's `renderDeferredLighting()` tail.

**Explicit answer to the central identity question:** at the point where normal main-view `renderGeomDeferred()` consumes `gGLLastModelView`, the value was produced by the preceding completed non-cube normal 3D scene's end-of-`renderDeferredLighting()` copy, subject to the conditions below. This is `SOURCE-PROVEN` for steady-state successive normal frames.

### 6. What conditions affect it?

- `gCubeSnapshot`: the advance is skipped when true. `SOURCE-PROVEN`.
- `renderDeferredLighting()` must execute through its tail. The function has an early `!sCull` return before the tail; a path that does not reach the tail does not perform this copy. `SOURCE-PROVEN` for control flow.
- The accepted normal visible deferred path calls `renderDeferredLighting()` after G-buffer completion. The audit does not generalize the once-per-frame statement to disconnected, startup, snapshot, non-rendering, or other non-normal paths.
- `CameraOffset`: shadow teardown restores saved current matrices only when `!CameraOffset`; otherwise it leaves `view[1]`/`proj[1]` as current helper state. This can change the value later consumed/copied without changing the history-copy mechanism itself. `SOURCE-PROVEN`.
- `LLViewerCamera::setPerspective()` writes current model-view only when `!for_selection && mZoomFactor == 1.f`; tiled/zoomed snapshot behavior is outside the ordinary visible-main scope. `SOURCE-PROVEN`.

## Auxiliary Interaction

### Shadow path: save -> substitute -> advance shadow-local history -> restore

`LLPipeline::generateSunShadow()` materially reuses the same global current/last helper slots.

```text
save:
    last_modelview   = get_last_modelview()
    last_projection  = get_last_projection()
    saved_view       = get_current_modelview()
    saved_proj       = get_current_projection()

for each applicable shadow view:
    set_current_modelview(shadow view)
    set_current_projection(shadow projection)
    set_last_modelview(mShadowModelview[index])
    set_last_projection(mShadowProjection[index])

    mShadowModelview[index]  = current shadow view
    mShadowProjection[index] = current shadow projection

teardown:
    if (!CameraOffset):
        set_current_modelview(saved_view)
        set_current_projection(saved_proj)
    else:
        set_current_modelview(view[1])
        set_current_projection(proj[1])

    set_last_modelview(last_modelview)
    set_last_projection(last_projection)
```

Source:

- `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `generateSunShadow(LLCamera& camera)`
- Members: `mShadowModelview[6]`, `mShadowProjection[6]`

Interpretation:

- The writes of `mShadow*` into `gGLLast*` are **temporary replacement**, not normal-main history advancement.
- The writes back from local `last_*` are **restoration**, not advancement.
- The per-shadow `mShadow* = current shadow matrix` assignments are a distinct **auxiliary shadow-history advancement**.
- The global `gGLLast*` values saved before shadow work are restored at the shown teardown, so ordinary shadow work does not permanently replace the normal last-matrix history.
- Current-matrix restoration is conditional on `CameraOffset`; last-matrix restoration is unconditional at that teardown.

Accepted `FS-FRAME-001` places sun-shadow generation before the ordinary main G-buffer, so this save/substitute/restore sequence is material to what the next main delta computation observes.

### Cube-face auxiliary rendering: shared delta writer, not history-advance source

`display_cube_face()` is a simplified auxiliary display path and calls:

```text
gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance())
...
gPipeline.renderDeferredLighting()
```

Because `renderGeomDeferred()` gates delta construction only on pointer identity (`&camera == LLViewerCamera::getInstance()`), an auxiliary cube-face pass that reuses the singleton viewer camera can derive and overwrite `gGLDeltaModelView` / `gGLInverseDeltaModelView`.

This does **not** make that write normal-main history advancement. The end-of-`renderDeferredLighting()` copy is separately guarded by `!gCubeSnapshot`, so cube-snapshot rendering does not advance `gGLLastModelView`/`gGLLastProjection` at that boundary.

For the accepted ordinary frame order, probe/auxiliary work precedes the main G-buffer, and the later ordinary main `renderGeomDeferred()` recomputes the delta before normal deferred consumers use it. Thus the final normal-main delta is established by the normal-main call, not merely by whichever invocation wrote the shared globals most recently before that call.

### Post-scene UI: `gGLLastModelView` is already same-frame history

After the main scene, `render_ui()` does:

```text
saved_view = get_current_modelview()
if (!gSnapshot):
    gGL.loadMatrix(gGLLastModelView)
    set_current_modelview(glm::make_mat4(gGLLastModelView))
...
if (!gSnapshot):
    set_current_modelview(saved_view)
```

This is a temporary replacement/restoration of **current model-view only**. It does not advance history.

Critically, the normal non-cube `renderDeferredLighting()` tail has already advanced `gGLLastModelView` before `render_ui()` is called. Therefore, during ordinary Frame N `render_ui()`, the `gGLLastModelView` loaded here is Frame N's just-copied scene matrix, not Frame N-1's matrix.

This is direct evidence that the temporal meaning of `gGLLastModelView` depends on execution point.

## Delta Construction

### Exact mathematical construction

Source:

- `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `renderGeomDeferred(LLCamera& camera, bool do_occlusion)`

Condition:

```text
&camera == LLViewerCamera::getInstance()
```

Operands:

```text
M_last = get_last_modelview()
M_cur  = get_current_modelview()
```

Construction:

```text
M_delta = inverse(M_last)
M_delta = M_cur * M_delta
M_delta_inv = inverse(M_delta)

gGLDeltaModelView        = M_delta
gGLInverseDeltaModelView = M_delta_inv
```

Equivalent formula:

```text
gGLDeltaModelView
    = M_current * inverse(M_last)

gGLInverseDeltaModelView
    = inverse(M_current * inverse(M_last))
```

### Mathematical meaning versus temporal meaning

The multiplication order is `current * inverse(last)`. The implementation comment states the goal is a matrix from the last frame's camera space to the current frame's camera space.

That comment alone would not prove that `M_last` actually belongs to the immediately previous visible frame. The separate end-of-scene writer trace supplies that temporal identity for successive ordinary non-cube normal frames.

Thus, at the normal Frame N main deferred entry after a completed Frame N-1:

```text
M_last = main model-view copied at Frame N-1 renderDeferredLighting() tail
M_cur  = main model-view established for Frame N
```

and the resulting delta is source-backed as:

```text
Frame N-1 camera space -> Frame N camera space
```

The inverse is:

```text
Frame N camera space -> Frame N-1 camera space
```

### Update point and lifetime

The delta is derived at `renderGeomDeferred()` entry, not at the history-advance boundary. It persists in the two global `glm::mat4` values until another qualifying `renderGeomDeferred()` overwrites it.

The pointer-identity condition is not a proof that every qualifying call is ordinary main rendering: `display_cube_face()` also passes the singleton viewer camera. Context, not the shared camera pointer alone, is required to classify the write.

### Upload and concrete use

`LLPipeline::bindDeferredShader()` uploads:

```text
gGLDeltaModelView        -> MODELVIEW_DELTA_MATRIX
gGLInverseDeltaModelView -> INVERSE_MODELVIEW_DELTA_MATRIX
```

`class3/deferred/screenSpaceReflUtil.glsl` declares `modelview_delta` and `inv_modelview_delta`. In `traceScreenRay()`, the shader explicitly applies `inv_modelview_delta` to both the current position and reflected point before ray marching against `sceneMap` and `sceneDepth`. The source comment states this transforms them into the same coordinate frame as those scene resources.

This establishes a concrete mathematical consumer of the inverse temporal transform. It does not by itself establish every deferred shader that may receive the reserved uniform slots.

## Projection History

Projection history is only partially symmetrical with model-view history.

### Proven symmetry

The following operations are symmetrical:

- normal camera setup writes current projection through `set_current_projection()`;
- the end-of-scene advance copies `gGLProjection` to `gGLLastProjection` in the same loop that advances model-view history;
- shadow generation saves `get_last_projection()` alongside `get_last_modelview()`;
- shadow rendering temporarily installs `mShadowProjection[...]` through `set_last_projection()`;
- shadow teardown restores the saved global last projection;
- current projection is saved/replaced/restored around shadow work alongside current model-view, subject to the same `CameraOffset` current-state exception.

### Proven asymmetry

The normal-main delta construction reads:

```text
get_last_modelview()
get_current_modelview()
```

It does **not** read `get_last_projection()` and does not derive a `gGLDeltaProjection` equivalent in the traced block.

`render_ui()` also temporarily substitutes `gGLLastModelView` as current model-view without an analogous `gGLLastProjection` substitution in that wrapper.

No normal-main temporal shader consumer of `gGLLastProjection` was established in this bounded trace. This is not a repository-wide assertion that no such reader exists; it is a scoped result: projection history is source-proven to be advanced and preserved, but the concrete normal-main temporal consumer identified here is model-view delta/SSR, not a projection-history delta.

**Projection-history conclusion:** storage advancement and shadow substitution/restoration are symmetrical with model-view; proven normal-main temporal consumption is not.

## First-Frame / Reset Behavior

### Explicit declarations do not establish valid temporal history

`indra/llrender/llrender.cpp` defines:

```text
F32 gGLModelView[16];
F32 gGLLastModelView[16];
F32 gGLLastProjection[16];
F32 gGLProjection[16];
glm::mat4 gGLDeltaModelView;
glm::mat4 gGLInverseDeltaModelView;
```

There is no explicit Firestorm initializer at these declarations that assigns a valid prior-camera matrix or marks history valid.

The C++ language's static-storage initialization rules are not equivalent to a Firestorm semantic guarantee that an initial matrix is a usable previous camera transform, so this audit does not promote language-level zero/default initialization into a valid temporal identity.

### Main delta construction has no local validity guard

The singleton-camera block in `renderGeomDeferred()` directly obtains `last_modelview`, calls `glm::inverse(last_modelview)`, and derives the delta. No local `history_valid`, frame-count, or equivalent guard surrounds that calculation in the traced block.

### What remains unresolved

`UNRESOLVED`:

- what exact earlier startup/render event, if any, guarantees a valid `gGLLastModelView` before the first ordinary visible main `renderGeomDeferred()` that matters;
- whether a renderer/context reset explicitly invalidates or reseeds these history slots elsewhere;
- whether teleport/scene transitions have a dedicated temporal-history invalidation mechanism elsewhere.

No such mechanism was established in the material writer/consumer paths traced for this audit. The steady-state Frame N -> Frame N+1 identity is proven independently of this first-frame question.

## Two-Frame Timeline

```text
PRIOR COMPLETED FRAME N-1

normal main camera current helpers represent Frame N-1
        |
        v
LLPipeline::renderDeferredLighting() tail
        |
        | screen_target->flush()
        | !gCubeSnapshot
        v
gGLLastModelView  <- gGLModelView(N-1)
gGLLastProjection <- gGLProjection(N-1)
        |
        +-------------------------------------------+
                                                    |
FRAME N                                             |
                                                    |
early auxiliary cube/probe work, if present         |
  may touch shared current/delta state               |
        |                                           |
        v                                           |
normal display_update_camera()                      |
  -> LLViewerWindow::setup3DRender()                 |
  -> LLViewerCamera::setPerspective()                |
        |                                           |
        +--> gGLProjection = Frame N current projection
        +--> gGLModelView  = Frame N current model-view
             [ordinary !selection, zoomFactor == 1]
        |
        v
sun-shadow work before the main G-buffer
  generateSunShadow()
    save current + last
    install shadow current + shadow last
    advance mShadowModelview/projection[]
    restore global last = Frame N-1 ----------------+
    restore current main helpers unless CameraOffset
        |
        v
main deferredScreen bind/clear
        |
        v
LLPipeline::renderGeomDeferred(*LLViewerCamera::getInstance())
        |
        | reads:
        |   last = Frame N-1 main model-view
        |   cur  = Frame N main model-view
        v
gGLDeltaModelView = cur * inverse(last)
gGLInverseDeltaModelView = inverse(delta)
        |
        v
bindDeferredShader()
        |
        +--> modelview_delta
        +--> inv_modelview_delta
                 |
                 v
        SSR utility uses inverse delta to align
        current ray data with sceneMap/sceneDepth frame
        |
        v
remaining main 3D scene / post-deferred work
        |
        v
LLPipeline::renderDeferredLighting() tail
        |
        | history advancement
        v
gGLLastModelView  <- Frame N current model-view
gGLLastProjection <- Frame N current projection
        |
        | from here onward "last" == Frame N
        v
render_ui()
  save current model-view
  temporarily current <- gGLLastModelView(Frame N)
  restore saved current
        |
        v
swap / frame completes

FRAME N+1

pre-main shadows may temporarily substitute shared history,
but restore gGLLastModelView = Frame N
        |
        v
normal main camera setup establishes Frame N+1 current
        |
        v
renderGeomDeferred(main viewer camera)
  last = Frame N
  cur  = Frame N+1
        |
        v
delta = Frame N camera space -> Frame N+1 camera space
```

Unresolved edge in this timeline: the seed before the first valid steady-state pair is not source-proven by this audit.

## Findings

### Finding 1 — Normal non-cube history advancement is an explicit end-of-scene copy

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `renderDeferredLighting()`
- Symbols: `gGLModelView`, `gGLProjection`, `gGLLastModelView`, `gGLLastProjection`, `gCubeSnapshot`
- Permalink: `https://github.com/FirestormViewer/phoenix-firestorm/blob/3e20e83b3ea01bb5ae3156d301d0d76ca88dd294/indra/newview/pipeline.cpp`

**What the source proves:**

After `screen_target->flush()`, a `!gCubeSnapshot` block copies all 16 current model-view and projection elements into the corresponding last slots. This is history advancement, not a swap and not a restoration.

### Finding 2 — At the next ordinary main deferred entry, `gGLLastModelView` was produced by the previous completed normal non-cube scene

**Confidence:** `SOURCE-PROVEN` for steady-state successive normal frames

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Functions: `renderDeferredLighting()`, `renderGeomDeferred()`
- Accepted ordering: `FS-FRAME-001.md`

**What the source proves:**

The previous scene advances the last slot at its end; intervening shadow work saves and restores that global last slot; then the next normal main `renderGeomDeferred()` reads it. This closes the writer-identity question left unresolved by `FS-CAMERA-001` for the ordinary steady-state path.

### Finding 3 — The temporal meaning of `gGLLastModelView` changes at the advancement boundary

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp` — `renderDeferredLighting()`
- Path: `indra/newview/llviewerdisplay.cpp` — `render_ui()`

**What the source proves:**

Before Frame N's end-of-scene copy, the slot can represent Frame N-1. After the copy, it represents Frame N. `render_ui()` subsequently loads that already-advanced Frame N value as a temporary current model-view. Therefore `gGLLastModelView` cannot be semantically labeled “previous visible frame” without specifying the execution point.

### Finding 4 — Delta construction occurs in `renderGeomDeferred()`, not `updateCull()`

**Confidence:** `SOURCE-PROVEN`; explicit contradiction with accepted prior record

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `renderGeomDeferred(LLCamera& camera, bool do_occlusion)`
- Symbols: `gGLDeltaModelView`, `gGLInverseDeltaModelView`
- Prior conflicting record: `FS-CAMERA-001.md`, Finding 16 / matrix inventory, which attributes this computation to `updateCull()`

**What the source proves:**

The pinned source places the singleton-camera test, reads of current/last model-view, `current * inverse(last)` arithmetic, inverse calculation, and assignments to both delta globals inside `LLPipeline::renderGeomDeferred()`.

The accepted prior record's location claim is preserved as conflicting evidence; this record does not edit it. The current pinned-source location is `renderGeomDeferred()`.

### Finding 5 — Delta construction is mathematically exact and temporally justified by a separate writer trace

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Function: `renderGeomDeferred()`

**What the source proves:**

The formula is `M_current * inverse(M_last)`, followed by inversion for the reverse transform. The source comment supplies intended camera-space direction; the separate end-of-scene advancement trace proves the immediately preceding normal-frame identity for `M_last` in steady state.

### Finding 6 — Shadow rendering temporarily repurposes both current and last helper slots and restores normal last history

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `generateSunShadow(LLCamera& camera)`
- Members/symbols: `mShadowModelview[]`, `mShadowProjection[]`, current/last get/set helpers

**What the source proves:**

Shadow generation saves global current and last matrices, installs shadow current matrices and per-shadow historical matrices, advances the per-shadow arrays, and restores the saved global last values. These operations are auxiliary substitution/restoration, not normal-main history advancement.

### Finding 7 — `CameraOffset` is an explicit current-state restoration exception

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `generateSunShadow()`
- Setting/state: `LLPipeline::CameraOffset`

**What the source proves:**

At shadow teardown, saved current model-view/projection are restored only when `!CameraOffset`; otherwise `view[1]`/`proj[1]` are installed. The saved global last-model-view/projection are restored afterward in either branch shown. Thus last-history preservation and current-camera restoration have different conditions.

### Finding 8 — The delta globals are shared derived state and can be overwritten by auxiliary cube-face rendering

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display_cube_face()`
- Path: `indra/newview/pipeline.cpp`
- Function: `renderGeomDeferred()`

**What the source proves:**

`display_cube_face()` calls `renderGeomDeferred(*LLViewerCamera::getInstance())`. The delta writer's condition is viewer-camera pointer identity, not an explicit “normal main frame” flag. Therefore an auxiliary cube-face invocation can write the same delta globals. Normal-main classification must come from call order/context; the later normal main `renderGeomDeferred()` re-derives the value for its own pass.

### Finding 9 — Cube snapshots are prevented from advancing the normal global last slots at the end-of-scene boundary

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Function: `renderDeferredLighting()`
- Symbol: `gCubeSnapshot`

**What the source proves:**

The direct `gGLLastModelView` / `gGLLastProjection` copy is inside `if (!gCubeSnapshot)`. Cube rendering can interact with shared current/delta infrastructure but does not advance the normal last slots through this copy when `gCubeSnapshot` is true.

### Finding 10 — Deferred binding uploads both derived model-view temporal matrices

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Function: `bindDeferredShader(...)`
- Uniform slots: `LLShaderMgr::MODELVIEW_DELTA_MATRIX`, `LLShaderMgr::INVERSE_MODELVIEW_DELTA_MATRIX`

**What the source proves:**

`bindDeferredShader()` directly uploads `gGLDeltaModelView` and `gGLInverseDeltaModelView` with `uniformMatrix4fv()`.

### Finding 11 — SSR concretely consumes the inverse temporal transform

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/app_settings/shaders/class3/deferred/screenSpaceReflUtil.glsl`
- Function: `traceScreenRay()`
- Uniform: `inv_modelview_delta`

**What the source proves:**

The shader multiplies both the current position and reflected point by `inv_modelview_delta` before ray marching and explicitly states that this puts them in the same coordinate frame as `sceneMap` and `sceneDepth`. This is a concrete mathematical use, not an inference from the shader filename.

### Finding 12 — Projection history is advanced and shadow-preserved, but no equivalent normal-main projection delta is established

**Confidence:** `SOURCE-PROVEN` for the observed asymmetry; exhaustive absence of all other projection-history consumers is not claimed

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Functions: `renderDeferredLighting()`, `generateSunShadow()`, `renderGeomDeferred()`
- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `render_ui()`

**What the source proves:**

`gGLLastProjection` is advanced and shadow-substituted/restored alongside model-view, but `renderGeomDeferred()` derives its temporal delta only from model-view. The UI wrapper also substitutes only last model-view. The traced normal temporal mechanism is therefore not fully symmetrical.

### Finding 13 — No Firestorm semantic validity guard is present at the main delta-consumption site

**Confidence:** `SOURCE-PROVEN` for the local consumer; startup validity remains `UNRESOLVED`

**Source:**

- Path: `indra/llrender/llrender.cpp` — global definitions
- Path: `indra/newview/pipeline.cpp` — `renderGeomDeferred()`

**What the source proves:**

The global temporal arrays/deltas have no explicit semantic initializer at declaration, and the main delta block in `renderGeomDeferred()` directly inverts `get_last_modelview()` without a local history-valid test. This does not prove a startup bug; it means this bounded trace does not establish the first valid-history seed.

## Unresolved Questions

1. **First valid history seed.** What source event guarantees a semantically valid `gGLLastModelView` before the first ordinary visible main `renderGeomDeferred()` that relies on it? This audit does not expand startup lifecycle far enough to answer it.
2. **Reset/invalidation behavior.** No explicit renderer-reset, context-recreation, teleport, or scene-transition invalidation/reseed operation for these globals was established in the material paths traced here. Whether one exists elsewhere remains `UNRESOLVED`.
3. **Projection-history consumers.** This audit proves advancement/preservation but does not claim a repository-wide absence of all consumers of `gGLLastProjection` outside the traced normal temporal mechanism.
4. **All deferred consumers.** `bindDeferredShader()` uploads both delta matrices broadly; this audit proves `screenSpaceReflUtil.glsl` as a concrete inverse-delta consumer but does not inventory every shader that may receive or use the reserved slots.

## Recommended Next Audit

- **Proposed task ID:** `FS-DEPTHSTATE-001`
- **Exact question:** Where, if anywhere, does Firestorm explicitly establish OpenGL depth-range and clip-control state for the normal Windows/OpenGL main-view context, and what source path guarantees the depth mapping consumed by deferred reconstruction?
- **Why the current evidence makes it useful:** this temporal trace reaches `screenSpaceReflUtil.glsl`, where current camera-space data is transformed into the frame of `sceneMap` / `sceneDepth`, but the correctness of reconstructing positions from that depth remains dependent on the viewer's actual OpenGL depth convention. The accepted camera audit establishes the projection/reconstruction path while leaving explicit depth-range/clip-control state unresolved. That is a bounded dependency exposed directly at the temporal consumer boundary.
- **Likely source starting points:** `indra/llwindow/llwindowwin32.cpp`, `indra/llrender/llgl.cpp`, `indra/llrender/llglheaders.h`, `indra/newview/llviewercamera.cpp`, `indra/llrender/llrender.cpp`, and `indra/newview/app_settings/shaders/class1/deferred/deferredUtil.glsl`.

## Handoff Summary

- Normal non-cube history advances explicitly at the tail of `LLPipeline::renderDeferredLighting()`.
- At the next ordinary main `renderGeomDeferred()`, `gGLLastModelView` was produced by the previous completed normal 3D scene's end-of-scene copy.
- `gGLLastModelView` is point-dependent: after Frame N's copy it already represents Frame N.
- Shadow work temporarily substitutes current/last globals, advances separate `mShadow*` history, then restores global last state.
- `CameraOffset` is a current-state restoration exception; it does not remove the shown global-last restoration.
- Delta construction is in `renderGeomDeferred()`, contradicting the accepted camera record's `updateCull()` location claim.
- The exact formula is `current * inverse(last)`; its inverse maps current camera space back to prior history space.
- `bindDeferredShader()` uploads both derived matrices.
- SSR concretely applies `inv_modelview_delta` to align current ray data with `sceneMap`/`sceneDepth` coordinates.
- Cube-face rendering can overwrite shared delta globals but is blocked from normal last-slot advancement by `gCubeSnapshot` at the copy boundary.
- Projection history advances/preserves symmetrically but has no proven equivalent normal-main delta in this trace.
- First valid-history seeding and reset invalidation remain unresolved.
- Recommended next audit: `FS-DEPTHSTATE-001`.
