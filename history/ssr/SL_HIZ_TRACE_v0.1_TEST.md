# SL Hi-Z Trace v0.1 — depth-slab comparison

Validated prerequisite: Hi-Z v0.1a containment + interval diagnostics passed in-world. v0.1b keeps the same hierarchy math and only adds silent passthrough so the producer can remain enabled as renderer infrastructure.

The comparison tracer is intentionally diagnostic-only. It uses perspective-correct screen-space interpolation, conservative min/max tile overlap, hierarchical descent, and a mip-0 finite depth-slab test. This follows the same general screen-space DDA principle as McGuire/Mara while adding the validated min/max hierarchy for skipping.

Technique order:
1. `SL Hi-Z v0.1b - Min/Max Infrastructure`
2. `SL SSR v0.35 - Legacy Resolve`
3. `SL SSR Temporal v0.1 - Reprojected History`
4. `SL Hi-Z Trace v0.1 - Depth-Slab Compare`

Primary diagnostic: `v0.35 vs Hi-Z hit mask`.
- WHITE = both hit.
- GREEN = Hi-Z only.
- RED = v0.35 only.
- BLACK = neither.

At the known grazing-ghost camera angle, classify the ghost region before any tuning. RED is the desired evidence that the hierarchical depth-slab core rejects the old bad hit. WHITE means Hi-Z alone reproduces the same geometry decision and the next investigation should target depth-layer insufficiency / surface representation rather than traversal speed.

Package: `SL_HiZ_Trace_v0_1_Compare.zip`
SHA-256: `8cf70b11202c7092d95098a158caf19d557d314ce974a554cb4dcd9a5fa287c8`
