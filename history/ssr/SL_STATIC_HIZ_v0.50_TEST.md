# SL Static Hi-Z v0.50 — Dstatic diagnostic

Base commit: `6b27f039f4c67fabdf5a1f37b490feffbde06b9b`
Feature branch: `agent/ssr-hiz`

This milestone is intentionally standalone. It does **not** edit `SL_SSR_v0_49_AvatarThicknessTrace.fx`, does not sample `SL_DEPTH_AVATAR_BACK`, and does not alter the working avatar `[D0,DavatarBack]` thickness trace.

## What it does

`SL_SSR_StaticHiZ_v0_50_Diagnostic.fx` builds a ten-level min/max hierarchy from the v0.49 static-world depth semantic `SL_DEPTH_BACKGROUND` (`Dstatic`). Level 0 stores exact linearized Dstatic depth as `[min,max]=[d,d]`; levels 1–9 reduce 2x2 child intervals with min/max reduction. Empty/background texels remain empty intervals instead of becoming far-plane geometry. Odd dimensions are retained with ceil-sized levels and explicit child bounds.

The static-world ray tracer uses hierarchical tile-boundary traversal, not screen-pixel DDA. A ray segment whose view-depth interval cannot overlap a tile's `[min,max]` interval skips that tile. Possible overlap descends toward mip 0 without advancing. At mip 0 the tracer uses a finite visible-surface slab `[Dstatic-frontTolerance, Dstatic+thickness]`, requires the ray to enter that slab from outside rather than accepting an already-behind sample, refines the entry by bisection, and validates the refined point against a fresh Dstatic sample.

Accepted world-hit color is sampled only from `SL_COLOR_BACKGROUND` (`Cstatic`). No scene/backbuffer color is used as the world-hit source.

## Runtime setup

1. Run `addons/SLSSR/static-hiz-v0.50/restore_v0.50_static_hiz.py` to reconstruct the exact FX source, then copy `SL_SSR_StaticHiZ_v0_50_Diagnostic.fx` into the active ReShade shader directory used by the v0.49 setup.
2. Keep the existing v0.49 native bridge/add-on stack active so `SL_DEPTH_PRIMARY_NATIVE`, `SL_DEPTH_BACKGROUND`, `SL_COLOR_BACKGROUND`, projection matrices, and normals are published.
3. Enable `SL SSR v0.50 - Dstatic Hi-Z Diagnostic` and place it after v0.49 in ReShade technique order so its debug display is not overwritten.
4. Do not tune performance. Leave `Start Mip=6`, `Traversal Budget=192`, `Refine Steps=6` for the first pass.

## First diagnostic sequence

Use the same camera angles that currently show ragged/stippled `Static-world accepted-hit mask` in v0.49.

1. `Bridge / source status`
   - cyan on valid Dstatic geometry: bridge/matrices and Dstatic sampling are alive;
   - dark blue/black background: no Dstatic geometry at that pixel;
   - red: bridge/projection contract is invalid.
2. `Selected pyramid min/max`, inspect debug mip 0, 4, 7, 9.
   - R = minimum linear depth;
   - G = maximum linear depth;
   - B = interval width;
   - mip 0 should have R approximately equal to G on static geometry;
   - coarse depth discontinuities should widen B rather than disappear.
3. `Static Hi-Z accepted-hit mask` at the grazing/corner test view.
   - This is the primary milestone result. Compare by switching between this view and v0.49 `Static-world accepted-hit mask`.
   - Desired result: continuous geometric coverage through long grazing transitions with fewer single-pixel holes/stipple, without new large false-positive regions.
4. If coverage is wrong, inspect `Traversal iterations`, `Average traversal mip`, `Rejected fine candidates`, and `Refinement work` before changing any parameter.
5. Use `Termination reason` and `Last fine-reject reason` to classify misses.

## Termination colors

- green: accepted hit
- red: bridge/matrix invalid
- orange: invalid/background receiver
- magenta: degenerate/unprojectable ray
- cyan: ray left screen/Firestorm world
- blue: reached trace end/max distance
- yellow: traversal budget exhausted
- salmon: candidates were found but all fine candidates were rejected

## Fine-reject colors

- magenta: depth-parallel segment
- red: ray entered the pixel already inside/behind the finite Dstatic slab
- blue: segment did not reach the slab entry
- black: refined Dstatic sample was empty
- cyan: mip-0 interval and fresh Dstatic disagreed across a discontinuity
- yellow: refined depth fell outside the validated slab

## Pass condition for integration work

Do not integrate into v0.49 yet. Return the runtime result first.

A useful PASS is: the Dstatic hierarchy views are coherent, the accepted-hit mask is materially less ragged at the known grazing/corner transitions, and no broad new false-hit regions appear. Only after that should the v0.49 **world branch** be replaced with this traversal while the avatar branch remains byte-for-byte logically unchanged.
