# FS-DEPTHSTATE-001

## Question

What OpenGL depth-range, clip-control, comparison, clear, and related state defines Firestorm's normal main-view depth-space contract?

## Repository State

- Repository: `https://github.com/FirestormViewer/phoenix-firestorm`
- Branch: `master`
- Commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`
- Platform: Windows
- Renderer: OpenGL
- Render scope: normal visible-camera main-view rendering
- Accepted prior evidence:
  - `FS-FRAME-001.md`
  - `FS-GBUF-001.md`
  - `FS-POST-001.md`
  - `FS-CAMERA-001.md`
- Audit type: source analysis only. No runtime capture or experimentation is claimed.

The requested commit was obtained through the repository source interface and matched the requested SHA. No revision substitution was made.

Status vocabulary:

- `SOURCE-PROVEN` — the implementation directly establishes the stated relationship.
- `LIKELY` — the examined implementation strongly supports the statement, but a requested absence, lifetime edge, or repository-wide identity is not completely closed.
- `UNRESOLVED` — the requested value or relationship is not established by the audited source evidence.

## Executive Depth Contract

The normal visible `display()` render scope explicitly establishes Firestorm's tracked depth state as:

```text
depth test     = enabled
depth writes   = enabled
depth function = GL_LEQUAL
```

through `LLGLDepthTest gls_depth(GL_TRUE, GL_TRUE, GL_LEQUAL)`. `LLGLDepthTest` is an RAII state object: it emits `glEnable/glDisable(GL_DEPTH_TEST)`, `glDepthFunc`, and `glDepthMask` when tracked state differs, then restores the prior tracked values on destruction. Nested shadow, lighting, post, debug, and other pass-specific overrides therefore do not define the enclosing normal-main state unless a separate leak exists.

Accepted camera evidence establishes a standard finite perspective projection and deferred reconstruction using sampled depth `d`, `ndc.z = 2*d - 1`, then `inv_proj`. Accepted G-buffer evidence establishes that the native main deferred depth attachment is requested as `GL_DEPTH_COMPONENT24`.

The incomplete part of the source-only contract is the OpenGL window-depth mapping around those facts:

- No actual `glDepthRange`/`glDepthRangef` setter was established in the audited normal-main renderer path. `glDepthRangef` is declared/loaded as a function pointer, but loader presence is not a call.
- `glClipControl` is declared and loaded when supported, but no actual normal-main call was established.
- No actual `glClearDepth`/`glClearDepthf` setter was established in the audited renderer path.

Therefore Firestorm's source strongly supports conventional, non-reversed depth, but the complete numeric projection-to-stored-depth equivalence is **not source-proven from Firestorm alone** because depth-range, clip-depth mode, and clear-depth value remain context/default-state edges.

`LLRenderTarget::clear()` does source-prove that a target with depth ownership/attachment includes `GL_DEPTH_BUFFER_BIT` in its `glClear` mask. It does not set the depth clear value and does not force the depth write mask. For the normal G-buffer clear, the enclosing `display()` state has depth writes enabled, so the clear executes in a write-enabled depth state.

## State Inventory

| State | Source representation / API | Normal-main value | Established where | Lifetime | Confidence |
|---|---|---|---|---|---|
| Depth-test enable | `LLGLDepthTest` -> `glEnable/glDisable(GL_DEPTH_TEST)` | Enabled | `indra/newview/llviewerdisplay.cpp`, `display()` | Enclosing `display()` RAII scope; nested overrides restore | `SOURCE-PROVEN` |
| Depth comparison function | `LLGLDepthTest` -> `glDepthFunc` | `GL_LEQUAL` baseline | `indra/newview/llviewerdisplay.cpp`, `display()` | Enclosing `display()` RAII scope; nested overrides restore | `SOURCE-PROVEN` |
| Depth-write enable | `LLGLDepthTest` -> `glDepthMask` | Enabled baseline | `indra/newview/llviewerdisplay.cpp`, `display()` | Enclosing `display()` RAII scope; later lighting/post passes can scope-disable and restore | `SOURCE-PROVEN` |
| Depth range | `glDepthRange` / `glDepthRangef` | No Firestorm setter established; numeric mapping unresolved | `llgl.cpp` loader checked; high-risk render/context files checked; accepted camera audit reported repository-wide symbol search | If no setter exists, would be persistent context state; exact Firestorm-established value not proven | `UNRESOLVED` |
| Clip origin / clip depth mode | `glClipControl` | No Firestorm call established; origin/depth mode unresolved | `indra/llrender/llgl.cpp` declaration/load; normal render/context paths checked | If untouched, persistent context state; exact Firestorm-established mode not proven | `UNRESOLVED` |
| Depth clear value | `glClearDepth` / `glClearDepthf` | No Firestorm setter established; value unresolved | Renderer/context/init files checked | Persistent GL state if untouched; exact value not Firestorm-source-proven | `UNRESOLVED` |
| Main deferred clear mask | `LLRenderTarget::clear()` -> `glClear` | Color plus depth for `mUseDepth` target | `indra/llrender/llrendertarget.cpp`, `LLRenderTarget::clear()` | Per clear call | `SOURCE-PROVEN` |
| Main deferred depth format | `LLRenderTarget::allocateDepth()` | Requested `GL_DEPTH_COMPONENT24` | `indra/llrender/llrendertarget.cpp`; accepted `FS-GBUF-001` | Render-target allocation lifetime | `SOURCE-PROVEN` |
| Depth clamp | `LLGLEnable(GL_DEPTH_CLAMP)` | No normal-main enable established; explicit use found in shadow generation | `indra/newview/pipeline.cpp`, shadow-generation path | Scoped auxiliary override; RAII restores | Normal-main value `UNRESOLVED`; auxiliary override `SOURCE-PROVEN` |
| Projection depth convention | `LLViewerCamera::calcProjection()` / `glm::perspective` | Finite conventional-sign perspective coefficients | `indra/newview/llviewercamera.cpp`, `setPerspective()` / `calcProjection()`; accepted `FS-CAMERA-001` | Main camera projection scope | `SOURCE-PROVEN` |
| Shader depth reconstruction | `deferredUtil.glsl` | `ndc.z = sampled_depth * 2 - 1`; then `inv_proj` | `indra/newview/app_settings/shaders/class1/deferred/deferredUtil.glsl` | Deferred shader invocation | `SOURCE-PROVEN` |
| Custom/logarithmic main depth encoding | Vertex/fragment shaders; `gl_FragDepth` | No custom encoding established in representative normal diffuse/PBR opaque G-buffer shaders | `diffuseV/F.glsl`, `pbropaqueV/F.glsl` | Per shader | Overall main-path absence `LIKELY` |

## API Call Inventory

### Depth-range APIs

Symbols checked:

- `glDepthRange`
- `glDepthRangef`
- wrappers/aliases in the GL abstraction
- function-pointer declaration/loading

Findings:

1. `indra/llrender/llgl.cpp`
   - `glDepthRangef` is present as a function pointer and is loaded through the GL loader.
   - This is capability plumbing, not a depth-range state change.
   - No actual `glDepthRangef(...)` invocation was found in this file.
2. High-risk source scopes checked directly at the pinned commit:
   - `indra/llrender/llgl.cpp`
   - `indra/llrender/llrender.cpp`
   - `indra/llrender/llrendertarget.cpp`
   - `indra/newview/llviewerdisplay.cpp`
   - `indra/newview/llviewerwindow.cpp`
   - `indra/newview/pipeline.cpp`
   - `indra/llwindow/llwindowwin32.cpp`
   - no actual setter was found in those scopes.
3. Accepted `FS-CAMERA-001` records a repository-wide symbol search for `glDepthRange` / `glDepthRangef` that did not establish a normal-main setter.

**Absence confidence:** high for the normal Windows/OpenGL main-view path, but the stronger statement “Firestorm never calls a depth-range API anywhere in the repository” is not made here.

### Clip-control API

Symbols checked:

- `glClipControl`
- core/extension declaration/loading
- context capability/load path

Findings:

1. `indra/llrender/llglheaders.h` declares the function pointer.
2. `indra/llrender/llgl.cpp`, `LLGLManager` initialization, loads `glClipControl` when the GL version supports it.
3. No actual `glClipControl(...)` call was found in the inspected GL manager, Windows context, main display, viewer-window, pipeline, render-target, or renderer files.
4. Accepted `FS-CAMERA-001` likewise did not establish a normal-main clip-control call.

This proves loader/capability support exists. It does **not** by itself prove the active origin or clip-depth mode.

**Absence confidence:** high for the audited normal-main scope; exact active clip-control state remains `UNRESOLVED` without promoting an OpenGL API default to a Firestorm-specific fact.

### Depth-function and depth-write APIs

The relevant actual setters are centralized by `LLGLDepthTest`.

`indra/llrender/llgl.cpp` — `LLGLDepthTest::LLGLDepthTest(...)`:

- enables/disables `GL_DEPTH_TEST` when necessary;
- calls `glDepthFunc(depth_func)` when the tracked function changes;
- calls `glDepthMask(write_enabled)` when the tracked write state changes.

`LLGLDepthTest::~LLGLDepthTest()` restores the previous tracked enable/function/write values. Debug validation can query `GL_DEPTH_FUNC`, `GL_DEPTH_WRITEMASK`, and depth-test enable to catch divergence from tracked state.

`indra/newview/llviewerdisplay.cpp` — `display(...)`:

```text
LLGLDepthTest gls_depth(GL_TRUE, GL_TRUE, GL_LEQUAL)
```

This is the normal main-view baseline.

Important auxiliary/pass examples from `indra/newview/pipeline.cpp`:

- shadow generation scopes `LLGLDepthTest(GL_TRUE, GL_TRUE, GL_LESS)`;
- local/deferred lighting scopes commonly use depth test on with writes off, with the wrapper default function `GL_LEQUAL` unless another function is supplied;
- full-screen/post operations can scope `GL_ALWAYS` or disable depth testing;
- pathfinding X-ray debug scopes `GL_GREATER` with writes disabled.

Those inner objects restore the previous wrapper state when their scopes end.

### Depth-clear APIs

Symbols checked:

- `glClearDepth`
- `glClearDepthf`
- render-target clear abstraction

Findings:

1. `glClearDepthf` is declared/loaded by GL plumbing in `indra/llrender/llgl.cpp` but no actual setter call was found there.
2. No `glClearDepth`/`glClearDepthf` call was found in the directly inspected main renderer, viewer display/window, pipeline, render target, or Windows context files.
3. `LLRenderTarget::clear()` calls `glClear(...)`; it does not establish the clear-depth scalar.

**Result:** Firestorm source in the audited scope proves that depth is cleared, but does not prove which scalar value is loaded into the depth buffer by that clear.

### Render-target clear call

`indra/llrender/llrendertarget.cpp` — `LLRenderTarget::clear(U32 mask_in)`:

```text
mask starts with GL_COLOR_BUFFER_BIT
if mUseDepth: add GL_DEPTH_BUFFER_BIT
glClear(mask & mask_in)
```

For an FBO target it clears directly. The fallback/default-framebuffer branch additionally scopes scissor to the target rectangle, but still uses `glClear`; it does not alter the clear-depth value, depth function, or depth write state.

For the normal deferred target, accepted G-buffer evidence establishes `mUseDepth`/native depth attachment and the main display calls `clear()` with the default mask. Therefore its clear mask includes `GL_DEPTH_BUFFER_BIT`.

### Depth clamp and polygon offset

`indra/newview/pipeline.cpp` shadow generation contains:

```text
LLGLEnable clamp_depth(depth_clamp ? GL_DEPTH_CLAMP : 0)
LLGLDepthTest depth_test(GL_TRUE, GL_TRUE, GL_LESS)
```

This is an auxiliary shadow-camera override, not the normal visible-camera depth contract. It is scoped by RAII.

`GL_GREATER` plus `glPolygonOffset(...)` was found in pathfinding X-ray/debug rendering. This is explicitly a debug visualization path and is not evidence of reversed-Z main rendering.

Polygon offset also occurs in specialized raster passes, but no evidence was found that it changes the global interpretation of the main native scene-depth resource. Those calls are therefore excluded from the core contract.

## Initialization Path

The relevant Windows/OpenGL path is:

```text
LLWindowWin32 context creation
    |
    | wglCreateContextAttribsARB / createSharedContext()
    v
