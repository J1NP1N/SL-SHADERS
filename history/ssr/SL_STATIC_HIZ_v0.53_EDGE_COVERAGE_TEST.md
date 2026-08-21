# SL Static Hi-Z v0.53 — Residual edge coverage

Parent diagnostic: `HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.52 Grazing Refine`
Feature branch: `agent/ssr-hiz`

Runtime validation of v0.52 closes the broad H2 issue:

`H2 broad reject -> advance -> ascend -> descend thrash: RESOLVED`

The accepted-hit mask is materially more coherent than v0.51, rejected fine candidates are now sparse and boundary-localized, and broad iteration-budget exhaustion is gone. v0.53 deliberately preserves that traversal/grazing-recovery behavior and targets only the residual thin grazing/silhouette holes.

This milestone remains standalone. It does **not** integrate Hi-Z into CORE, does not sample or modify `SL_DEPTH_AVATAR_BACK`, preserves `Dstatic = SL_DEPTH_BACKGROUND` and `Cstatic = SL_COLOR_BACKGROUND`, and does not use screen-pixel DDA.

## Residual root cause targeted

At mip 0, v0.52 still generated/refined a candidate using the hierarchy guide depth `sd`, then performed this hard post-refinement gate:

```hlsl
else if (abs(freshDepth - sd) > discontinuityTolerance)
    reject code 5;
```

At a silhouette/discontinuity pixel, the mip-0 hierarchy sample can represent the neighboring side of the pixel while the fresh full-resolution Dstatic at the **refined UV** is valid. In that case the ray can already lie inside the fresh finite Dstatic slab, but v0.52 rejects the crossing solely because the guide depth and fresh depth differ.

That produces exactly the residual failure pattern: a valid boundary crossing is discarded, traversal continues across the edge, and only a thin local fringe can still consume extra traversal budget.

## Exact v0.53 code change

Candidate generation, hierarchy traversal, full ascent, H2 grazing backtrack/recovery, and all v0.52 reject logic before final validation are preserved.

Final validation changes from:

```hlsl
if (freshDepth <= 0)
    code 4;
else if (abs(freshDepth - sd) > tolerance)
    code 5;
else if (candidateDepth outside fresh slab)
    code 6;
else
    accept;
```

to:

```hlsl
hierarchyMismatch = abs(freshDepth - sd) > tolerance;
freshInside = candidateDepth inside [freshDepth-front, freshDepth+back];

if (freshDepth <= 0)
    code 4;
else if (!freshInside)
    hierarchyMismatch ? code 5 : code 6;
else
    accept;
```

Therefore the hierarchy depth remains a conservative traversal/refinement guide, but it is no longer allowed to veto a geometrically valid crossing proven by fresh full-resolution Dstatic. A mismatch rescued this way is counted explicitly.

No tolerance was widened.

## Minimum new diagnostic

Two display entries are added:

- `Residual edge failure class`
- `Fresh-depth edge rescue count`

`Residual edge failure class` colors:

- **green** — a hit was accepted because fresh Dstatic proved valid slab membership even though the mip-0 guide depth mismatched; this is the v0.53 targeted rescue.
- **red** — trace ended / hit budget without ever reaching a mip-0 candidate cell: candidate never generated.
- **magenta** — H2 backtrack refinement aborted on an empty/discontinuous fresh-depth sample: refinement exited early.
- **orange** — after a rejected mip-0 cell, the immediate post-tile-boundary point is still inside a fresh Dstatic slab: tile transition is carrying/losing the crossing.
- **yellow** — iteration budget exhausted after mip-0 candidates were reached, without one of the signatures above: locally excessive traversal.
- **blue** — other fine-reject termination.
- **black** — no residual failure signature.
- Hits not requiring the new rescue remain black in this classifier.

`Fresh-depth edge rescue count` is green intensity proportional to how many stale-guide mismatches were converted into valid hits.

The diagnostic-only tile-transition probe does not alter lambda, mip, candidate generation, or acceptance.

## Isolated ReShade order

Use exactly:

1. `CORE — ...` v0.49 baseline
2. `HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.53 Edge Coverage`

Place HIZ DEBUG after CORE.

Turn OFF all `TEMPORAL PRE — ...`, `SPATIAL — ...`, `TEMPORAL POST — ...`, `AVATAR RECEIVER — ...`, v0.50/v0.51/v0.52 and other Hi-Z prototypes, and any alternate SSR trace/resolve/composite.

Keep the v0.52 correctness settings unchanged:

- `Start Mip = 6`
- `Traversal Budget = 192`
- `Refine Steps = 6`
- `Grazing Backtrack = 2.0 px`

## Exact runtime test

Use the same fixed grazing/corner/silhouette view used for the v0.52 pass.

Capture:

1. `Static Hi-Z accepted-hit mask`
2. `Termination reason`
3. `Rejected fine candidates`
4. `Residual edge failure class`
5. `Fresh-depth edge rescue count`

Compare v0.52 -> v0.53 without moving the camera.

PASS for this revision:

- broad v0.52 coherence remains intact;
- remaining thin grazing/silhouette holes decrease;
- residual yellow budget fringes decrease;
- green rescue appears specifically along boundary pixels that gain coverage;
- rejected-fine activity does not broaden;
- no new broad false-hit regions;
- no regression to v0.51-style stipple/thrash.

Interpretation if holes remain:

- red => candidate-generation/coarse traversal issue, not refinement;
- magenta => backtrack refinement exits too early;
- orange => tile transition loses the crossing;
- yellow => local traversal budget remains excessive;
- cyan/code-5 in the existing reject views with no green rescue => fresh candidate is genuinely outside its slab or another discontinuity condition still rejects it.

Do not broaden traversal based on this test; use the classifier to select the next single boundary defect only.

## Source integrity

`SL_SSR_StaticHiZ_v0_53_EdgeCoverage_Diagnostic.fx`

SHA-256: `d4e4e9f72fae5a02ad2a1c9b7b534587a67aa3a7be441e4d4e2968eee91544e4`

No Firestorm/ReShade runtime is available in the authoring environment. v0.53 is runtime-testable, not runtime-proven.
