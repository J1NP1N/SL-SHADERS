CORE+SPATIAL — Full-Res Pixel Mapping v0.4

Branch: agent/ssr-spatial
Parent runtime milestone: bff0e966ecaa3598b3d6cf9fc19f0950d39773d8
FX after restore: SL_SSR_CORE_SPATIAL_v0_4.fx
FX SHA-256: e1a6b85648e4469455d4ee6981ba40abca6f60918619affa2fffae5f28088049

Compile-only correction from v0.3
---------------------------------
ReShade/OpenGL rejected fmod() in the new Display Mode 37 mapping diagnostic.
The three diagnostic-only modulo expressions now use:
    x - floor(x / period) * period
which avoids fmod while producing the same deterministic pattern.

No trace, hit acceptance, D0/Dstatic/Cstatic/DavatarBack semantics, avatar interval,
Spatial resolve behavior, material response, or RT dimensions changed from v0.3.
DDA and obsolete recovery paths remain removed. No Hi-Z or Temporal integration.

Technique:
CORE+SPATIAL — Full-Res Pixel Mapping v0.4

Runtime test state:
CORE+SPATIAL v0.4 ON; CORE v0.49 OFF; TEMPORAL OFF; HIZ DEBUG OFF;
AVATAR RECEIVER OFF for isolated CORE testing.

Start with Display Mode 37. Correct full-res producer/consumer pixel mapping is black.
