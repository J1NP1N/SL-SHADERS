# SLRenderBridge State Machine

## Evidence classes

The state machine distinguishes:

- source-backed semantic markers: authoritative context evidence when emitted by a future Firestorm patch at audited source boundaries;
- ReShade resource observations: authoritative for the observed OpenGL resource/view identity, not for Firestorm high-level ownership;
- structural heuristics: candidate-only evidence and never sufficient to publish `SL_MAIN_*` resources.

## Main-view classifier

| From | Trigger | Required evidence | To | Invalidation / action | Confidence |
| --- | --- | --- | --- | --- | --- |
| `UNINITIALIZED` | bridge construction | none | `OBSERVING` | none | `NONE` |
| `OBSERVING` | first deferred-like target set | >=3 color attachments plus depth; first three colors and depth share nonzero dimensions | `MAIN_CANDIDATE` | remember candidate only; do not publish | `STRUCTURAL_CANDIDATE` |
| `MAIN_CANDIDATE` | distinct deferred-like target before present/native context | same structural rule, different resource identity | `AMBIGUOUS` | do not publish | `STRUCTURAL_CANDIDATE` |
| any external-only state | `present` | ReShade present callback | `OBSERVING` | clear per-present candidate classification; keep resource diagnostics | `NONE` |
| any | Firestorm `MAIN_VIEW_BEGIN` | source-backed marker at normal main context | `MAIN_CONFIRMED` | no resource publication yet | `SOURCE_BACKED_NATIVE_MARKER` |
| `MAIN_CONFIRMED` | Firestorm `MAIN_GBUFFER_BOUND` while a ReShade deferred-like target is current | marker + current ReShade resource set | `MAIN_CONFIRMED` | latch current set as semantic main; increment generation if changed | `SOURCE_BACKED_NATIVE_MARKER` |
| any | Firestorm standard/hero/impostor/other aux begin | source-backed auxiliary marker | `AUXILIARY_CONFIRMED` | mark later deferred-like binds rejected as main; never replace confirmed main | `SOURCE_BACKED_NATIVE_MARKER` |
| `AUXILIARY_CONFIRMED` | Firestorm aux end | source-backed marker | `OBSERVING` | preserve previously confirmed main resource identity | `NONE` |
| `MAIN_CONFIRMED` | Firestorm main-frame complete | source-backed marker | `OBSERVING` | preserve main resources until actual invalidation/recreation | `NONE` |
| any | resize/device/resource invalidation | ReShade lifecycle event or future Firestorm invalidation marker | `OBSERVING` | clear stale semantic resources; increment generation | `NONE` |

### Why the structural rule is not authoritative

The deferred-like rule exists only to give diagnostics and the future marker a target set to latch. It approximates the source fact that the main G-buffer is an MRT with depth, but `FS-AUX-001` proves the standard and hero probe packs intentionally have the same core layout. Dimensions and attachment structure are therefore not native discriminators.

Known false positives include standard reflection probes, hero/mirror probes, and any other auxiliary deferred pack with matching structure. Known false negatives include configuration changes that alter attachment availability/count or an observation surface that does not expose all views as expected.

Elimination path: Firestorm marker at `mMainRT.deferredScreen` bind and explicit auxiliary markers.

## Candidate stage tracker

The candidate tracker is diagnostic-only:

```text
NONE
  |
  | deferred-like target bound
  v
DEFERRED_LIKE_BUILDING
  |
  | different/non-deferred target bound
  v
DEFERRED_LIKE_COMPLETE
```

This is not exported as a Firestorm semantic render stage. It does not imply that `renderGeomDeferred()` actually completed.

## Semantic render stages

| Stage | Trigger | Source-backed Firestorm meaning | External-only behavior |
| --- | --- | --- | --- |
| `UNKNOWN` | default / present / invalidation | no current source-backed semantic boundary | normal state |
| `MAIN_GBUFFER_BUILDING` | `MAIN_GBUFFER_BOUND` marker | current observed set corresponds to `mMainRT.deferredScreen` during the main deferred geometry interval | never inferred |
| `MAIN_GBUFFER_COMPLETE` | `MAIN_GBUFFER_COMPLETE` marker | normal-main `renderGeomDeferred()` has completed and `deferredScreen.flush()` boundary was reached | never inferred |
| `MAIN_DEFERRED_LIGHTING` | deferred-lighting marker | main deferred lighting begins after completed G-buffer | never inferred |
| `MAIN_POST_DEFERRED` | post-deferred marker | main post-deferred scene work on `mMainRT.screen` | never inferred |
| `MAIN_SCENE_COMPLETE` | scene-complete marker | completed world scene at/near `renderFinalize()` input | never inferred |
| `MAIN_POST_PROCESS` | post-process marker | Firestorm `renderFinalize()` post chain | never inferred |
| `AUXILIARY_RENDER` | auxiliary begin marker | source-backed probe/impostor/other auxiliary context | never inferred from square target/fullscreen draw |

## Resource invalidation

A confirmed semantic set is cleared immediately when any tracked member resource receives ReShade `destroy_resource`.

Renderer reset paths also clear the set:

- swapchain resize;
- device destruction;
- future `RENDERER_RESOURCES_INVALIDATED` Firestorm marker.

The semantic resource generation increments on invalidation and on a newly confirmed main set. No stale handle survives as a published main contract resource.

## Ambiguity policy

The bridge's correctness preference is:

```text
AMBIGUOUS / NOT PUBLISHED
        over
CONFIDENTLY WRONG MAIN RESOURCE
```

There is no fallback that promotes a candidate because it is full-screen-sized, appears most often, has familiar formats, uses `CAMERA_WORLD`, or occurs near a present call.
