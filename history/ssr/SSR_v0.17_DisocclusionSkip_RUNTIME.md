# SSR v0.17 DisocclusionSkip — runtime result

Date: 2026-08-19

Result: **FAIL for recovery, informative; original interpretation corrected after follow-up**.

User supplied diagnostics showing the avatar-adjacent missing-reflection region is visible not only in the final composite but also in `Ray hit mask` and `Reflection base removal x10`.

Initial interpretation incorrectly treated the black region as unavailable background/disocclusion data. The user clarified the diagnostic polarity: **white is the good/accepted reflection hit; the black in-between region is the defect.**

Follow-up test:

- `Hit Thickness` was raised as high as `0.30` while the problematic camera angle remained in view.
- Reflected color remained good where SSR was already valid.
- The black/missing region did **not** fill in.

Corrected conclusions:

- The artifact is upstream of material weighting and final composite because it is already present in the ray-hit diagnostic.
- v0.16 energy-style receiver replacement remains useful; it removed the old dark cast-shadow bleed component.
- v0.17 oversized-crossing skip did not fix the missing hit region.
- **Hit Thickness is not the controlling failure for this region.** Do not continue global thickness tuning as the next step.
- The remaining trace failure has not yet been identified. Candidate termination paths include reflected-ray direction rejection, leaving the projected screen/view, exhausting the trace before a crossing, oversized-crossing rejection after the skip budget, or confidence reaching zero.

Next step: use v0.18 `Ray termination reason` to color-code the exact TraceSSR failure path on the black region before making another algorithmic change.