versioned Windows OpenGL context made current
    |
    v
gGLManager.initGL()
    |
    | load GL entry points / capabilities
    | including glDepthRangef, glClearDepthf as supported
    | and glClipControl when version permits
    v
LLGLManager::initGLStates()
    |
    v
LLGLState::initClass()
    |
    | initializes wrapper state bookkeeping for general GL state
    | does not explicitly call depth-range, clip-control, or clear-depth setters
    v
viewer rendering
    |
    v
display()
    |
    | LLGLDepthTest(GL_TRUE, GL_TRUE, GL_LEQUAL)
    v
normal visible main-view baseline
```

`LLGLDepthTest` has static tracked initial values corresponding to the documented OpenGL defaults (`depth test disabled`, function `GL_LESS`, writes enabled). Those comments/initializers establish how Firestorm's wrapper begins bookkeeping; they are not equivalent to Firestorm actively issuing the GL calls or proving the live driver state after arbitrary prior work.

The key global-to-frame transition is therefore not `initGLStates()` setting a complete depth-space convention. The decisive Firestorm-issued normal-frame state is the `display()` RAII depth-test object, which explicitly establishes test enable, compare function, and write enable. Depth range, clip-control mode, and clear scalar remain outside that explicit frame setup.

## Main-View State Timeline

```text
Windows OpenGL context creation
    |
    | no depth-range / clip-control / clear-depth setter established
    v
