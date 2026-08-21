CORE+SPATIAL — Full-Res Coverage v0.2

Branch: agent/ssr-spatial
Parent runtime milestone: 03368099f4f0dc8e984fb4f8ba70163c73687352
FX after restore: SL_SSR_CORE_SPATIAL_v0_2.fx
Restore: python restore_core_spatial_v0.2.py
FX SHA-256: 89c2bef07f9e7b43163ee947c471906777dbfabc1c6dfbda3bb9719520954348

Purpose
-------
Production CORE cleanup plus a correctness-first reflection-edge coverage fix.
This is a full-file v0.49 superset with the existing Spatial resolve included.
It replaces ordinary CORE v0.49 during isolated testing; never enable both.

Validated rendering contract preserved
--------------------------------------
- D0 = SL_DEPTH_PRIMARY_NATIVE.
- Dstatic = SL_DEPTH_BACKGROUND.
- Cstatic = SL_COLOR_BACKGROUND.
- DavatarBack = SL_DEPTH_AVATAR_BACK.
- WORLD trace intersects Dstatic and samples Cstatic.
- AVATAR trace remains inside the native [D0, DavatarBack] interval.
- WORLD and AVATAR traces remain independent; nearest accepted point wins.
- Spatial roughness/material response and bilateral resolve math are unchanged.

Production-path cleanup
-----------------------
Removed completely from this FX:
- the obsolete DDA implementation, branch, fallback, settings, helpers, UI,
  and DDA trace-status diagnostic;
- Disocclusion Skips and skipped-hit confidence/path;
- Background Entry Recovery and its confidence/path;
- Silhouette Edge Recovery and all edge-recovery gates/path;
- Deferred Candidate Fallback and saved-candidate path;
- Trace Through Foreground debug path, which depended on unlimited skip behavior;
- diagnostics exposed solely for the deleted paths.

Useful trace diagnostics retained
---------------------------------
Display Mode 22: Ray termination reason
Display Mode 23: No-hit depth history
Display Mode 24: No-hit closest depth delta
Display Mode 25: No-hit crossing candidate path
Display Mode 26: Accepted hit distance
Display Mode 27: Accepted screen stretch
Display Mode 28: Receiver grazing angle
Display Mode 29: Long-ray fade mask
Display Mode 30: Excluded/rigged receiver mask
Display Mode 31: Static-world accepted-hit mask
Display Mode 32: Avatar-only accepted-hit mask
Display Mode 33: Dual-trace selected layer
Display Mode 34: Resolve radius
Display Mode 35: Resolved SSR confidence/coverage
Display Mode 36: Resolve rejection: avatar R / depth G / normal B

Root-cause diagnosis and correction
-----------------------------------
The visible stair-step boundary is already present in the static-world accepted-hit
mask, before Spatial filtering. In the previous active source, SLSSRRawTex was
BUFFER_WIDTH/2 x BUFFER_HEIGHT/2, so only one binary accepted-hit decision was
launched per 2x2 full-resolution receiver pixels. The raw hit mask therefore had
half-resolution coverage quantization before any resolve could operate.

Historical trace-core testing also established that increasing binary refinement
from 5 to 9 iterations did not correct the relevant depth-discontinuity failure
class. The current production fix therefore does not loosen thickness or add an
edge heuristic.

v0.2 changes SLSSRRawTex, SLSSRMetaTex, SLSSRBlurHTex, and SLSSRResolvedTex to
BUFFER_WIDTH x BUFFER_HEIGHT. CORE now launches one receiver ray per screen pixel,
and the existing Spatial resolve preserves that coverage through the final SSR
contribution. This is correctness-first and intentionally more expensive.

Runtime test procedure
----------------------
Technique state for isolated testing:
1. CORE+SPATIAL — Full-Res Coverage v0.2: ON
2. CORE v0.49: OFF
3. TEMPORAL: OFF (both PRE and POST variants if present)
4. HIZ DEBUG: OFF
5. Keep the separate AVATAR RECEIVER experiment OFF for this isolated CORE test.

Never enable CORE+SPATIAL and ordinary CORE v0.49 at the same time.

At the exact same camera/test geometry used for the current jagged edge:
A. Select Display Mode 31, Static-world accepted-hit mask. Compare silhouette and
   grazing/corner boundaries against the previous CORE+SPATIAL runtime.
B. Select Display Mode 22, Ray termination reason, and Mode 25, No-hit crossing
   candidate path, if any residual holes remain. These distinguish trace-budget /
   crossing / thickness rejection without changing acceptance.
C. Select Display Mode 32, Avatar-only accepted-hit mask. Confirm the avatar path
   remains clean and stable.
D. Select Display Mode 33, Dual-trace selected layer. Confirm world/avatar winner
   selection remains physically nearest along the same reflected ray.
E. Return to Final composite. Confirm reflected silhouettes are materially smoother,
   with no broad false-positive hits.
F. Recheck the established avatar scene: GOOD avatar reflection must remain and the
   pale/white secondary avatar ghost must not return.

No Hi-Z or temporal logic is integrated in this FX. The separate Avatar Receiver
effect is not modified by this milestone.
