# SLRenderBridge Contract

## Contract rules

A semantic is published only to the degree supported by evidence. A non-null resource binding means the bridge has both a source-backed main classification and a bridge-owned one-mip ReShade publication SRV refreshed from that authoritative resource immediately before effects execute. Candidate-only resources remain unbound.

Depth resource identity and depth content semantics are separate. The accepted audits source-prove that `mMainRT.deferredScreen` and `mMainRT.screen` share the same depth texture, while later post-deferred rendering can change its contents. Consumers must check `SL_RENDER_STAGE` and must not treat a stable depth handle as a frozen G-buffer-depth snapshot.

Attachment 2 is exposed raw as Firestorm encoded normal plus metadata. It is not documented or converted as generic RGB normals.

## Effect-facing types

Expected consumer declarations are conceptually:

```text
texture2D ... : SL_MAIN_GBUFFER_DEPTH;
texture2D ... : SL_MAIN_GBUFFER_NORMAL_META;
texture2D ... : SL_MAIN_GBUFFER_ALBEDO;
texture2D ... : SL_MAIN_GBUFFER_MATERIAL;
texture2D ... : SL_MAIN_SCENE_COLOR;

uniform uint  SL_RENDER_STAGE;
uniform uint  SL_MAIN_CLASSIFICATION;
uniform uint  SL_MAIN_CONFIDENCE;
uniform uint2 SL_FRAME_ID;
uniform uint2 SL_RESOURCE_GENERATION;
uniform uint  SL_MAIN_GBUFFER_VALID;
uniform uint  SL_MATRIX_VALID;
```

64-bit counters use `uint2 {low32, high32}` because ReShade FX integer uniforms are 32-bit elements.

Matrix variables are updated only when `SL_MATRIX_VALID != 0`; otherwise the bridge deliberately leaves their effect defaults untouched.

## Semantic items

| Contract item | Semantic meaning | Source provenance | Valid stage | Lifetime | Availability |
| --- | --- | --- | --- | --- | --- |
| `SL_MAIN_GBUFFER_DEPTH` | Raw main `mMainRT.deferredScreen` depth texture; same identity later shared with `mMainRT.screen` | `FS-GBUF-001`, `FS-DEPTHSTATE-001` | G-buffer depth contents are authoritative at `MAIN_GBUFFER_COMPLETE`; later same resource may contain evolved scene depth | Until semantic generation changes or resource destruction | PARTIAL |
| `SL_MAIN_GBUFFER_NORMAL_META` | Raw attachment 2: encoded normal plus Firestorm metadata/flags | `FS-GBUF-001` | `MAIN_GBUFFER_COMPLETE` and later while attachment contents remain valid | Same as confirmed G-buffer set | PARTIAL |
| `SL_MAIN_GBUFFER_ALBEDO` | Raw attachment 0 diffuse/base-color-side deferred payload | `FS-GBUF-001` | `MAIN_GBUFFER_COMPLETE` and later while attachment remains valid | Same as confirmed G-buffer set | PARTIAL |
| `SL_MAIN_GBUFFER_MATERIAL` | Raw attachment 1: legacy specular/gloss or PBR ORM depending G-buffer flags/material path | `FS-GBUF-001` | `MAIN_GBUFFER_COMPLETE` and later while attachment remains valid | Same as confirmed G-buffer set | PARTIAL |
| `SL_MAIN_SCENE_COLOR` | Authoritative main world-scene color (`mMainRT.screen`) before final post chain | `FS-POST-001` | `MAIN_SCENE_COMPLETE` | Evolves in place through post-deferred; later authority moves through post chain/backbuffer | REQUIRES_FIRESTORM_PATCH |
| `SL_MAIN_MODELVIEW` | Active Firestorm renderer model-view used for shader-visible main rendering | `FS-CAMERA-001` | Marker-defined main stage only | Per semantic main frame/stage | REQUIRES_FIRESTORM_PATCH |
| `SL_MAIN_PROJECTION` | Active Firestorm renderer projection | `FS-CAMERA-001` | Marker-defined main stage only | Per semantic main frame/stage | REQUIRES_FIRESTORM_PATCH |
| `SL_MAIN_INV_MODELVIEW` | Inverse of active renderer model-view as supplied by Firestorm shader infrastructure | `FS-CAMERA-001` | Marker-defined main stage only | Per semantic main frame/stage | REQUIRES_FIRESTORM_PATCH |
| `SL_MAIN_INV_PROJECTION` | Inverse of active renderer projection (`inv_proj`) | `FS-CAMERA-001` | Marker-defined main stage only | Per semantic main frame/stage | REQUIRES_FIRESTORM_PATCH |
| `SL_MAIN_PREV_MODELVIEW` | Previous normal-main model-view history | `FS-TEMPORAL-001` | Main temporal consumers | Per semantic frame | REQUIRES_FIRESTORM_PATCH |
| `SL_MAIN_MODELVIEW_DELTA` | Firestorm current-to-last model-view delta global uploaded by deferred binding | `FS-TEMPORAL-001` | Main deferred consumers after current main delta is derived | Per render invocation; auxiliary cube renders can overwrite shared globals | REQUIRES_FIRESTORM_PATCH |
| `SL_MAIN_INV_MODELVIEW_DELTA` | Inverse model-view delta used by Firestorm temporal/SSR utilities | `FS-TEMPORAL-001` | Same as above | Same as above | REQUIRES_FIRESTORM_PATCH |
| `SL_RENDER_STAGE` | Typed semantic stage enum; unknown when external observation cannot prove a Firestorm boundary | `FS-FRAME-001`, `FS-POST-001`, `FS-AUX-001` | Always readable | Per callback/present interval | PARTIAL |
| `SL_FRAME_ID` | ReShade present epoch, not Firestorm `gFrameCount` | ReShade `present` event definition | Always readable | Monotonic for bridge lifetime | IMPLEMENTED |
| `SL_RESOURCE_GENERATION` | Monotonic epoch for confirmed semantic main resource-set replacement/invalidation | Audit lifecycle findings + ReShade destroy/resize observation | Always readable | Bridge lifetime | IMPLEMENTED |
| `SL_MAIN_CLASSIFICATION` | Classifier state enum | `FS-AUX-001` plus bridge state machine | Always readable | Current observation/context | IMPLEMENTED |
| `SL_MAIN_CONFIDENCE` | Evidence class for classification | Bridge evidence policy | Always readable | Current observation/context | IMPLEMENTED |
| `SL_MAIN_GBUFFER_VALID` | All four authoritative sources have valid persistent publication resources/SRVs and were refreshed for the current effect execution | ReShade supported resource/create-view/copy/update-texture API + confirmed-main policy | During ReShade effect rendering | Current effect execution; publication objects persist for resource generation | PARTIAL |
| `SL_MATRIX_VALID` | All six currently supported matrix fields were supplied through the native marker ABI | `FS-CAMERA-001`, `FS-TEMPORAL-001` + bridge ABI | Marker-defined main stage | Until invalidation/new marker | REQUIRES_FIRESTORM_PATCH |

