# SSR resolve / temporal architecture

Status: v0.35 resolve prototype built on v0.34 GhostCull. This document defines the next independent work so trace-core experiments do not absorb resolve/history logic.

## Pipeline boundary

```text
TraceSSR / TraceSSR_DDA
    -> Raw SSR color + confidence
    -> Trace metadata (distance / screen stretch / grazing)
    -> Material-aware spatial resolve
    -> Temporal reprojection / accumulation
    -> Energy replacement composite
```

The trace core is allowed to change independently. Resolve/history must consume a small stable interface rather than embedding new acceptance rules inside `TraceSSR()`.

## Legacy-first material resolve

Primary Second Life path is legacy Blinn-Phong.

Firestorm legacy deferred contract:

- `specularRect.rgb` = specular color
- `specularRect.a` = specular exponent / glossiness

Therefore:

- RGB controls reflection tint/energy.
- Alpha controls reflection lobe width only.
- Alpha must never be used as a reflection-presence gate; prior runtime already proved valid legacy specular RGB can exist with alpha at zero.

PBR remains a secondary branch using Firestorm ORM roughness/metallic channels.

## v0.35 trace metadata contract

Second MRT from the existing trace pass:

- R = accepted view-space hit distance
- G = receiver-to-hit screen travel in native Firestorm pixels
- B = receiver grazing factor
- A = trace confidence

This metadata is generated from an already accepted hit. It does not alter tracing.

## Temporal bridge contract

Do not implement screen-locked accumulation as a production fallback. Proper history needs the Firestorm camera delta already known to exist in the renderer family.

Native bridge should publish:

- current -> previous camera-space transform (Firestorm `inv_modelview_delta` equivalent)
- validity flag
- frame sequence / parity
- history reset flag

The existing projection matrix may be reused for history only while projection is unchanged. A projection/FOV/viewport change must force reset.

### CPU-side work

Prefer CPU for low-frequency state work:

- frame index / ping-pong selection
- Halton or blue-noise sequence index generation
- viewport/resolution/FOV change detection
- camera-cut detection
- history-reset decisions
- precomputed resolve/jitter tables
- resource lifetime/reallocation decisions

Do not move per-pixel filtering or depth reprojection to CPU. GPU readback and re-upload would introduce synchronization stalls larger than the shader work being avoided.

### GPU-side temporal work

- reproject current receiver position into previous camera space
- fetch prior accumulated SSR
- reject off-screen history
- reject by previous depth mismatch
- reject by previous normal mismatch
- clamp history to current spatial neighborhood
- accumulate with confidence-dependent history weight
- store accumulated color plus compact depth/normal history

No true object motion vectors are currently available, so moving avatars/objects still require depth/normal/disocclusion rejection.

## Hi-Z direction

Build the depth pyramid natively from Firestorm deferred depth and expose it to SSR. CPU should manage allocation/mip count and rebuild/reset decisions; GPU should perform min/max reduction. CPU depth readback is explicitly not the target.

Preferred pyramid is min/max depth rather than averaged depth so the tracer can conservatively skip empty depth ranges and keep a finite thickness interval.

## Backface / second-depth direction

A second depth layer is a structural Firestorm-side feature, not something ReShade should infer from the first layer.

Candidate implementation:

- auxiliary opaque geometry pass after/beside deferred depth
- capture backface or second-nearest depth for SSR-relevant opaque geometry
- expose as a dedicated semantic through the bridge

This should come after v0.35 distance/stretch evidence and temporal infrastructure because it is more invasive.
