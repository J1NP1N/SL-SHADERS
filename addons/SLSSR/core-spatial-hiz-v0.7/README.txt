CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.7

Packaging/preprocessor fix only for the accepted v0.6 integration.

Problem:
v0.6 runtime FX referenced an adjacent custom include:
  #include "SL_HIZ53_WORLD_TRACE_INTEGRATION.fxinc"
The chat handoff attached only the .fx, so ReShade could not open that file.

Correction:
- inline the exact validated v0.53 WORLD integration block into the runtime FX
- remove the custom include dependency
- retain only the standard ReShade.fxh include
- update runtime identifier/label from v0.6 to v0.7

No shader behavior changes:
- WORLD Hi-Z v0.53 tracer unchanged
- temporary old-WORLD/Hi-Z A/B selector unchanged
- AVATAR [D0,DavatarBack] unchanged
- WORLD/AVATAR arbitration unchanged
- Raw/Meta unchanged
- full-resolution buffers unchanged
- Spatial resolve/AA unchanged
- materials/roughness unchanged
- Cstatic sampling/composite unchanged
- no Temporal, DDA, or removed recovery path added

Validation:
After replacing the inlined block with the original v0.6 include directive and
normalizing the v0.7 identifiers back to v0.6, the source is byte-for-byte equal
to the accepted v0.6 generated FX.

FX SHA-256:
387229c2afdbb1257c32c6a327cc5a55f25e970d7da0492b54e4df35bcc09bde
