# SLRenderBridge Limitations

## 1. Pure external ReShade observation cannot source-prove main versus probe

This is the dominant Phase 1 limitation.

ReShade exposes OpenGL resource/view/framebuffer-binding activity, but not Firestorm C++ ownership such as:

- `mRT == &mMainRT`;
- `mRT == &mAuxillaryRT`;
- `mRT == &mHeroProbeRT`;
- `gCubeSnapshot`;
- `mRenderingMirror`.

`FS-AUX-001` proves the auxiliary packs intentionally reuse the same core deferred pipeline and can look structurally like the main G-buffer. Consequently, an unpatched run may observe useful candidates but will not publish them as authoritative `SL_MAIN_*` resources.

## 2. Native OpenGL FBO object ID is not part of the supported bridge contract

The ReShade `bind_render_targets_and_depth_stencil` event exposes resource views, which are sufficient to track underlying resources. Phase 1 diagnostics therefore report the observed view/resource set rather than inventing a native FBO ID.

A future implementation may inspect additional officially supported API if it becomes available, but it should not reach into ReShade backend internals just to obtain an FBO number.

## 3. Main G-buffer texture publication is implemented but dormant without semantic confirmation

The add-on can create supported OpenGL shader-resource views and bind them to ReShade texture semantics. It only does so after the future native marker confirms the current target as normal main.

This path is source-reviewed against ReShade API 20 but has not been compiled on Windows or runtime-tested in Firestorm in this environment. It remains `PARTIAL`, not runtime-proven.

## 4. Scene color is not mapped in Phase 1

`FS-POST-001` source-proves `mMainRT.screen` as the evolving lit/world scene target, but an external ReShade add-on cannot distinguish it authoritatively from analogous auxiliary pack screen targets with the current evidence surface. `SL_MAIN_SCENE_COLOR` remains unbound.

## 5. Authoritative matrices require a Firestorm-side semantic source

The audits prove that active renderer matrices are not equivalent to reconstructing a camera from FOV/near/far, and auxiliary passes can mutate shared matrix helpers. Phase 1 therefore does not scrape generic GL uniforms or reconstruct matrices heuristically.

The bridge-side marker ABI has fields for:

- model-view;
- projection;
- inverse model-view;
- inverse projection;
- model-view delta;
- inverse model-view delta.

They remain invalid until a Firestorm patch supplies them at the proper normal-main boundary.

`SL_MAIN_PREV_MODELVIEW` is not derived from the delta in Phase 1; it remains explicitly unavailable.

## 6. `SL_FRAME_ID` is a ReShade present epoch

It is useful for grouping repeated callbacks, but it is not a source-proven Firestorm semantic frame number. A future Firestorm marker can provide `native_frame_id` independently.

## 7. Resource identity does not freeze resource contents

The main deferred depth texture is shared into `mMainRT.screen`. Later scene passes can modify it without changing the GL resource identity. Similar lifetime/content issues may apply to other reused render targets.

Consumers must use stage semantics, not handle equality alone.

## 8. Candidate completion is only observational

The external candidate tracker labels a deferred-like target `DEFERRED_LIKE_COMPLETE` when ReShade observes a transition away from it. This does not prove the Firestorm `renderGeomDeferred() -> flush()` semantic boundary. It is diagnostics only and never drives `SL_RENDER_STAGE`.

## Remaining heuristic register

| Heuristic | Why needed | Firestorm fact approximated | False positives | False negatives | Confidence | Elimination path |
| --- | --- | --- | --- | --- | --- | --- |
| deferred-like target = >=3 color resources + depth, first three colors/depth same nonzero dimensions | gives the observer a bounded candidate set and a resource set for a future marker to latch | `mMainRT.deferredScreen` is a multi-attachment deferred target with depth | standard probes, hero probes, other similar deferred auxiliary targets | configurations/observation cases with missing/different attachments | low / candidate-only | `MAIN_GBUFFER_BOUND` marker at `mMainRT.deferredScreen` |
| candidate complete when binding moves away from deferred-like target | diagnostics need a rough observational lifecycle | source-proven main G-buffer has a bind/build/flush interval | temporary rebinds, auxiliary transitions | flush without an observable target change | low / diagnostics-only | `MAIN_GBUFFER_COMPLETE` marker immediately after source-backed flush boundary |

No other heuristic is permitted to upgrade a target to `MAIN_CONFIRMED`.
