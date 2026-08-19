# SSR v0.12 ReShadePublish — runtime result

Date: 2026-08-19

Build: **SLProbeLighting v1.6.10 / SSR v0.12 ReShadePublish**

## Result

**PASS — ReShade-side publication of the main-pass material G-buffer is proven.**

Runtime screenshots showed:

- `SL_GBUFFER_SPECULAR input source: GATED MAIN-PASS SNAPSHOT`
- `SL_GBUFFER_SPECULAR FX publication: RESHADE-OWNED COPY`
- `SL_GBUFFER_SPECULAR semantic bound: YES`
- `Published specular target: tex 983, 3840 x 2027`
- `Display Mode -> G-buffer specular RGB` visibly displayed scene/material variation instead of black.

This closes the v0.11 failure where the gated private/native GL texture could report semantic-bound while the FX still sampled black.

## Interpretation

The acquisition chain established by v0.10 remains valid, and v0.12 proves the missing interoperability step: copy the captured material payload into a ReShade-owned render target before exposing it to the FX.

The manual `Analyze SL_GBUFFER_SPECULAR now` CPU readback showed zeroes in the later screenshot. That does not invalidate the publication proof: Analyze operates on the frozen/native proof source at the time the button is pressed, whereas the live FX diagnostic visibly sampled the published ReShade-owned copy. The live shader-visible output is the authoritative test for v0.12's hypothesis.

## Next step

Do not alter SSR strength/weighting yet. Use the existing FX material-class diagnostic on the same scene:

- `Material class: legacy cyan / PBR magenta`
- `Bridge status`

Once the real G-buffer flag classification is known, apply the correct legacy/PBR material interpretation and then resume SSR response/weighting work.