GL manager initialization
    |
    | entry points loaded
    | wrapper bookkeeping initialized
    | no complete explicit depth-space default established
    v
normal display()
    |
    | LLGLDepthTest(GL_TRUE, GL_TRUE, GL_LEQUAL)
    | SOURCE-PROVEN baseline:
    |   test=ON, writes=ON, func=LEQUAL
    v
main-view setup3DRender / camera projection
    |
    | finite perspective projection
    | near = viewer-camera near
    | active normal far = MAX_FAR_CLIP*2
    v
pre-main auxiliary passes, when enabled
    |
    | shadows can temporarily use LESS + DEPTH_CLAMP
    | other passes can temporarily alter depth state
    | RAII restores enclosing state
    v
main deferredScreen.bindTarget()
    |
    | changes FBO/viewport; no depth-space remapping established
    v
deferredScreen.clear()
    |
    | GL_DEPTH_BUFFER_BIT included because target uses depth
    | enclosing writes=ON
    | clear scalar remains UNRESOLVED
    v
renderGeomDeferred(main camera)
    |
    | baseline test=ON, writes=ON, func=LEQUAL
    | geometry shaders write ordinary gl_Position
    | native depth attachment receives passing fragment depth
    v
deferredScreen.flush()
    |
    | accepted boundary: main G-buffer/deferred depth complete
    v
