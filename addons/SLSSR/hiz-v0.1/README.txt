SL Hi-Z v0.1 - Min/Max Depth Pyramid

Separate FX-only infrastructure build. Reads the authoritative Firestorm SL_DEPTH semantic and exact inverse projection already proven by SSR/HybridGI, then builds a geometry-only hierarchical min/max linear-depth pyramid. It does not alter SSR yet.

Level 0: full-resolution R32F exact linear view depth.
Levels 1..9: RG32F where R=min geometry depth and G=max geometry depth.
Background/outside world is an empty interval, not far-plane geometry. Reduction uses ceil-sized levels and explicit integer texel mapping so odd dimensions are preserved.

First test: Bridge / matrix status, then Hierarchy containment at mips 1, 4, 7, 9. Stable geometry should be green; red indicates a hierarchy failure. Blue background at coarse levels is normal when the tile contains geometry elsewhere.

Package: SL_HiZ_v0_1_MinMax.zip
SHA-256: 2337a4e42cda5367b1d4c2e110eab13f50a70ee5c117349a97c4c6199dfcf8e7
