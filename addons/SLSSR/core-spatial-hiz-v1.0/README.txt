CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v1.0

Root cause corrected
--------------------
The exact v0.49 shader declares SLSSRRawTex, SLSSRMetaTex, SLSSRBlurHTex and
SLSSRResolvedTex at BUFFER_WIDTH/2 x BUFFER_HEIGHT/2. The newer production shader
reused those exact texture names while declaring them full resolution.

ReShade shares same-named textures between loaded effects. Therefore merely leaving
v0.49 / Spatial-v0.1 in the shader search path can alias the production full-res
intermediates to the older half-res storage even when the old techniques are OFF.
That produces the persistent top-left-quarter / scale mismatch seen in Raw hit,
SSR contribution and resolved confidence diagnostics.

A second regression in v0.9 came from deriving screen UV from SV_Position. The exact
v0.49 contract uses normalized TEXCOORD in Trace, ResolveHorizontal,
ResolveVertical and Composite. On OpenGL SV_Position uses a bottom-left origin,
while ReShade normalizes TEXCOORD to the DirectX-style texture convention. v1.0
therefore restores the v0.49 TEXCOORD contract and does not use SV_Position for
screen UV reconstruction.

Changes
-------
- Keep Raw/Meta/BlurH/Resolved full resolution.
- Rename all four private SSR RTs and samplers to the unique SLCSH10* namespace.
- Rename all ten private Hi-Z pyramid textures/samplers to SLCSH10H53* so the
  standalone Hi-Z diagnostic can remain loaded without storage aliasing.
- Remove the v0.8 viewport-reset workaround.
- Keep v0.49 normalized TEXCOORD addressing in Trace/Resolve/Composite.
- No tracer acceptance, hit tolerance, avatar interval, arbitration, material,
  roughness, Cstatic sampling or Spatial filtering math is changed.

Runtime isolation
-----------------
Enable only CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v1.0.
CORE v0.49 OFF. Temporal OFF. HIZ DEBUG OFF. Avatar Receiver OFF.
Older FX files may remain present/loaded; their private RT names can no longer alias
this runtime.

First checks:
1. Spatial SSR Resolve OFF: Ray hit / accepted-hit / SSR contribution must occupy
   the correct full-screen receiver locations, not only the top-left quarter.
2. Spatial SSR Resolve ON: placement must remain identical; only the intended
   roughness/coverage filtering may change.
3. Mode 35 resolved confidence must align with the raw accepted-hit geometry.
4. Mode 38 old-vs-Hi-Z coverage must be screen-registered; switching A/B must not
   move or scale the reflection field.

Expected FX SHA-256:
715deb015938b879ae9a23cd24f1cc26adac2ffe3d731f9edaf70a911e0bb755