`PARTIAL` for the G-buffer resources means the ReShade-side resource tracking and shader-binding path is implemented, but pure external observation cannot authoritatively decide that a deferred-like target is `mMainRT.deferredScreen`. In an unpatched Firestorm run these semantics therefore remain null by design.

## Enum values

`SL_RENDER_STAGE`:

| Value | Meaning |
| ---: | --- |
| 0 | `UNKNOWN` |
| 10 | `MAIN_GBUFFER_BUILDING` |
| 20 | `MAIN_GBUFFER_COMPLETE` |
| 30 | `MAIN_DEFERRED_LIGHTING` |
| 40 | `MAIN_POST_DEFERRED` |
| 50 | `MAIN_SCENE_COMPLETE` |
| 60 | `MAIN_POST_PROCESS` |
| 100 | `AUXILIARY_RENDER` |

`SL_MAIN_CLASSIFICATION`:

| Value | Meaning |
| ---: | --- |
| 0 | `UNINITIALIZED` |
| 1 | `OBSERVING` |
| 2 | `MAIN_CANDIDATE` |
| 3 | `MAIN_CONFIRMED` |
| 4 | `AUXILIARY_CONFIRMED` |
| 5 | `AMBIGUOUS` |

`SL_MAIN_CONFIDENCE`:

| Value | Meaning |
| ---: | --- |
| 0 | `NONE` |
| 1 | `STRUCTURAL_CANDIDATE` |
| 2 | `SOURCE_BACKED_NATIVE_MARKER` |

## Resource identity versus contents

`SL_RESOURCE_GENERATION` answers whether the semantic main resource set changed. `SL_RENDER_STAGE` answers what the bridge knows about the semantic contents at the current boundary.

Example for depth:

```text
resource generation N
    |
    +-- MAIN_GBUFFER_COMPLETE: same depth resource contains completed deferred geometry depth
    |
    +-- MAIN_POST_DEFERRED:    same resource may now include later depth-writing categories
```

Phase 1.1 copies the authoritative depth resource into a bridge-private one-level publication texture immediately before ReShade effects execute. That publication copy is a readable effect-time snapshot, not a promise that its contents still equal the earlier `MAIN_GBUFFER_COMPLETE` depth if Firestorm has written additional shared depth in between.
