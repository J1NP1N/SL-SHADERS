# SL Static Hi-Z v0.52 — Grazing refinement / rejection diagnostics

Parent diagnostic: `HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.51 Full Ascent`
Feature branch: `agent/ssr-hiz`

Runtime result from v0.51 confirms H2: full-ascent is not the remaining blocker. At the known grazing/corner failure view, the accepted-hit mask remains heavily ragged/stippled, termination still contains substantial iteration-budget exhaustion, and rejected fine candidates are extremely active over the same geometry.

This milestone remains standalone. It does **not** integrate Hi-Z into CORE, does not sample or modify `SL_DEPTH_AVATAR_BACK`, preserves world semantics as `Dstatic = SL_DEPTH_BACKGROUND` and `Cstatic = SL_COLOR_BACKGROUND`, and does not use screen-pixel DDA.

## H2 defect in v0.51

At mip 0, v0.51 used one reject code for every `!startsBeforeEntry` case. That conflated:

1. the ray is already **inside** the finite Dstatic slab at the cell boundary; and
2. the ray is already **past/outside** the slab in the direction of travel.

At grazing incidence, case 1 can be a legitimate continuation of the same locally continuous surface: the slab entry occurred just before the current pixel boundary. Rejecting it forces the traversal to advance, ascend, later descend, rediscover the same surface, and reject again.

## v0.52 correction

`HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.52 Grazing Refine` keeps the hierarchy/ascent behavior from v0.51 and changes only mip-0 candidate handling.

When a mip-0 candidate begins already inside the finite slab:

- sample full-resolution Dstatic at the current boundary and a bounded backward point;
- require local Dstatic continuity using `Static Hi-Z Refine Discontinuity`;
- search backward by `Static Hi-Z Grazing Backtrack (px)` (default `2.0 px`);
- if the true slab-entry side is bracketed, bisect using fresh full-resolution Dstatic samples;
- if the entry lies farther back than the bounded search but Dstatic remains locally continuous and the current point is still inside the finite slab, accept the current boundary as a conservative continuation point;
- run the same fresh-Dstatic discontinuity and finite-slab validation before accepting.

This converts the repeated reject -> advance -> ascend -> descend loop into a terminal valid hit only for locally continuous geometry. A discontinuity is still rejected.

## Reject reason split

Fine-reject codes are now:

- `1` magenta — depth-parallel mip-0 segment
- `2` red — begins inside slab but local Dstatic continuity fails; unsafe to recover
- `3` blue — segment does not reach slab entry
- `4` purple — fresh Dstatic empty at refined candidate
- `5` cyan — mip-0 / fresh-Dstatic discontinuity mismatch
- `6` yellow — refined candidate outside the validated finite slab
- `7` white — ray is already beyond/outside the finite slab, not an inside-slab grazing continuation

The previous code 2 conflation is therefore removed.

## New diagnostic views

In addition to the v0.51 views:

- `Dominant fine-reject reason` — color of the most frequent reject reason for each receiver pixel across the trace
- `Reject code 2 count — inside slab / discontinuous` — red intensity
- `Grazing recovery count` — green intensity; nonzero only when the new locally-continuous inside-slab recovery produces an accepted hit
- `Reject code 7 count — already beyond slab` — white intensity

The original `Last fine-reject reason` remains available.

## Isolated ReShade technique order

Use exactly:

1. `CORE — ...` v0.49 baseline
2. `HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.52 Grazing Refine`

Place HIZ DEBUG after CORE so its diagnostic display is the final visible output.

Turn **OFF**:

- every `TEMPORAL PRE — ...`
- every `SPATIAL — ...`
- every `TEMPORAL POST — ...`
- every `AVATAR RECEIVER — ...`
- v0.50 / v0.51 and other older/duplicate Hi-Z diagnostics
- any other alternate SSR trace/resolve/composite

Keep `Start Mip = 6`, `Traversal Budget = 192`, `Refine Steps = 6`, and `Grazing Backtrack = 2.0 px` for the first v0.52 test.

## Runtime comparison

Use the exact same grazing/corner camera that failed v0.51.

Capture:

1. `Static Hi-Z accepted-hit mask`
2. `Termination reason`
3. `Rejected fine candidates`
4. `Dominant fine-reject reason`
5. `Reject code 2 count — inside slab / discontinuous`
6. `Grazing recovery count`
7. `Reject code 7 count — already beyond slab`

Primary success signal:

- accepted-hit coverage becomes materially less ragged/stippled on the known long/grazing transitions;
- yellow iteration-budget regions decrease;
- total rejected-fine activity decreases in the same geometry;
- green grazing-recovery activity appears where v0.51 previously cycled through code-2 rejects;
- no broad new false-hit regions appear.

If code-2 red remains dominant while green recovery stays absent, local continuity gating/backtrack is still too strict or the surface is not continuous at the relevant boundary. If code 7 white dominates instead, the ray is reaching mip 0 after already traversing the finite slab and the next investigation should target the coarse-to-fine entry bracket rather than relaxing continuity.

## Source integrity

`SL_SSR_StaticHiZ_v0_52_GrazingRefine_Diagnostic.fx`

SHA-256: `d499c8cedf922552a784a4ca4359ba74b1161b4026b6f20e263ef82715f94c38`

No Firestorm/ReShade runtime is available in the authoring environment. This commit is runtime-testable, not runtime-proven.
