# SSR v0.20 BackgroundEntry — runtime result

Date: 2026-08-19

Result: **FAIL for the target BLUE reflection hole, informative**.

Runtime supplied three views from v0.20:

- `Background-entry recovered hit mask`
- `Ray termination reason`
- normal/final composite

Observed result:

- The new background-entry recovery mask is essentially empty over the target upside-down avatar-shaped missing-reflection region.
- The target region remains in the no-hit/BLUE class in `Ray termination reason`.
- The final composite therefore does not materially recover the missing avatar-reflection region.

Interpretation:

The specific v0.20 hypothesis — that the BLUE hole was caused by a direct `background -> first geometry sample already non-negative` transition that could not form a normal sign bracket — is not supported by runtime. The dedicated recovered-entry mask does not identify the target silhouette.

Do not further relax background-entry acceptance without evidence; that risks false through-object hits.

Next diagnostic should classify failed BLUE rays by the depth samples they actually observed:

1. no non-background geometry sampled at all;
2. geometry sampled, but all deltas remain negative (ray stays in front of sampled depth);
3. geometry sampled, but all deltas remain non-negative (ray stays behind sampled depth);
4. both signs observed but no accepted crossing.

This classification will determine whether the remaining issue is projection/sampling coverage, sign history, or crossing acceptance.

Preserve proven material response and v0.16 energy-composite behavior. Keep ORANGE disocclusion rejection as a separate failure class.
