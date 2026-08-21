SL SSR Spatial v0.1 — v0.49 roughness-aware spatial resolve

Backbone commit: 6b27f039f4c67fabdf5a1f37b490feffbde06b9b
Expected restored FX SHA-256: 7edb120a901d6d24660850e8c73ed02f030d9575fa0c68b43fc7d18c16dfe385

Restore
-------
Run: python restore_spatial_v0.1.py
This writes: SL_SSR_Spatial_v0_1.fx

ReShade technique
-----------------
SL SSR Spatial v0.1 - v0.49 Backbone

Scope
-----
Resolve-only milestone. WORLD tracing remains Dstatic/Cstatic. AVATAR tracing remains
inside the native [D0, DavatarBack] interval. Screen-Pixel DDA remains off by default.
No native plumbing, temporal accumulation, Hi-Z tracing, or avatar thickness changes.

Spatial resolve
---------------
- separable 9-tap-per-axis bilateral normalized convolution of SSR contribution only
- premultiplied radiance + confidence/coverage filtering so zero-hit samples participate
  as zero coverage and ragged static-world boundaries can anti-alias
- PBR roughness / legacy glossiness controls the filter radius
- long-ray distance only broadens nonzero roughness; mirror roughness stays sharp
- tangent-plane depth rejection tolerates same-plane grazing depth slope
- normal rejection protects wall/floor corners
- D0-vs-Dstatic receiver exclusion prevents spread across visible avatar silhouettes

Recommended first runtime defaults
----------------------------------
Spatial SSR Resolve = 1
Resolve Max Radius (px) = 10.0
Legacy Gloss Curve = 1.35
Rough-Ray Radius Boost = 0.25
Resolve Plane-Depth Edge = 0.035
Resolve Normal Edge = 24.0
Resolve Coverage AA = 1.0
Use Screen-Pixel DDA = 0

New diagnostics
---------------
Display Mode 43: Resolve radius
Display Mode 44: Resolved SSR confidence/coverage
Display Mode 45: Resolve rejection: avatar R / depth G / normal B
