# SSR v0.25 SilhouetteGate runtime result

Date: 2026-08-19

Runtime settings retained:

- `Disocclusion Skips = 3`
- `Hit Thickness = 0.18`
- v0.24 silhouette thresholds unchanged
- display: `Silhouette-edge gate reason`

Observed result:

The target upside-down avatar-shaped missing reflection region is dominated by the ordinary BLUE/no-crossing color, not by the v0.25 terminal silhouette-gate failure colors (yellow/magenta/orange/cyan/red).

Interpretation:

- v0.22 already proved target rays form oversized negative-to-positive candidates.
- v0.25 shows that for most target pixels the terminal silhouette gate is never reached.
- The likely flow is: one or more oversized candidates consume normal `Disocclusion Skips`, then the ray later terminates as ordinary no-crossing before the skip budget is exhausted.
- This explains why v0.24 recovered only sparse isolated pixels: only rays that reach a terminal oversized candidate after exhausting the skip budget can enter the silhouette-edge recovery branch.

Conclusion:

v0.24/v0.25's terminal-only silhouette recovery architecture is structurally misplaced for the target artifact. Silhouette-vs-disocclusion classification must occur at each oversized crossing candidate, not only after all three disocclusion skips are spent.

Do not reduce `Disocclusion Skips` from 3; that setting remains the known-good handling for the separate disocclusion problem.

Next immediate comparison remains v0.26 OriginBiasAudit to decouple ray-origin bias from `Hit Thickness`, followed by the prepared v0.28 ScreenDDA prototype if needed.
