# SSR v0.17 DisocclusionSkip — runtime result

Date: 2026-08-19

Result: **FAIL for recovery, informative**.

User supplied diagnostics showing the avatar-shaped missing-reflection region is visible not only in the final composite but also in `Ray hit mask` and `Reflection base removal x10`.

Interpretation:

- The remaining artifact is upstream of material weighting and composite.
- v0.16 energy-style receiver replacement removed the dark cast-shadow bleed, but it cannot fill pixels where no SSR hit exists.
- v0.17's limited oversized-depth-crossing skip did not recover the missing reflected background.
- The camera-angle dependence and hole already present in the ray-hit mask indicate a true screen-space disocclusion / single-layer visibility limitation: the background behind the foreground avatar is absent from the current screen depth/color buffers.

Conclusion:

Do not continue tuning thickness, crossing count, or skip confidence as the primary fix. The next approach should supply missing reflection information from outside the current single-frame, single-layer ray result, e.g. temporally reprojected valid SSR history with confidence/rejection and/or a spatial/probe fallback for unresolved holes.

Keep v0.16 energy composite behavior; it solved the dark receiver/shadow bleed component of the artifact.
