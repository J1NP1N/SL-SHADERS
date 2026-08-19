# SSR v0.22 CrossingPath — runtime result

Date: 2026-08-19

Result: **PASS as diagnostic / target path identified**.

Runtime screenshot was captured with `Disocclusion Skips = 3` preserved. The avatar-reflection target region is dominated by **ORANGE** in `No-hit crossing candidate path`.

In v0.22, ORANGE means the ray did form the expected negative-to-positive depth crossing candidate, entered binary refinement, but the refined candidate still ended with `finalDelta > Hit Thickness`; the candidate was therefore treated as oversized and skipped/rejected. With the configured skip budget, the target can still exhaust the disocclusion skips and remain missing.

This materially narrows the bug:

- traversal coverage is not the primary failure;
- the ray samples both depth signs;
- a valid crossing candidate is formed;
- the remaining failure is candidate refinement / acceptance precision before the fixed thickness test.

`Disocclusion Skips = 3` remains the known setting for the separate ORANGE/disocclusion recovery path and should not be disabled while fixing this target.

Next isolated test: increase binary hit refinement depth from 5 to 9 iterations without changing trace range, material response, energy composite, disocclusion skips, or hit-thickness policy. If the target turns WHITE, the candidate was simply under-refined. If it remains ORANGE, the depth function is discontinuous at the reflected silhouette and fixed-thickness acceptance needs an edge-aware replacement.
