# SSR v0.15 PBRAlphaProbe runtime

Date: 2026-08-19

Result: **INCONCLUSIVE / selector miss**

Observed:

- Native overlay version was correct: `SL Probe Lighting v1.6.11 ... (v0.15 PBRAlphaProbe)`.
- ReShade display mode was `PBR alpha-blend path probe mask`.
- The displayed probe mask was fully black in the supplied frame; the known glass fixture did not light up.

Interpretation:

This does **not** prove that PBR alpha/glass cannot be captured. v0.15 intentionally snapshots only the first contiguous PBR-alpha segment. A black mask can mean the first-segment selector missed the target segment, the before/after timing did not span the glass draw, or the PBR-alpha signature needs refinement. The lower native PBR-alpha counters were not visible in the supplied screenshot, so do not infer `draws = 0` from this frame alone.

The known glass fixture remains recorded in `SSR_v0.15_PBRAlphaProbe_FIXTURE.md`. Glass work is parked while an opaque SSR disocclusion artifact is fixed.
