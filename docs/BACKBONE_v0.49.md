# SSR v0.49 Backbone

Branch: `agent/ssr-background-depth`

The integration backbone is `SL_SSR_v0_49_AvatarThicknessTrace.fx` plus the native four-buffer bridge.

## Required semantics

| Semantic | Meaning |
|---|---|
| `SL_DEPTH_PRIMARY_NATIVE` | D0: nearest visible depth |
| `SL_DEPTH_BACKGROUND` | Dstatic: avatar-free/static world depth |
| `SL_COLOR_BACKGROUND` | Cstatic: avatar-free/static world color |
| `SL_DEPTH_AVATAR_BACK` | DavatarBack: avatar/rigged backface/exit depth |

## Trace split

WORLD trace:

`Dstatic -> Cstatic`

AVATAR trace:

`D0 + DavatarBack -> scene-linear avatar color`

Avatar hits are valid only inside `[D0, DavatarBack]`. Samples behind the exit surface are not avatar geometry.

This is the structural fix for the former secondary avatar-shaped ghost and is a hard integration constraint for parallel work.

## Preserve

- good avatar reflection on reflective world surfaces;
- native scene pair alignment;
- native avatar back-depth interval;
- v0.49 world/avatar trace separation;
- DDA disabled by default/user preference.

## Do not revive

- screen-space flipped-avatar reflection;
- confidence-only ghost culling;
- accepted-stretch threshold as avatar eligibility;
- D0/Dstatic foreground substitution;
- global final-frame blur as an SSR cleanup mechanism.

## Current known defect

Static-world hit coverage can be ragged/stippled at grazing angles and corners. The avatar-only hit mask is clean. Work on this defect must not destabilize the avatar thickness branch.

## Intended parallel extensions

1. Roughness-aware depth/normal-aware spatial resolve.
2. Temporal accumulation and reprojection.
3. Hi-Z static-world traversal.

These should be developed as separable branches from this backbone and merged only after independent runtime validation.
