# SSR v0.23 DeepRefine — runtime result

Date: 2026-08-19

Result: **FAIL for target artifact, informative**.

Runtime screenshots show the upside-down avatar-reflection hole remains present in the final composite. In `No-hit crossing candidate path`, the target remains ORANGE with `Disocclusion Skips = 3` and `Hit Thickness = 0.18`.

v0.23 changed only binary refinement depth from 5 to 9 iterations. Since the same candidate remains oversized after the deeper refinement, the target is not explained by insufficient binary-search iteration count.

Interpretation:

- the ray reaches a real negative-to-positive crossing candidate;
- binary refinement converges, but the refined positive-side sample remains farther than global `Hit Thickness`;
- this is characteristic of a screen-depth discontinuity/silhouette boundary rather than a smooth depth surface;
- simply increasing refinement or global thickness is therefore the wrong fix.

Next revision should preserve `Disocclusion Skips = 3` and add a conservative silhouette/depth-edge recovery path only when an oversized candidate would otherwise exhaust the disocclusion skip budget. This avoids regressing the already-useful skip path while allowing a genuine reflected silhouette entry to become a hit.
