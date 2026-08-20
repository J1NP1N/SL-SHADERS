# SL SSR Background Depth v0.2 — checkpoint / design reset

This file is the continuation checkpoint for the Firestorm-native background-depth experiment on branch `agent/ssr-background-depth`.

## Pinned Firestorm source

Firestorm base:

`FirestormViewer/phoenix-firestorm@f0d4a81c5ded331fb35d19e88544f0d22723bee5`

Local Firestorm source used for the live tests:

`C:\firestorm-slssr\phoenix-firestorm`

Installed custom viewer:

`C:\Program Files\FirestormOS-SLSSRBGDepth`

Known successful rebuild command, from `cmd.exe`:

```bat
set PATH=C:\cygwin64\bin;%PATH%
set AUTOBUILD_VSVER=170
set AUTOBUILD_VARIABLES_FILE=C:\firestorm-slssr\fs-build-variables\variables
cd /d C:\firestorm-slssr\phoenix-firestorm
autobuild build -A 64 -c ReleaseFS_open --no-configure
```

Build output used to replace the installed executable:

`C:\firestorm-slssr\phoenix-firestorm\build-vc170-64\newview\Release\FirestormOS-SLSSRBGDepth.exe`

## Native API currently present

The custom viewer exports:

- `SL_GetSSRPrimaryDepthInfo(texture,width,height)`
- `SL_GetSSRBackgroundDepthInfo(texture,width,height)`
- `SL_SetSSRBackgroundDepthEnabled(enabled)`

The v0.2 ReShade effect consumes:

- `SL_DEPTH_PRIMARY_NATIVE`
- `SL_DEPTH_BACKGROUND`

## ReShade bridge status

The original v0.2 bridge manually fabricated an OpenGL ReShade `resource_view` from the Firestorm texture ID. That path produced valid-looking IDs/sizes but both raw depth samplers read black.

The tested bridge is now **v0.2.2** and has been synced into:

`addons/SLSSR/background-depth-v0.2/SLBackgroundDepthLink.cpp`

v0.2.2 creates ReShade-owned shader-readable backup resources and copies the two Firestorm depth textures into them before publishing the semantics.

Repository sync commit:

`e91c094dfa92effc10e27fbd8045e6efbb485994`

After installing the x64 v0.2.2 add-on, the primary native depth became readable. This is the strongest evidence so far that the bridge path itself is now basically functional.

## Current runtime result

Latest tested state after the Firestorm v0.2.3 and v0.2.4 diagnostic patches:

```text
Link / native pair: CYAN
Primary NATIVE RAW: white scene with gray avatar silhouettes
Background NATIVE RAW: solid black
```

Interpretation:

- both native exports resolve
- both reported sizes are valid
- the ReShade bridge can read Firestorm's primary deferred depth
- the background target is still not producing the intended usable raw depth payload
- do **not** continue debugging linearization, signed difference, recovery masks, or SSR integration until raw background depth is valid

The primary raw result also establishes the observed depth convention for this test build: background/far values are near white and nearer visible geometry is darker. The intended auxiliary target should therefore be white where no allowed background geometry exists, not solid black.

## Firestorm diagnostic patches already tested

### v0.2.3 clear-state patch

Repository file:

`tools/firestorm/Fix-SLSSRBackgroundDepthClear-v0.2.3.ps1`

Commit:

`a4bb9417c420c47b2df0508bc164dae43263d9a8`

Purpose:

- establish `LLGLDepthTest(GL_TRUE, GL_TRUE, GL_LESS)` before the auxiliary clear
- force depth clear value to `1.0` for that clear

Result:

**No change.** Primary raw remained valid; background raw remained black.

### v0.2.4 camera-matrix patch

Repository file:

`tools/firestorm/Fix-SLSSRBackgroundDepthMatrices-v0.2.4.ps1`

Commit:

`33b900894fd9616de93f4cec015922c1f758abd4`

Purpose:

- explicitly save/reload the main-camera projection and model-view around the auxiliary shadow-program draw, matching the structure of Firestorm's normal shadow rendering more closely

Result:

**No change.** Primary raw remained valid; background raw remained black.

These two failed hypotheses are important. Do not repeat them unless new evidence points back to them.

## Performance regression — unresolved

The custom compiled viewer is currently running at noticeably lower FPS than the normal viewer. This is a tracked issue and must be resolved before this becomes a usable SSR path.

Most likely costs in the current prototype:

1. `renderSSRBackgroundDepth()` re-renders many opaque/static draw batches at full viewport resolution every frame while enabled.
2. The v0.2.2 ReShade bridge copies both the primary and background full-resolution depth resources every effect frame.
3. The bridge currently calls `SL_SetSSRBackgroundDepthEnabled(1)` unconditionally from the ReShade begin-effects callback. Once the add-on is active, the extra Firestorm pass is effectively always enabled; it is not yet gated by whether the diagnostic/final SSR technique actually needs it.

Do not treat the FPS drop as an unrelated build problem until this extra-pass cost is measured. Required later work:

- baseline stock/custom viewer FPS in the same scene/settings
- measure GPU time for `renderSSRBackgroundDepth`
- gate the pass so it runs only when actually required
- stop copying native primary depth if the final architecture does not need that copy
- evaluate lower-resolution background depth only after correctness is established

## Depth model: define the layer before writing more code

The project was starting to use the words "background layer" and "second layer" interchangeably. They are not the same thing.

