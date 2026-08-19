# SSR v0.13 LegacyRGBResponse — runtime result

Date: 2026-08-19

Result: **PASS for the targeted legacy-response correction.**

Runtime evidence on the existing mixed test scene:

- `SSR contribution` is visibly non-black and contains colored reflected scene signal on legacy material surfaces.
- `Final reflection weight x10` is strongly nonzero on the legacy test cube.
- This is after the material-class diagnostic had already confirmed the cube is legacy/cyan and the bridge status is healthy/cyan.

Interpretation:

v0.13 successfully removed legacy `specularRect.a` / glossiness as a reflectivity gate and allowed the published legacy `specularRect.rgb` to drive the reflected contribution. The old `A=0` condition no longer annihilates legacy SSR.

The `Final reflection weight x10` view also shows visible speckling/noise across portions of the ground and scene. That is a separate ray/weight stability problem and is not folded into the v0.13 pass/fail judgment. Do not regress the material-response fix while investigating that later.

A normal composite screenshot was not included in this runtime report, so final presentation strength/quality is not yet judged here. v0.13 proves signal path and weighting activation only.
