# SSR v0.35-v0.49 Runtime Record

This file records the runtime conclusions needed to understand why v0.49 is the current backbone.

## Stable facts before v0.38

- Primary camera depth D0 was available.
- Native Dstatic and Cstatic were later added as a simultaneous avatar-free static-world scene pair.
- Original secondary avatar ghost existed before Dstatic/Cstatic existed; therefore those buffers did not cause the original bug.
- Good avatar reflection is the skin-colored/normal reflection on the receiver. Bad artifact is the secondary white/pale avatar-shaped region.

## v0.38 BackgroundScenePair

Dstatic accepted hits resolved through Cstatic. The previous dark/black contamination became a bright background-colored smear/lobe while the good avatar reflection remained. Background color was therefore not the root cause.

## v0.39 StaticWorldTrace

Tracing only Dstatic/Cstatic removed the avatar contamination but also removed the good avatar reflection. Conclusion: static-world independence was useful but avatar reflection needed a separate real path.

## v0.40-v0.44 rejected approaches

v0.40: screen-space mirrored avatar source produced a wrong translucent/vertical smear.

v0.41: D0→Dstatic foreground substitution attacked the wrong thing.

v0.42/v0.43: accepted-screen-stretch looked diagnostically useful in some views, but directly using/gating by it damaged valid avatar reflections.

v0.44: constraining the resolved reflection to center-pixel raw hit support did not remove the white lobes.

## v0.45 BackgroundHitContinue

The `Background-layer accepted-hit mask` became black, proving the Dstatic/background accepted-hit path could be removed. The bad pale strip still existed in `SSR contribution` and final composite. Therefore the surviving artifact came from another accepted trace path.

## v0.46 PrimaryHoldRelease

The released-primary-foreground diagnostic was essentially black. The tested short-travel primary-hold branch was not the culprit.

## v0.47 DualTrace — decisive isolation

Two real traces were separated:

- world: Dstatic/Cstatic;
- avatar: D0 on rigged/foreground pixels.

`Dual-trace selected layer` showed the broad world region as cyan and the bad vertical region as magenta. `Avatar-only accepted-hit mask` showed the entire bad tall band. Conclusion: the avatar-only D0 trace itself recreated the ghost from the camera-visible avatar silhouette.

## v0.48 AvatarStretchGate — reject

A minimum screen-stretch threshold removed valid avatar reflection along with the bad region. Stretch was not a unique classifier.

## Native avatar thickness v0.3.6b

Firestorm gained a dedicated rigged/avatar backface depth target, exported as DavatarBack and published to ReShade as `SL_DEPTH_AVATAR_BACK` by bridge v0.4.

`SL_AvatarThicknessProof_v0_1.fx` `Valid backface mask` produced a clean cyan avatar silhouette aligned with the avatar. PASS.

## v0.49 AvatarThicknessTrace — current backbone

The world trace remains Dstatic/Cstatic.

The avatar trace now treats `[D0,DavatarBack]` as the actual avatar volume. A reflected ray can hit the avatar only while it lies inside that interval. Once it passes behind DavatarBack, that screen pixel is empty for the avatar trace.

Runtime: the original secondary avatar ghost is essentially solved while the good avatar reflection remains.

Remaining issue: static-world accepted-hit coverage is ragged/stippled at grazing/corner transitions. Avatar-only accepted-hit mask is clean. DDA is not desired.
