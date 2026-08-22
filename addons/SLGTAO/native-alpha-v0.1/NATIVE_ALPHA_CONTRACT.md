# GTAO native alpha-geometry contract

This contract replaces every post-process alpha heuristic.

## `SL_ALPHA_MATERIAL`

Binary or normalized geometry-classification texture.

It is written only by scene geometry routed through Firestorm alpha/cutout render categories. The v0.1 native replay includes `PASS_ALPHA`, `PASS_ALPHA_MASK`, `PASS_FULLBRIGHT_ALPHA_MASK`, the legacy material mask passes, `PASS_GLTF_PBR_ALPHA_MASK`, grass/tree cutout paths, and corresponding rigged variants where applicable.

Explicitly excluded at capture time: sky, WL sky, clouds, particles, HUD and HUD particles.

Do not derive this semantic from framebuffer alpha, G-buffer alpha, final image opacity, D0 validity, normals or specular payload.

## `SL_DEPTH_ALPHA_NATIVE`

Nearest eligible alpha-geometry fragment depth in the same native camera/projection and raw depth convention as `SL_DEPTH_PRIMARY_NATIVE`.

- full native viewport resolution;
- background/empty = 1.0;
- nearest eligible alpha fragment wins via private `GL_LESS` depth;
- never modifies Firestorm's primary D0 depth buffer.

## `SL_ALPHA_COVERAGE`

Coverage/opacity for the same eligible fragment represented by `SL_DEPTH_ALPHA_NATIVE`.

- surviving alpha-mask/cutout fragments contribute 1;
- alpha-blended fragments preserve authored fragment alpha after texture/vertex-alpha evaluation;
- cloud opacity never enters this semantic because clouds are excluded by renderer classification.

## GTAO consumption

GTAO resolves one visible geometry depth:

`Dvisible = nearest(D0, Dalpha)` when native alpha material is eligible and coverage is non-zero.

Every depth-dependent GTAO stage must use that same resolved depth: linear-depth diagnostics, raw horizon search, depth-discontinuity rejection, bilateral depth weights and final AO contribution.

## Current limitation

Forward alpha geometry may not populate Firestorm's deferred normal buffer. v0.1 therefore proves classification/depth/coverage first. If alpha surfaces need their own surface orientation for AO receiving/filtering, publish `SL_NORMAL_ALPHA_NATIVE` from the same eligible native replay as a later semantic instead of reusing stale deferred normals behind the transparent surface.

## Optional future semantic

`SL_CLOUD_MASK` may be captured directly from `renderSkyCloudsDeferred()` / `RENDER_TYPE_CLOUDS` for SSR/environment work. It is intentionally separate from GTAO alpha-material classification.