renderDeferredLighting()
    |
    | samples native depth
    | many lighting draws scope-disable depth writes / depth test as needed
    | reconstruction uses sampled d -> 2*d-1 -> inv_proj
    v
renderGeomPostDeferred()
    |
    | shares/evolves same native scene depth where passes write depth
    | pass-specific depth states are scoped
    v
post/finalize
    |
    | full-screen passes often disable/override depth locally
    v
exit display()
    |
    | enclosing LLGLDepthTest restores the pre-display tracked state
```

## Projection-to-Depth Mapping

Accepted prior evidence establishes the main perspective projection and deferred reconstruction. This audit adds the state around them.

| Edge | Status | Evidence / limitation |
|---|---|---|
| View/eye-space position -> projected clip-space `gl_Position` | `SOURCE-PROVEN` | Main diffuse and PBR opaque vertex shaders multiply by `projection_matrix` or `modelview_projection_matrix`; accepted camera audit establishes the active perspective matrix. |
| Projection coefficients encode near/far with conventional finite perspective sign convention | `SOURCE-PROVEN` | `calcProjection()` has `(far+near)/(near-far)`, `2*far*near/(near-far)`, and `-1` perspective term; normal path uses `glm::perspective`. |
| Clip-space z/w -> NDC z | `SOURCE-PROVEN` for use of ordinary OpenGL `gl_Position`; no Firestorm custom divide path exists | This is fixed OpenGL rasterization behavior rather than mutable depth-range state. Firestorm does not replace the perspective divide. |
| NDC z -> window/depth-range-mapped z | `UNRESOLVED` | No actual `glDepthRange*` setter established; no Firestorm-specific numeric range is source-proven. |
| Clip depth convention affecting NDC/window mapping | `UNRESOLVED` | `glClipControl` is loaded but no actual normal-main call established; active depth mode is not explicitly fixed by audited Firestorm code. |
| Window depth -> depth-test comparison | `SOURCE-PROVEN` | Normal `display()` baseline is depth test enabled with `GL_LEQUAL`. |
| Passing fragment depth -> native main depth attachment | `SOURCE-PROVEN` | Depth writes enabled in normal baseline; accepted G-buffer evidence identifies `mMainRT.deferredScreen.mDepth`, requested as `GL_DEPTH_COMPONENT24`. |
| Clear operation -> depth attachment | `SOURCE-PROVEN` | `LLRenderTarget::clear()` includes `GL_DEPTH_BUFFER_BIT` when `mUseDepth`; main deferred target has depth. |
| Clear operation -> specific numeric depth value | `UNRESOLVED` | No actual `glClearDepth*` setter established in audited scope. |
| Native depth attachment -> shader depth sample `d` | `SOURCE-PROVEN` | Accepted deferred/G-buffer evidence establishes the depth texture binding and sampling path. |
| Sampled `d` -> reconstructed NDC z | `SOURCE-PROVEN` | `deferredUtil.glsl`: `d*2-1`. |
| Reconstructed NDC -> eye/view position | `SOURCE-PROVEN` | `deferredUtil.glsl` applies `inv_proj` and divides by w. |

The most important unresolved edge is numeric compatibility between the window-depth value written by OpenGL and the shader's assumption that sampled depth can be mapped back to NDC by `2*d-1`. That compatibility is what the usual `[0,1]` depth range plus negative-one-to-one clip-depth convention would provide, but this audit does not elevate those API defaults into Firestorm-specific source facts.

## Reversed-Z Determination

### Projection evidence

**Status: `SOURCE-PROVEN` conventional-sign perspective projection.**

The source projection coefficients are the standard finite perspective form with a `-1` perspective term. Under ordinary OpenGL perspective divide, near and far map in the conventional NDC direction rather than a reversed projection matrix.

### Comparison-function evidence

**Status: `SOURCE-PROVEN` conventional comparison direction.**

Normal `display()` establishes `GL_LEQUAL`, not `GL_GREATER`/`GL_GEQUAL`, and enables depth writes. `GL_GREATER` occurrences found in the inspected pipeline are scoped pathfinding X-ray/debug passes, not normal scene geometry.

### Clear-value evidence

**Status: `UNRESOLVED`.**

The source proves a depth clear occurs on the main deferred target, but no explicit `glClearDepth`/`glClearDepthf` value was established in the audited renderer path.

### Depth-range evidence

**Status: `UNRESOLVED`.**

No actual normal-main `glDepthRange`/`glDepthRangef` call was established. Loader presence does not establish a value.

### Clip-control evidence

**Status: `UNRESOLVED`.**

`glClipControl` is loaded when supported, but no actual normal-main call was established. Firestorm source therefore does not explicitly fix clip origin/depth mode in the audited path.

### Conclusion

**Overall: strongly supported conventional depth, but the full depth-space contract is not source-proven because context/default-state edges remain unresolved.**

The source evidence is inconsistent with a deliberate reversed-Z implementation in the normal main view: projection direction is conventional and the main comparison function is `GL_LEQUAL`. However, the audit does not label the complete pipeline `SOURCE-PROVEN conventional depth` because the clear scalar, depth-range mapping, and clip-control depth mode are not explicitly established by Firestorm source in the audited path.

No contradiction with the accepted prior audits was found.

## Custom / Logarithmic Depth

### Principal normal deferred geometry

`indra/newview/app_settings/shaders/class1/deferred/diffuseV.glsl` writes:

```text
gl_Position = projection_matrix * pos
```

or:

```text
gl_Position = modelview_projection_matrix * vec4(position, 1)
```

`diffuseF.glsl` writes G-buffer color payloads and does not write `gl_FragDepth`.

The PBR opaque equivalents, `pbropaqueV.glsl` and `pbropaqueF.glsl`, likewise use ordinary projected `gl_Position`; the fragment shader writes G-buffer payloads and does not write `gl_FragDepth`.

No logarithm, exponential remap, custom z packing, or other native-depth encoding was found in these principal normal opaque/deferred programs.

### Projection-specific depth modifications

`LLGLSquashToFarClip` in `indra/llrender/llgl.cpp` temporarily rewrites projection depth for far-clip/sky-style rendering and restores the projection stack when its scope ends. This is a specialized scoped projection modification, not evidence that normal opaque main-view depth is logarithmically/custom encoded.

### Conclusion

**Confidence: `LIKELY` no custom/logarithmic native main-view depth encoding.**

The principal diffuse and PBR opaque G-buffer shaders are directly source-proven to use ordinary projection depth without `gl_FragDepth`. A repository-wide proof that no unusual main-view fragment shader ever writes `gl_FragDepth` was not completed, so the broader absence claim remains `LIKELY`, not `SOURCE-PROVEN`.

## Auxiliary Interactions

### Shadow rendering

`indra/newview/pipeline.cpp` shadow generation explicitly scopes:

```text
GL_DEPTH_CLAMP (when supported/requested)
GL_DEPTH_TEST enabled
GL_DEPTH_WRITES enabled
GL_DEPTH_FUNC = GL_LESS
```

This is an auxiliary shadow-camera path. The `LLGLEnable` and `LLGLDepthTest` RAII objects restore previous state at scope exit. Accepted frame evidence places shadow generation before main G-buffer population, so this explicit auxiliary `GL_LESS`/depth-clamp configuration must not be interpreted as the visible-camera baseline.

### Pathfinding X-ray/debug rendering

Pathfinding debug/X-ray drawing uses `GL_GREATER`, disables depth writes, and applies polygon offset. This is diagnostic rendering. It does not establish reversed depth for normal world geometry and is scoped by `LLGLDepthTest`.

### Full-screen lighting/post passes

Deferred lighting and post-processing contain temporary depth-test/write changes, including disabled depth testing or `GL_ALWAYS` where a full-screen operation should not be rejected by scene depth. Those operations occur after G-buffer population and are scoped/restored. They alter pass behavior, not the numeric interpretation of the native depth texture already produced by geometry.

### Shared main depth after G-buffer completion

Accepted G-buffer/post evidence establishes that `mMainRT.screen` shares the exact native deferred depth attachment and later post-deferred scene passes can write it. This means the resource evolves after the G-buffer-complete boundary; it does not imply a change of depth encoding. Later passes continue to use scoped renderer depth state.

## Findings

### Finding 1 — Normal `display()` explicitly establishes depth test ON, writes ON, and `GL_LEQUAL`

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display(bool rebuild, F32 zoom_factor, int subfield, bool for_snapshot)`
- Symbol: local `LLGLDepthTest gls_depth(GL_TRUE, GL_TRUE, GL_LEQUAL)`
- Path: `indra/llrender/llgl.cpp`
- Class: `LLGLDepthTest`
- Functions: constructor, destructor

