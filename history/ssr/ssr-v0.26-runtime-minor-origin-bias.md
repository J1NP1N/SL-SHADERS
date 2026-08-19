# SSR v0.26 OriginBiasAudit runtime result

Date: 2026-08-19

User report: reducing the independently controlled ray-origin bias makes the avatar-shaped missing reflection **a little better**, but the artifact remains clearly present.

Interpretation:

- The old coupling `Ray Origin Bias = Hit Thickness * 0.75` was a real geometric bug and materially perturbed the reflected ray.
- Correcting the bias changes the boundary of the artifact slightly, so origin displacement is a contributing factor.
- It is **not** the root cause of the avatar-shaped missing reflection.
- Do not continue treating the symptom as a generic hole to be filled.

New isolation question:

> What is the first oversized crossing candidate that the marcher discards on rays which later terminate with no accepted hit?

Plausible failure chain to test directly:

`floor receiver -> reflection ray reaches avatar -> avatar silhouette produces a large positive depth jump -> current code classifies candidate as disocclusion -> candidate is skipped -> no later crossing -> BLUE/no reflection`

If the first discarded candidate samples the avatar itself, then the valid reflection hit is being deliberately thrown away as a false disocclusion. The next diagnostic should identify the discarded candidate rather than modify hit acceptance.

Keep `Disocclusion Skips = 3`, `Hit Thickness = 0.18`, and corrected `Ray Origin Bias = 0.010` for that isolation test.
