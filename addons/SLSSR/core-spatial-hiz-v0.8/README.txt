CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.8

Runtime failure fixed
---------------------
v0.7 Mode 38 and final SSR were enlarged/anchored toward the top-left for BOTH old-WORLD and Hi-Z-WORLD A/B selections. Because Mode 38 is generated in the common CORE Trace pass and both WORLD tracers showed the same registration error, the defect was not Hi-Z hitUV, WORLD arbitration, Cstatic sampling, or Spatial filtering.

The new common change before Trace in v0.7 was the ten Hi-Z build passes. L0 is full resolution, then L1..L9 progressively reduce the render-target/viewport size. On the validated Firestorm/OpenGL runtime, the production Trace pass behaved as though the reduced L9 raster viewport remained active. Its full-resolution Raw/Meta output was therefore populated from a reduced raster domain and later displayed stretched/zoomed.

Correction
----------
After SLH53BuildL9 and before the existing production Trace pass, v0.8 binds one disposable BUFFER_WIDTH x BUFFER_HEIGHT R8 target through SLH53ViewportReset. This forces a full-resolution raster-target transition before CORE Trace.

The reset pass has no inputs and its output is never sampled. It cannot affect the Hi-Z hierarchy or SSR data.

No other behavior changed from v0.7:
- validated Hi-Z v0.53 WORLD/Dstatic code unchanged
- old v0.5 WORLD tracer A/B path unchanged
- AVATAR TraceSSR and [D0,DavatarBack] unchanged
- nearest WORLD/AVATAR arbitration unchanged
- Raw/Meta and full-res Spatial buffers unchanged
- Spatial resolve/AA, materials and roughness unchanged
- Cstatic color/composite unchanged
- no Temporal, DDA, or removed recovery paths

Static equivalence check
------------------------
If the v0.8 version labels, SLH53ViewportResetTex/function, and SLH53ViewportReset pass are removed, the resulting source is byte-for-byte identical to v0.7.

Runtime test
------------
CORE+SPATIAL v0.8 ON; ordinary CORE/v0.49 OFF; TEMPORAL OFF; standalone HIZ DEBUG OFF; AVATAR RECEIVER OFF.
1. Display Mode 38 must now be registered to the full screen rather than zoomed top-left.
2. Test WORLD Tracer A/B = Old CORE WORLD tracer. Final placement must match accepted v0.5.
3. Test WORLD Tracer A/B = Hi-Z v0.53 WORLD tracer. Placement/scaling must remain identical while WORLD coverage improves.
4. Check Mode 32 avatar-only mask and Mode 33 layer selection for regressions.

FX SHA-256: 13f5b7ad3d43f1241f5bdd18495aa56b2da013875986649839d943f031b30bd9