**What the source proves:**
The normal display render scope requests depth testing enabled, depth writes enabled, and `GL_LEQUAL`. The wrapper applies the actual OpenGL enable/function/mask mutations when necessary and restores prior tracked state on destruction. This is the authoritative Firestorm-issued baseline for the main scene unless an inner scoped pass overrides it.

### Finding 2 — `LLGLDepthTest` is the material depth comparison/write abstraction and restores scoped overrides

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/llrender/llglstates.h`
- Class: `LLGLDepthTest`
- Path: `indra/llrender/llgl.cpp`
- Class: `LLGLDepthTest`
- Functions: `LLGLDepthTest::LLGLDepthTest(...)`, `LLGLDepthTest::~LLGLDepthTest()`

**What the source proves:**
The wrapper tracks prior depth-test enable, compare function, and write-mask values, changes them through `glEnable/glDisable`, `glDepthFunc`, and `glDepthMask`, and restores prior values when the object leaves scope. A shadow/debug/post override therefore is not itself normal-main state.

### Finding 3 — GL initialization does not explicitly establish the full depth-space mapping

**Confidence:** `SOURCE-PROVEN` for the inspected initialization path; active unmapped values remain `UNRESOLVED`

**Source:**

- Path: `indra/llwindow/llwindowwin32.cpp`
- Class: `LLWindowWin32`
- Functions: Windows context creation, `createSharedContext()`
- Path: `indra/llrender/llgl.cpp`
- Class: `LLGLManager`
- Functions: `initGL()`, `initGLStates()`
- Class: `LLGLState`
- Function: `initClass()`

**What the source proves:**
The Windows viewer creates/makes current a versioned OpenGL context, then initializes the GL manager and loads entry points. `initGLStates()` does not issue depth-range, clip-control, or clear-depth setters. The renderer therefore cannot claim those values were actively initialized there.

### Finding 4 — `glDepthRangef` support is loaded, but no relevant actual depth-range setter was established

**Confidence:** `LIKELY` absence in the complete normal-main path; numeric value `UNRESOLVED`

**Source:**

- Path: `indra/llrender/llglheaders.h`
- Symbol: `glDepthRangef` declaration
- Path: `indra/llrender/llgl.cpp`
- Class: `LLGLManager`
- Symbol: `glDepthRangef` function-pointer load
- Additional audited scopes: `llrender.cpp`, `llrendertarget.cpp`, `llviewerdisplay.cpp`, `llviewerwindow.cpp`, `pipeline.cpp`, `llwindowwin32.cpp`
- Accepted evidence: `FS-CAMERA-001` repository-wide symbol search record

**What the source proves:**
A loaded function pointer is not a call. No normal-main setter was established by the prior repository search plus current high-risk-path recheck. The exact active depth-range mapping is therefore not Firestorm-source-proven.

### Finding 5 — `glClipControl` support is loaded, but no relevant actual call was established

**Confidence:** `LIKELY` absence in the complete normal-main path; mode `UNRESOLVED`

**Source:**

- Path: `indra/llrender/llglheaders.h`
- Symbol: `glClipControl` declaration
- Path: `indra/llrender/llgl.cpp`
- Class: `LLGLManager`
- Symbol: version-gated `glClipControl` function-pointer load
- Additional audited Windows/main-render scopes listed in Search Coverage

**What the source proves:**
Firestorm has plumbing to call clip control on sufficiently new GL contexts, but loader presence is not state configuration. No actual normal-main call was established, so origin and clip-depth mode remain unresolved as Firestorm-specific source facts.

### Finding 6 — The main deferred target clear includes depth, but the clear scalar is not explicitly established

**Confidence:** clear operation `SOURCE-PROVEN`; clear value `UNRESOLVED`

**Source:**

- Path: `indra/llrender/llrendertarget.cpp`
- Class: `LLRenderTarget`
- Function: `clear(U32 mask_in)`
- Function: `allocateDepth()`
- Accepted evidence: `FS-GBUF-001` main deferred target/depth ownership and `GL_DEPTH_COMPONENT24`
- Accepted evidence: `FS-FRAME-001` main `deferredScreen.bindTarget() -> clear() -> renderGeomDeferred()` sequence

**What the source proves:**
`LLRenderTarget::clear()` adds `GL_DEPTH_BUFFER_BIT` when `mUseDepth` and calls `glClear`. The main deferred target has depth, so its normal clear includes depth. The function does not call `glClearDepth*` and does not mutate depth compare/write state. No explicit clear scalar was established elsewhere in the audited path.

### Finding 7 — The main G-buffer clear occurs while the enclosing display depth-write state is enabled

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display(...)`
- Symbol: enclosing `LLGLDepthTest(GL_TRUE, GL_TRUE, GL_LEQUAL)`
- Path: `indra/llrender/llrendertarget.cpp`
- Function: `LLRenderTarget::clear()`

