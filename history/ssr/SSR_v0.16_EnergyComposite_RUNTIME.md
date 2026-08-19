# SSR v0.16 EnergyComposite runtime

Date: 2026-08-19

Result: **PARTIAL PASS**

Observed:

- The previously dark cast-shadow ghost under/through the strong floor reflection is no longer dark after the energy-style base replacement.
- A camera-angle-dependent avatar-shaped region remains where SSR is missing rather than merely dark.
- User description: the remaining area looks like SSR is absent behind the avatar and changes with camera angle.

Interpretation:

v0.16 successfully addressed the additive-composite/base-energy problem. The remaining artifact is a different class: a screen-space disocclusion/visibility hole.

The current marcher explicitly rejects an oversized depth crossing after binary refinement when the crossing exceeds `SSRThickness`. Foreground occluders such as the avatar can therefore terminate a reflected ray before it reaches recoverable background screen data.

Next revision should leave v0.16 material and energy-composite behavior intact and test a limited skip-through of oversized crossings with reduced confidence. If that cannot recover the hole, move to temporal/spatial/probe fallback rather than more receiver-composite tuning.
