CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.6

Branch: agent/ssr-spatial
Parent accepted runtime: aed6af3768628ea7c0abf2d18f9d3ae8b9cc8484 (CORE+SPATIAL v0.5)
Validated Hi-Z source: agent/ssr-hiz addons/SLSSR/static-hiz-v0.53/integration/SL_HIZ53_WORLD_TRACE_INTEGRATION.fxinc
Validated standalone reference SHA-256: d1b7870345c9a418b9a54c018271f8307768d244c4a0490b30dba6840624e8a1

Runtime files
-------------
SL_SSR_CORE_SPATIAL_HIZ_v0_6.fx
SL_HIZ53_WORLD_TRACE_INTEGRATION.fxinc   (must be adjacent to the FX)

Integration scope
-----------------
Tracer transplant only. WORLD/Dstatic can be switched temporarily between the accepted v0.5 marcher and validated Hi-Z v0.53. AVATAR remains the v0.5 [D0,DavatarBack] TraceSSR path. Nearest WORLD/AVATAR arbitration, Raw/Meta, full-res buffers, Spatial resolve, materials, roughness, Cstatic sampling/composite and current receiver semantics remain unchanged.

Temporary A/B
-------------
WORLD Tracer A/B = 0: old accepted v0.5 WORLD tracer
WORLD Tracer A/B = 1: Hi-Z v0.53 WORLD tracer (default for integration testing)
Display Mode 38: old R / Hi-Z G / both white / neither black.
Display Mode 31 remains the selected production WORLD accepted-hit mask.
Display Mode 32 remains AVATAR-only accepted-hit mask.
Display Mode 33 remains dual-trace selected layer.
Display Mode 37 remains the old-WORLD blocked background-entry diagnostic.

Hi-Z transplant invariants
--------------------------
Dstatic only for WORLD candidates.
Cstatic only for Hi-Z WORLD hit color.
D0 is receiver setup only inside the validated Hi-Z source.
Fresh full-resolution Dstatic is final acceptance authority.
No guide-vs-fresh hard veto is added.
v0.52/v0.53 grazing recovery unchanged.
Discontinuity tolerance remains 0.20.
No DDA. No Temporal. No removed recovery path.

Hi-Z build order
----------------
Ten hierarchy passes L0..L9 execute immediately before the existing Trace pass. ResolveHorizontal, ResolveVertical and Composite remain after Trace exactly as before.

Runtime test
------------
Enable only CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.6.
CORE v0.49 OFF. Standalone HIZ DEBUG OFF. TEMPORAL PRE/POST OFF. AVATAR RECEIVER OFF.
First set WORLD Tracer A/B = Hi-Z v0.53.
1. Mode 31: compare static-world accepted-hit coverage at the validated grazing/corner/silhouette views.
2. Mode 32: avatar-only mask must remain unchanged from v0.5.
3. Mode 33: nearest WORLD/AVATAR selected layer must remain correct.
4. Mode 38: inspect old-vs-Hi-Z coverage delta; broad green at known missing old-WORLD edges is expected, broad false green elsewhere is a fail.
5. SSR contribution and Final composite: reflection placement/scaling must match v0.5 while retaining the edge improvement.
6. Recheck GOOD avatar reflections and absence of the pale/white BAD avatar ghost.
Then switch WORLD Tracer A/B = old v0.5 to verify A/B without changing any other setting.
