# Firestorm Mapping

Firestorm source mapping is pinned to `master` commit `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`. The audit documents, not an unpinned viewer revision, define the semantic basis of this table.

| Bridge semantic / state | Accepted audit | Firestorm source symbol / object | Relevant source area | Bridge use |
| --- | --- | --- | --- | --- |
| normal main context | `FS-AUX-001`, accepted renderer map | `gPipeline.mRT == &gPipeline.mMainRT`, `gCubeSnapshot == false` | `indra/newview/llviewerdisplay.cpp`, `pipeline.h` | semantic truth; not externally visible through ReShade |
| standard probe context | `FS-AUX-001` | `gPipeline.mRT = &gPipeline.mAuxillaryRT`, cube snapshot path | `llreflectionmapmanager.cpp::updateProbeFace()`, `llviewerdisplay.cpp::display_cube_face()` | future auxiliary marker boundary |
| hero/mirror context | `FS-AUX-001` | `gPipeline.mRT = &gPipeline.mHeroProbeRT`, `mRenderingMirror`, cube snapshot path | `llheroprobemanager.cpp::updateProbeFace()`, `llviewerdisplay.cpp::display_cube_face()` | future auxiliary marker boundary |
| `SL_MAIN_GBUFFER_ALBEDO` | `FS-GBUF-001` | `mMainRT.deferredScreen` attachment 0 | `pipeline.cpp` render-target allocation/binding; deferred shader outputs | current ReShade target attachment 0 only after main marker |
| `SL_MAIN_GBUFFER_MATERIAL` | `FS-GBUF-001` | `mMainRT.deferredScreen` attachment 1 | deferred material/PBR output paths; `bindDeferredShader()` | current ReShade target attachment 1 only after main marker |
| `SL_MAIN_GBUFFER_NORMAL_META` | `FS-GBUF-001` | `mMainRT.deferredScreen` attachment 2 | deferred shader outputs; `bindDeferredShader()` | raw attachment 2 only after main marker |
| `SL_MAIN_GBUFFER_DEPTH` | `FS-GBUF-001`, `FS-DEPTHSTATE-001` | `mMainRT.deferredScreen.mDepth`, requested `GL_DEPTH_COMPONENT24` | render-target allocation/deferred path | current depth resource only after main marker |
| G-buffer complete boundary | `FS-FRAME-001`, `FS-GBUF-001` | `deferredScreen.bindTarget()` -> `renderGeomDeferred()` -> `deferredScreen.flush()` | `llviewerdisplay.cpp::display()`, `pipeline.cpp::renderGeomDeferred()` | future `MAIN_GBUFFER_COMPLETE` marker |
| shared/evolving depth | `FS-GBUF-001`, `FS-ALPHA-001`, `FS-DEPTHSTATE-001` | `mMainRT.deferredScreen` depth shared with `mMainRT.screen` | render-target allocation + post-deferred draw categories | contract distinguishes identity from stage contents |
| `SL_MAIN_SCENE_COLOR` | `FS-POST-001` | `mMainRT.screen` color 0 | `renderDeferredLighting()`, post-deferred scene work, `renderFinalize()` | not implemented in external Phase 1 |
| scene-complete boundary | `FS-POST-001`, `FS-FRAME-001` | completed `mMainRT.screen` before final post chain | `render_ui()` -> `gPipeline.renderFinalize()` | future `MAIN_SCENE_COMPLETE` marker |
| `SL_MAIN_MODELVIEW` | `FS-CAMERA-001` | active `LLRender` model-view stack entry / `modelview_matrix` | `llrender.cpp::syncMatrices()` | future marker matrix payload |
| `SL_MAIN_PROJECTION` | `FS-CAMERA-001` | active `LLRender` projection / `projection_matrix` | `llrender.cpp::syncMatrices()` | future marker matrix payload |
| `SL_MAIN_INV_MODELVIEW` | `FS-CAMERA-001` | inverse active model-view / `inv_modelview` | `llrender.cpp::syncMatrices()` | future marker matrix payload |
| `SL_MAIN_INV_PROJECTION` | `FS-CAMERA-001` | inverse active projection / `inv_proj` | `llrender.cpp::syncMatrices()` | future marker matrix payload |
| `SL_MAIN_MODELVIEW_DELTA` | `FS-TEMPORAL-001` | `gGLDeltaModelView`, `modelview_delta` | `pipeline.cpp::renderGeomDeferred()`, `bindDeferredShader()` | future marker matrix payload; cube passes can overwrite shared global |
| `SL_MAIN_INV_MODELVIEW_DELTA` | `FS-TEMPORAL-001` | `gGLInverseDeltaModelView`, `inv_modelview_delta` | same as above; concrete use in deferred SSR utility | future marker matrix payload |
| post processing | `FS-FRAME-001`, `FS-POST-001` | `LLPipeline::renderFinalize()` | `pipeline.cpp`, `llviewerdisplay.cpp::render_ui()` | future `MAIN_POST_PROCESS` marker |
| resource recreation | renderer map / `FS-GBUF-001`, `FS-POST-001` | `RenderTargetPack` allocation/release, optional emissive/HDR/settings-dependent target recreation | `pipeline.cpp`, `LLRenderTarget` implementation | ReShade resource destruction/resize invalidation + future native invalidation marker |

## Normal attachment contract

Attachment 2 remains raw. The bridge intentionally preserves Firestorm's native encoded normal plus metadata/flag payload rather than silently converting it. Any consumer decode must follow `FS-GBUF-001`/the pinned Firestorm shader helpers.

## Auxiliary protection mapping

The classifier does not use the following as authoritative main discriminators because `FS-AUX-001` demonstrates they can occur in auxiliary cube rendering as well:

- framebuffer dimensions;
- viewport dimensions;
- attachment count/formats;
- deferred draw functions;
- `CAMERA_WORLD`;
- singleton `LLViewerCamera` identity;
- a deferred-style depth attachment.