**What the source proves:**
The main target clear does not force depth writes, but normal `display()` already has depth writes enabled. Thus the normal deferred clear is not dependent on a locally disabled write mask left by an enclosing main pass. The numeric value written by the clear remains unresolved.

### Finding 8 — The source projection and main compare direction both point to conventional, not reversed-Z, rendering

**Confidence:** `SOURCE-PROVEN` for those two evidence axes; overall full-depth determination remains incomplete

**Source:**

- Path: `indra/newview/llviewercamera.cpp`
- Class: `LLViewerCamera`
- Functions: `calcProjection()`, `setPerspective()`
- Accepted evidence: `FS-CAMERA-001`
- Path: `indra/newview/llviewerdisplay.cpp`
- Function: `display(...)`
- Symbol: `GL_LEQUAL`

**What the source proves:**
The projection coefficients have conventional finite-perspective direction and the normal main compare function accepts smaller/equal values. A deliberate reversed-Z path would normally require contrary evidence in at least projection or comparison; none was found. Full source-only proof still depends on unresolved depth-range/clip-control/clear-state edges.

### Finding 9 — Shadow depth state is explicitly different and scoped

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Shadow-generation path
- Symbols: `LLGLEnable clamp_depth(...)`, `LLGLDepthTest(..., GL_LESS)`

