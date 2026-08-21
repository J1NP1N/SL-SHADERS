SL SSR Temporal v0.3 — Avatar-Reactive Resolve

Purpose
-------
Runtime follow-up to Temporal v0.2 for reflected-avatar movement ghosting.
This remains a separable presentation-delta temporal wrapper. It does not modify
CORE trace logic and does not require access to the Spatial branch source.

Production validation target
----------------------------
The runtime production target is the currently accepted CORE+SPATIAL artifact.
Plain v0.49 is historical ancestry only for this test.

Required technique order
------------------------
Keep exactly this functional order, adjacent:

1. TEMPORAL PRE — v0.3 Capture
2. CORE — accepted CORE+SPATIAL production core
3. TEMPORAL POST — v0.3 Avatar-Reactive Resolve

Do not place any unrelated effect between PRE, CORE, and POST. The temporal layer
measures the exact presentation-space contribution produced between its capture
and resolve passes.

Isolated-test effects OFF
-------------------------
Disable during isolated v0.3 validation:
- Temporal v0.2 PRE/POST;
- TEMPORAL POST — Motion Bridge Probe after motion availability has been verified;
- all alternate temporal implementations;
- HIZ DEBUG techniques;
- AVATAR RECEIVER techniques;
- alternate/legacy CORE implementations;
- duplicate standalone SPATIAL passes if the accepted production CORE already
  includes the Spatial resolve being validated.

Do not run a second presentation-changing effect between v0.3 PRE and POST.

Root cause addressed
--------------------
Temporal v0.2 validates camera-reprojected receiver geometry. For a moving avatar
reflected in a stationary floor/wall, the receiver D0 and receiver normal stay
stable, so depth/normal rejection correctly pass even though reflected content
has moved.

The v0.2 current/history transition is binary: both frames are considered valid
whenever both have any nontrivial SSR presentation contribution. A stale avatar
reflection can therefore survive when the old avatar contribution is replaced by
some other valid SSR contribution.

The v0.2 3x3 clamp is an RGB axis-aligned min/max envelope. A stale avatar color
can lie inside those independent channel bounds even when no actual current sample
matches that RGB. Clamp amount then stays small and history remains weighted.

v0.3 change
-----------
- History jitter is hard-disabled in code. The compatibility control is fixed at
  0.00 and is not consumed by history sampling.
- Center radiance rejection defaults are more reactive:
    start 0.12, end 0.55.
- Adds an actual current-neighborhood content-support gate. The reprojected history
  RGB is compared against each real current 3x3 SSR-contribution sample using a
  normalized RGB distance. The minimum distance is the unsupported-content metric.
- Animated Content Reject defaults:
    start 0.10, end 0.30.
- The unsupported-content trust multiplies history weight and hard-rejects at the
  end threshold. It does not blur or reshape current reflection geometry.
- No per-object/avatar motion vector is fabricated.

Diagnostic
----------
Existing displays remain useful:
- History weight
- History rejection reason
- Depth agreement
- Normal agreement
- Neighborhood clamp amount

New displays:
- Reactive gate audit (R=transition G=radiance B=unsupported)
    R: 1 when current/history contribution-valid states differ.
    G: current-center vs reprojected-history normalized radiance difference.
    B: nearest actual current 3x3 sample difference from history RGB.
- Reactive history trust
    white: current neighborhood supports history content;
    black: unsupported stale content is being rejected.

Moving-avatar expectation
-------------------------
At a stale reflected-leg/body trail location:
- Depth agreement may remain high: expected, because receiver geometry is static.
- Normal agreement may remain high: expected for the same reason.
- Transition R may remain black when both old/new SSR contributions are valid.
- Radiance G should rise where reflected content changed.
- Unsupported B should rise when the old avatar RGB no longer exists locally.
- Reactive history trust should drop toward black.
- History weight should drop sharply; hard rejects report code 8 / salmon.
- Clamp amount may remain low even while unsupported B is high; that specifically
  demonstrates the old AABB-clamp blind spot.

Stationary-world expectation
----------------------------
Stable world reflections should keep low radiance/unsupported divergence, high
reactive trust, and nonzero history weight. The new gate should not globally erase
history on unrelated static receivers.

Acceptance
----------
PASS only if:
1. moving avatar/reflected legs leave no visible temporal trail;
2. stationary reflections still gain temporal stability;
3. there is no whole-screen jitter (jitter is hard-off/default 0.00);
4. current reflection shape is materially unchanged;
5. unrelated static receivers do not lose history excessively.
