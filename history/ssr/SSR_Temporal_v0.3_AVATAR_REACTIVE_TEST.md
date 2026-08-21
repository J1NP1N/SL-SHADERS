# SSR Temporal v0.3 Avatar-Reactive Runtime Test

Branch: `agent/ssr-temporal`

## Scope

Fix the Temporal v0.2 failure where avatar movement leaves reflected legs/body
history trails. This revision is temporal-only and remains separable from the
Spatial branch.

Production validation target: the accepted `CORE+SPATIAL` runtime artifact.
Plain v0.49 is ancestry, not the production validation target.

## Root cause

The stale reflected-avatar history survives because v0.2's geometry validation
tracks the reflective receiver, not the reflected source object:

1. Receiver D0 remains stable when the avatar moves only in reflection.
2. Receiver normal remains stable.
3. Current/history contribution validity is binary, so both frames pass when both
   contain any SSR contribution even if reflected content identity changed.
4. Radiance rejection was permissive (`0.20 -> 0.85`).
5. The 3x3 neighborhood clamp uses independent RGB min/max bounds, so stale RGB
   can remain inside the box without matching any actual current sample.
6. Camera motion trust has no knowledge of avatar animation and must not be treated
   as object motion.

## Exact change

New FX:
`addons/SLSSR/temporal-v0.3/SL_SSR_Temporal_v0_3_AvatarReactive.fx`

- hard-disable history jitter; compatibility control remains fixed at `0.00` and
  is not used in history sampling;
- radiance reject defaults: start `0.12`, end `0.55`;
- add actual 3x3 nearest-sample normalized RGB support test;
- animated-content reject defaults: start `0.10`, end `0.30`;
- multiply accepted history weight by reactive content trust;
- hard reject unsupported stale content with existing reject code 8;
- add a third diagnostic MRT only; no trace/core/native change.

## Technique order

1. `TEMPORAL PRE — v0.3 Capture`
2. `CORE — ...` accepted CORE+SPATIAL production technique
3. `TEMPORAL POST — v0.3 Avatar-Reactive Resolve`

Keep them adjacent.

## Effects OFF for isolated test

- Temporal v0.2 PRE and POST
- Motion Bridge Probe after confirming bridge motion availability
- other temporal experiments
- HIZ DEBUG
- AVATAR RECEIVER
- alternate/legacy CORE
- duplicate standalone SPATIAL if already incorporated in the accepted production CORE

## Diagnostic procedure

Use the same reflective floor/wall where moving avatar legs previously left a
visible trail.

1. `History jitter status (hard off)` must be black and the UI control must show
   `0.00`.
2. With avatar stationary, view `History weight`: stable world receivers should
   retain visible history weight.
3. Move avatar legs/body while keeping camera movement minimal.
4. At the old reflected silhouette location inspect:
   - `Depth agreement`
   - `Normal agreement`
   - `History rejection reason`
   - `Neighborhood clamp amount`
   - `Reactive gate audit (R=transition G=radiance B=unsupported)`
   - `Reactive history trust`
   - `History weight`
5. Expected failure diagnosis from v0.2 lineage:
   - depth/normal often stay accepted because receiver is static;
   - transition R often stays 0 because both contributions are valid;
   - clamp amount may stay low;
   - G/B should expose changed/unsupported reflected content.
6. Expected v0.3 behavior:
   - reactive trust goes dark on stale avatar history;
   - history weight collapses there;
   - hard cases show rejection code 8 / salmon;
   - current reflection shape follows the current CORE+SPATIAL result without a
     trailing copy.
7. Stop avatar movement and inspect unrelated static reflections. They should
   reacquire/retain temporal weight instead of globally rejecting history.

## Acceptance

PASS only if all are true:

1. no visible persistent trail behind moving reflected legs/body;
2. stationary reflections still gain temporal stability;
3. no whole-screen jitter;
4. no material reflection-shape change relative to current CORE+SPATIAL;
5. no excessive history destruction across unrelated static receivers.

If any fail, report screenshots for `History weight`, `History rejection reason`,
`Reactive gate audit`, and `Reactive history trust` before tuning thresholds.