**What the source proves:**
Shadow rendering can enable `GL_DEPTH_CLAMP` and uses `GL_LESS`. These settings belong to an auxiliary shadow camera/pass and are wrapped by RAII state objects. They are not evidence for the normal visible-camera `GL_LEQUAL` baseline.

### Finding 10 — `GL_GREATER` occurrences inspected are debug/X-ray behavior, not reversed main rendering

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/pipeline.cpp`
- Class: `LLPipeline`
- Pathfinding console/X-ray rendering blocks
- Symbols: `LLGLDepthTest(GL_TRUE, GL_FALSE, GL_GREATER)`, `glPolygonOffset(...)`

**What the source proves:**
The inspected `GL_GREATER` usage is explicitly pathfinding X-ray/debug rendering with writes disabled. It cannot be generalized into a reversed-Z main-scene contract.

### Finding 11 — Principal normal diffuse and PBR opaque G-buffer shaders use ordinary projection depth

**Confidence:** principal programs `SOURCE-PROVEN`; global all-main-shader absence of custom depth `LIKELY`

**Source:**

- Path: `indra/newview/app_settings/shaders/class1/deferred/diffuseV.glsl`
- Symbol: `gl_Position`
- Path: `indra/newview/app_settings/shaders/class1/deferred/diffuseF.glsl`
- Function: `main()`
- Path: `indra/newview/app_settings/shaders/class1/deferred/pbropaqueV.glsl`
- Symbol: `gl_Position`
- Path: `indra/newview/app_settings/shaders/class1/deferred/pbropaqueF.glsl`
- Function: `main()`

**What the source proves:**
These main opaque/deferred vertex programs write ordinary projection/MVP results to `gl_Position`; their fragment programs write G-buffer payloads and do not write `gl_FragDepth`. They do not implement logarithmic or custom native depth encoding.

### Finding 12 — Deferred reconstruction assumes sampled depth can be remapped by `2*d-1`

**Confidence:** `SOURCE-PROVEN`

**Source:**

- Path: `indra/newview/app_settings/shaders/class1/deferred/deferredUtil.glsl`
- Symbols: depth sampling/reconstruction utility, `inv_proj`
- Accepted evidence: `FS-CAMERA-001`

**What the source proves:**
Deferred reconstruction converts the sampled depth scalar to NDC with `2*d-1` and then applies `inv_proj`. This makes the unresolved OpenGL depth-range/clip-mode edge materially important: the shader side is explicit even though the corresponding Firestorm GL mapping setter is not.

## Search Coverage

### Exact API/state terms

Checked for actual uses or abstractions of:

- `glDepthRange`
- `glDepthRangef`
- `glClipControl`
- `glDepthFunc`
- `glDepthMask`
- `glClearDepth`
- `glClearDepthf`
- `GL_DEPTH_TEST`
- `LLGLDepthTest`
- `GL_DEPTH_CLAMP`
- `GL_GREATER`
- `GL_ALWAYS`
- `glPolygonOffset`
- `glClear`
- `GL_DEPTH_BUFFER_BIT`
- `gl_FragDepth` in representative normal deferred shader programs
- `gl_Position` in representative normal deferred shader programs
- `depthMap`
- `inv_proj`
- `glm::perspective`

### Abstraction/lifetime layers checked

- GL entry-point declarations and loader initialization
- `LLGLManager` initialization
- generic `LLGLState` / `LLGLEnable` RAII behavior
- `LLGLDepthTest` depth-test/function/write wrapper
- Windows context creation and GL manager handoff
- `display()` normal main-frame baseline
- viewer camera/projection setup via accepted `FS-CAMERA-001`
- `LLRenderTarget` bind/clear/depth allocation behavior
- main `LLPipeline` deferred/shadow/post state overrides
- principal deferred diffuse and PBR opaque shaders
- accepted frame/G-buffer/post audits for main-target ownership and ordering

### Files directly inspected at the pinned commit

- `indra/llrender/llgl.cpp`
- `indra/llrender/llgl.h`
- `indra/llrender/llglstates.h`
- `indra/llrender/llglheaders.h`
- `indra/llrender/llrender.cpp`
- `indra/llrender/llrendertarget.cpp`
- `indra/llrender/llrendertarget.h`
- `indra/llwindow/llwindowwin32.cpp`
- `indra/newview/llviewerdisplay.cpp`
- `indra/newview/llviewerwindow.cpp`
- `indra/newview/pipeline.cpp`
- `indra/newview/app_settings/shaders/class1/deferred/diffuseV.glsl`
- `indra/newview/app_settings/shaders/class1/deferred/diffuseF.glsl`
- `indra/newview/app_settings/shaders/class1/deferred/pbropaqueV.glsl`
- `indra/newview/app_settings/shaders/class1/deferred/pbropaqueF.glsl`
- deferred shader directory inventory and accepted `deferredUtil.glsl` findings

### Negative-finding discipline

- Declarations, typedefs, and loader assignments were explicitly separated from state-changing calls.
- The accepted `FS-CAMERA-001` repository-wide symbol-search result for `glDepthRange`/`glDepthRangef`/`glClipControl` was reused rather than silently treated as a complete runtime-state proof.
- Current direct inspection rechecked the highest-risk Windows/context/render files around normal main rendering.
- Because the available repository code-search interface did not provide a reliable full-repository content query in this audit, stronger absolute claims such as “Firestorm never calls this anywhere” are intentionally avoided.
- `gl_FragDepth` was checked in principal normal diffuse/PBR opaque deferred programs, not exhaustively across every shader variant; the broad custom-depth absence is therefore `LIKELY`.

## Unresolved Questions

1. What source/configuration guarantee establishes the live depth range used by the Windows OpenGL context before and during normal `display()` if no Firestorm `glDepthRange*` setter runs?
2. What source/configuration guarantee establishes the live clip-depth mode when `glClipControl` is loaded but not called in the audited normal-main path?
3. What source/configuration guarantee establishes the live depth-clear scalar when the renderer issues depth clears without an explicit `glClearDepth*` setter in the audited scope?
4. Is there any less-common normal-main deferred shader variant outside the principal diffuse/PBR opaque programs that writes `gl_FragDepth` or otherwise custom-encodes native scene depth? No such path was established here.
5. What is the persistent normal-main `GL_DEPTH_CLAMP` state outside the source-proven scoped shadow override? No normal-main enable was established, but the exact persistent value was not independently source-proven.

## Recommended Next Audit

- **Proposed task ID:** `FS-GLDEPTHDEFAULTS-001`
- **Exact question:** What exact Windows OpenGL context/profile and renderer-initialization guarantees make Firestorm's normal main-view rely on specific values for depth range, clip-depth mode, and depth-clear value before `display()` begins, and is any intervening source path capable of changing those values without restoration?
- **Why this is the next useful dependency:** `FS-DEPTHSTATE-001` closes the main comparison/write state and the shader/projection endpoints, but the numerical bridge between projected NDC and sampled depth remains incomplete precisely at context-level state for which no Firestorm setter was established. Closing that single context/default-state boundary would determine whether the shader's `2*d-1` reconstruction is fully source/spec-backed and whether conventional depth can be upgraded from strongly supported to fully proven.
- **Likely source starting points:** `indra/llwindow/llwindowwin32.cpp`; `indra/llrender/llgl.cpp`; `indra/llrender/llglheaders.h`; context profile/version attribute construction; GL state initialization; any platform/common GL bootstrap called before `display()`; the applicable OpenGL specification text for initial depth-range, clip-control, and depth-clear state.

## Handoff Summary

- Pinned commit `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294` was used; no revision substitution.
- Normal `display()` source-proves depth test ON, depth writes ON, and `GL_LEQUAL`.
- `LLGLDepthTest` source-proves scoped application and restoration of enable/function/write state.
- Main deferred target clear source-proves inclusion of `GL_DEPTH_BUFFER_BIT`.
- Main deferred native depth is accepted/source-proven as requested `GL_DEPTH_COMPONENT24`.
- Main projection and shader `2*d-1 -> inv_proj` reconstruction remain accepted/source-proven.
- No actual normal-main depth-range setter was established; numeric depth range remains unresolved.
- `glClipControl` is loaded but no normal-main call was established; clip-depth mode remains unresolved.
- No explicit depth-clear setter was established; clear scalar remains unresolved.
- Shadows can scope `GL_DEPTH_CLAMP` + `GL_LESS`; pathfinding debug can scope `GL_GREATER`; neither defines main depth.
- Principal diffuse/PBR opaque shaders use ordinary `gl_Position` and no `gl_FragDepth`; global custom-depth absence is `LIKELY`.
- Overall depth is strongly supported as conventional/non-reversed, but not fully source-proven because context/default-state edges remain.
- Next audit: `FS-GLDEPTHDEFAULTS-001` to close the context/default-state bridge.
