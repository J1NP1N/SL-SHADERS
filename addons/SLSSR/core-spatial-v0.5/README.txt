CORE+SPATIAL — Full-Res Background-Bracket Fix v0.5

Branch: agent/ssr-spatial
Parent failed runtime: b6847049b0d841b63acc8ea6157b0d7ebef6e1a7 (v0.4)
FX: SL_SSR_CORE_SPATIAL_v0_5.fx
Build: python build_v0.5_from_v0.2.py
FX SHA-256: 90f875b3f622d7e5301ce98413d52a9c0755adb1b10683079bf2c05773ff86c7

Diagnosis
---------
v0.3/v0.4 pixel-center snapping was not the missing half->full conversion. ReShade fullscreen TEXCOORD is already normalized across the pass viewport. v0.5 therefore returns to the normalized-UV access contract of v0.2 while keeping Raw/Meta/BlurH/Resolved at BUFFER_WIDTH x BUFFER_HEIGHT.

The actual leftover obsolete path was inside TraceSSR: clear/background samples still set previousValid=true and previousDelta=-1e6. The next geometry sample with delta>=0 could therefore synthesize a negative->positive crossing even though the negative side was empty background. Binary refinement then converged onto a screen-space depth discontinuity. This was underlying background-entry recovery behavior that remained after its UI/permissive acceptance branch was removed. Full-resolution launch exposed it at many more silhouette pixels and produced broad false world hits.

Correction
----------
- background/clear now invalidates previousValid; empty space cannot be a geometric bracket side
- blocked background->positive geometry events are diagnostic only and cannot be refined/accepted
- Display Mode 37: Blocked background-entry crossing mask (orange)
- duplicate Mode 22 test corrected so Mode 23 is reachable
- Mode 34 masks invalid/excluded receivers before showing resolve radius
- v0.3/v0.4 explicit pixel-center snapping and POINT-only RT access are not carried forward

Preserved
---------
- full-resolution SLSSRRawTex / SLSSRMetaTex / SLSSRBlurHTex / SLSSRResolvedTex
- D0 = SL_DEPTH_PRIMARY_NATIVE
- Dstatic = SL_DEPTH_BACKGROUND
- Cstatic = SL_COLOR_BACKGROUND
- DavatarBack = SL_DEPTH_AVATAR_BACK
- AVATAR remains exactly [D0,DavatarBack]
- WORLD remains Dstatic/Cstatic
- current Spatial roughness/material and bilateral resolve math
- DDA remains absent
- Disocclusion Skips, Background Entry Recovery, Silhouette Edge Recovery and Deferred Candidate Fallback remain absent
- no Hi-Z, Temporal or separate Avatar Receiver integration

Runtime order
-------------
CORE+SPATIAL v0.5 ON; CORE v0.49 OFF; TEMPORAL OFF; HIZ DEBUG OFF; AVATAR RECEIVER OFF.
1. Mode 37: orange should mark where the old synthetic bracket is now blocked.
2. Mode 31: broad false world structures corresponding to Mode 37 must be absent.
3. Mode 32: confirm GOOD avatar coverage unchanged.
4. Modes 34 and 36: verify receiver-space alignment.
5. SSR contribution and Final composite: verify correct reflection placement with no broad false-positive world hits.
6. Confirm GOOD avatar reflection and no pale/white secondary-avatar ghost.
