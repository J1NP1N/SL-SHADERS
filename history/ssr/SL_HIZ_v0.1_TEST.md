# SL Hi-Z v0.1 — min/max pyramid runtime test

Baseline: existing Firestorm/SLProbeLighting depth + exact projection bridge. This build is an independent FX-only producer/diagnostic and does not change the current SSR tracer, v0.35 Legacy Resolve, or SSR Temporal v0.1.

## Pyramid contract

- Level 0: full-resolution `R32F` positive linear view depth.
- Levels 1..9: `RG32F`, `R=min geometry depth`, `G=max geometry depth`.
- Background/outside Firestorm world is an empty interval (`min=HIZ_EMPTY_DEPTH`, `max=0`), not far-plane geometry.
- Reduction is min/max, never average.
- Level dimensions use ceil division and explicit integer texel mapping so odd buffer dimensions do not drop source rows/columns. For the previously observed 3840x2027 buffer the chain is 3840x2027 -> 1920x1014 -> 960x507 -> 480x254 -> 240x127 -> 120x64 -> 60x32 -> 30x16 -> 15x8 -> 8x4.

## Runtime sequence

1. Hot-install `SL_HiZ_v0_1_MinMax.zip`; Firestorm may remain open.
2. Enable `SL Hi-Z v0.1 - Min/Max Depth Pyramid`.
3. `Hi-Z Display -> Bridge / matrix status`: expect the same valid cyan/green-ish bridge state already proven by SSR/temporal.
4. `Hi-Z Display -> Hierarchy containment`; inspect debug mip 1, 4, 7, and 9.
   - Stable geometry pixels: GREEN.
   - RED on stable opaque geometry: reduction/mapping failure.
   - Background BLUE at coarse levels: normal; the coarse tile contains geometry elsewhere.
   - Background BLACK: fully empty selected tile.
5. Inspect `Minimum depth`, `Maximum depth`, and `Depth interval width` at mip 4 and mip 7.

## Pass condition

No red containment failures on stable opaque geometry across mip 1/4/7/9, with plausible near/far interval behavior.

If this passes, the next build is a separate Hi-Z SSR tracer that consumes this hierarchy. Spatial resolve v0.35 and Temporal v0.1 remain separate modules.

## Package

`SL_HiZ_v0_1_MinMax.zip`

SHA-256: `2337a4e42cda5367b1d4c2e110eab13f50a70ee5c117349a97c4c6199dfcf8e7`