### D0 — primary camera depth

`D0(x,y)` is Firestorm's normal nearest visible depth for a pixel after opaque/deferred rendering.

A normal depth buffer stores one winner per pixel. With `GL_LESS` and a far clear, the closest passing fragment replaces the previous value. Firestorm's deferred pools render both static and rigged variants, so the primary depth can contain avatars and rigged attachments as well as world geometry.

This is the depth the normal SSR tracer sees.

### D1 — true second-nearest depth

A mathematical second layer would be:

`D1(x,y) = nearest fragment strictly behind D0(x,y)`

That requires a depth-peel style pass: render geometry again while rejecting fragments that are not farther than `D0 + epsilon`, then keep the nearest remaining fragment.

Important: for the avatar problem, a generic D1 is not guaranteed to be the wall. It can be another avatar/clothing/body surface behind the first avatar surface.

Therefore a generic second-nearest layer is not automatically the payload this project actually wants.

### Dstatic — nearest allowed static/background depth

The original v0.1 experiment is really trying to construct a different semantic:

`Dstatic(x,y) = nearest non-rigged/static opaque surface from the same camera`

This is a **class-filtered first depth**, not a second-nearest depth.

At a wall pixel with no avatar in front:

`Dstatic ≈ D0`

At an avatar pixel with a wall behind it:

`Dstatic > D0`

At a pixel with no static/background surface:

`Dstatic = far clear` (approximately raw `1.0` in the current observed convention)

For the specific visible artifact we are trying to solve — an avatar hiding wall/floor geometry needed by SSR — `Dstatic` is more directly useful than a generic D1.

## The missing safety condition: primary occluder classification

A static/background depth must not simply replace primary depth whenever it is farther.

The safe conceptual payload is:

- `D0`: normal primary depth
- `M0`: a mask/classification telling us whether the primary surface is an excluded occluder class, initially rigged/avatar
- `Dstatic`: nearest permitted static/background depth

Then the tracer can use `Dstatic` only when `M0` says the primary depth came from a class intentionally absent from `Dstatic`.

Without `M0`, a fallback to farther depth can tunnel through legitimate static foreground surfaces or through geometry families accidentally omitted from the auxiliary pass.

This classification/mask should be part of the design before final SSR integration.

## Depth alone does not recover hidden color

Even a correct hidden wall depth does not magically make the wall's hidden screen color available. If an SSR hit lands exactly at a pixel whose visible color is the avatar, the normal scene color buffer still contains the avatar.

A background depth layer can help the ray **trace through** an occluder and find another visible hit, but fully reconstructing a hit that is hidden in both depth and color eventually requires one of:

- a matching background/static color/radiance layer
- another scene representation
- a reflection probe/environment fallback

For now, keep the task scoped to proving the depth payload first.

## What the raw background texture should look like

Before any linearization:

- `Primary NATIVE RAW`: ordinary scene depth, with avatars visible
- `Background NATIVE RAW`: ordinary-looking world depth with excluded rigged/avatar geometry absent
- where an avatar covers a wall, the background raw texture should show the wall depth through the avatar silhouette
- empty/no-static pixels should be far/white, not black

Until this is true, the layer is not valid.

## Next diagnostic — stop guessing at matrices

The next test should isolate target contents from geometry rendering.

### Test A: clear-only target

Temporarily make `renderSSRBackgroundDepth()` bind the auxiliary target, clear its depth to `1.0`, draw **nothing**, and flush.

Expected ReShade result:

`Background NATIVE RAW = solid white`

If it is still black, the problem is target/export/copy/resource handling, not static geometry or camera matrices.

### Test B: controlled constant depth

After clear-only succeeds, write one controlled depth value (for example a fullscreen debug draw at a known depth, or another native constant-depth test).

Expected ReShade result:

known raw gray value matching the injected depth.

This proves the auxiliary FBO -> native texture -> exported ID -> ReShade backup -> FX sampler chain end to end.

### Test C: actual static geometry

Only after A and B succeed should the static geometry draw be restored. Then debug draw-call coverage / matrices / render-map selection if the texture is wrong.

This sequence is now preferred over more speculative state patches.

## Relevant Firestorm source behavior already verified

- `LLRenderTarget::allocate(..., depth=true)` creates a `GL_DEPTH_COMPONENT24` depth texture.
- a zero color format is allowed; the target can be depth-only.
- `LLRenderTarget::bindTarget()` sets draw/read buffers to `GL_NONE` when there is no color attachment.
- primary deferred draw pools include both static and rigged variants; therefore normal primary depth naturally contains rigged/avatar geometry.
- Firestorm's screen-space reflection utility samples one `sceneDepth` texture and reconstructs linear/view-space depth from that single layer.

This confirms the architectural problem: once an avatar wins D0 at a pixel, the wall depth behind it is absent from ordinary single-layer SSR. ReShade cannot reconstruct that missing geometry from the primary depth buffer alone.

## Current decision

Do not call the current auxiliary texture a proven "second layer" yet.

The intended semantic for the avatar/wall experiment is now:

**nearest static/background depth from the same camera, paired with an eventual primary occluder mask.**

First milestone remains purely structural:

1. prove raw `Dstatic` is valid
2. prove `Dstatic > D0` through avatar silhouettes
3. then decide how the tracer consumes it
4. address performance before considering the path production-ready
