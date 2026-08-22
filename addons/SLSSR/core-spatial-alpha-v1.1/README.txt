CORE+SPATIAL — Native Alpha Diagnostics v1.1

Base
----
agent/ssr-spatial production base: 7067519e973d464818ba54c3128108ab4cbba67f
Technique: CORE+SPATIAL — Native Alpha Diagnostics v1.1
Expected restored FX SHA-256:
b26229c5041affbe2c39ae90c7437ee9f20e5fe1026a1f5c3860f8e312bdcee5

Scope
-----
Diagnostics-only native-alpha semantic integration. Display Mode 0 preserves the
existing CORE+SPATIAL production behavior. No Firestorm/native capture changes.
No Temporal integration. DDA/recovery paths remain removed.

Preserved contracts
-------------------
- D0 = SL_DEPTH_PRIMARY_NATIVE remains the visible/front-depth backbone.
- WORLD remains the existing Dstatic/Cstatic path (old/Hi-Z A/B retained).
- AVATAR remains the validated [D0,DavatarBack] thickness interval.
- SL_DEPTH_ALPHA_NATIVE never substitutes for DavatarBack.
- Existing WORLD/AVATAR nearest arbitration, Raw/Meta, full-res buffers,
  Spatial resolve/AA, materials/roughness, Cstatic color sampling and final
  composite are not changed in normal Display Mode 0.

Native semantic bindings
------------------------
- SL_ALPHA_MATERIAL
- SL_DEPTH_ALPHA_NATIVE
- SL_ALPHA_COVERAGE
The bridge-validity and viewport-registration uniforms use the same names and
mapping as SL_NativeAlphaProof_v0_1.fx on agent/native-alpha-geometry.

Receiver association
--------------------
Native alpha may classify the visible receiver only when native alpha depth and
D0 coincide in reconstructed view depth. Default diagnostic tolerance:
- Alpha Receiver Depth Match = 0.030 view units
- Alpha Receiver Relative Match = 0.0010
Hidden alpha behind opaque D0 is reported separately and never becomes the
visible alpha receiver in these diagnostics.

Diagnostic-only ray model
-------------------------
A separate supplemental alpha-depth tracer follows the visible D0 receiver's
existing reflection ray. It is not wired into production TraceSSR, Hi-Z,
arbitration, Raw/Meta, Spatial or Final. A valid alpha intersection supplies
native authored coverage as blocker weight; diagnostic transmittance is
1 - blockerWeight. Missing alpha samples are empty transport space and do not
form synthetic recovery brackets.

Display modes
-------------
39  NATIVE ALPHA — Material classification
40  NATIVE ALPHA — Coverage
41  NATIVE ALPHA — Depth raw
42  NATIVE ALPHA — Receiver coincidence: behind R / match G / front B
43  NATIVE ALPHA — Receiver class: cutout cyan / fractional yellow
44  NATIVE ALPHA — SSR ray candidate
45  NATIVE ALPHA — SSR blocker weight
46  NATIVE ALPHA — SSR transmittance
47  NATIVE ALPHA — SSR before alpha handling
48  NATIVE ALPHA — SSR after alpha handling PREVIEW
49  NATIVE ALPHA — Environment: blocker R / WORLD hit G / escape B
50  NATIVE ALPHA — Semantic status M/D/C = R/G/B

Modes 39-49 fail closed to magenta if bridge registration or any of the three
semantic validity flags is unavailable. Mode 50 shows the individual validity
flags directly.

Runtime gate
------------
Enable only CORE+SPATIAL — Native Alpha Diagnostics v1.1 for this test.
Keep ordinary CORE/v0.49, older CORE+SPATIAL versions, Temporal PRE/POST,
standalone HIZ DEBUG and AVATAR RECEIVER effects OFF.

1. Mode 50 should be white (all M/D/C semantic-valid channels present).
2. Modes 39-41: confirm material/depth/coverage register to the native alpha
   geometry; sky/WL sky/clouds should not appear as alpha material.
3. Mode 42: opaque object in front of an alpha object must show RED on the hidden
   alpha region, never GREEN. GREEN is the only receiver-alpha association.
4. Mode 43: cutout survivors should be CYAN; authored fractional alpha should be
   YELLOW with intensity tracking coverage; holes should be black.
5. Mode 44: inspect reflected-ray alpha candidate coverage.
6. Modes 45/46: blocker weight and transmittance must be complementary.
   Cutout coverage 1 -> blocker 1 / transmittance 0. Fractional blend -> partial.
7. Modes 47/48: compare current resolved SSR with the diagnostic-only
   transmittance preview. This does not alter normal Display Mode 0.
8. Mode 49: RED is a genuine alpha blocker before the existing selected SSR hit,
   GREEN is an accepted existing WORLD hit, BLUE is WORLD escape.
9. Return to Display Mode 0 and confirm opaque SSR and GOOD avatar reflections
   are visually unchanged from the base build.

Do not advance production alpha behavior until these diagnostics are proven.
