SL SSR Temporal v0.2 — v0.49 presentation-delta reprojection

Baseline
--------
Fixed producer: SL_SSR_v0_49_AvatarThicknessTrace.fx
Backbone commit: 6b27f039f4c67fabdf5a1f37b490feffbde06b9b
Feature branch: agent/ssr-temporal

This is FX-only. It does not modify v0.49 tracing, the world/static trace,
or the [D0, DavatarBack] avatar-thickness interval.

Coordination naming contract
----------------------------
MAIN's current handoff requires subsystem prefixes for all new experimental
ReShade techniques:

- CORE — ...
- SPATIAL — ...
- TEMPORAL PRE — ...
- TEMPORAL POST — ...
- HIZ DEBUG — ...
- AVATAR RECEIVER — ...

The existing v0.2 runtime milestone is intentionally NOT rewritten merely for
this coordination update. Its FX blob remains unchanged for the pending runtime
test. The next temporal runtime FX/revision must expose its two checkboxes with
TEMPORAL PRE — ... and TEMPORAL POST — ... labels.

Exact technique order for the current v0.2 milestone
----------------------------------------------------
Keep these three techniques adjacent and in exactly this order:

1. SL SSR Temporal v0.2 - Capture Before SSR
2. SL SSR v0.49 - Avatar Thickness Trace
3. SL SSR Temporal v0.2 - Resolve After SSR

Do not put another effect between the capture and resolve techniques. The temporal
effect measures the exact presentation-space contribution produced between them.

For the next prefixed runtime revision, the same functional order is mandatory:

1. TEMPORAL PRE — temporal capture/history input
2. CORE — v0.49 Avatar Thickness Trace
3. TEMPORAL POST — temporal reprojection/resolve

Isolated temporal runtime test: effects that must be OFF
-------------------------------------------------------
For an isolated temporal test, leave only the one v0.49 CORE plus this one temporal
PRE/POST pair active. Disable all other experimental SSR workstreams:

- every SPATIAL — ... technique;
- every HIZ DEBUG — ... technique;
- every AVATAR RECEIVER — ... technique;
- any other TEMPORAL PRE — ... / TEMPORAL POST — ... implementation;
- any alternate/duplicate CORE — ... or legacy experimental SSR core.

No unrelated ReShade effect may be placed between temporal PRE, CORE, and temporal
POST. For clean A/B screenshots, preferably disable presentation-changing post
effects elsewhere in the chain as well.

Why this architecture
---------------------
The temporal layer does not bind v0.49 private textures and does not reconstruct
its material/composite math. It captures the backbuffer before v0.49, captures
the post-v0.49 difference at half resolution, then temporally reprojects only that
SSR contribution.

This keeps v0.49 hit logic and avatar thickness behavior byte-for-byte untouched
and keeps temporal separable from a future roughness-aware spatial resolve.

Reprojection / rejection
------------------------
Uses the existing Firestorm bridge camera contract:
- SLGIInvModelviewDeltaC0..C3
- SLGIMotionValid
- current projection/inverse projection
- D0 = SL_DEPTH_PRIMARY_NATIVE
- SL_NORMALS

History is rejected for:
- unavailable/invalid bridge motion
- camera-cut-sized view transform changes
- screen-edge/reprojection failure
- previous-depth mismatch / disocclusion
- receiver-normal mismatch
- current/history valid-contribution transitions
- strong stale-radiance or neighborhood-clamp disagreement

Moving avatar protection
------------------------
The current bridge has camera motion, not per-object avatar motion vectors.
v0.2 therefore does not fabricate avatar motion. Instead it prevents trails by:
- never resurrecting a previous reflected contribution after the current one disappears
- rejecting newly appearing vs previously missing contribution transitions
- clamping history to the current 3x3 SSR-contribution neighborhood
- aggressively reducing history when current/history radiance diverges

This is intentionally conservative around moving reflected avatars.

Jitter
------
History radiance uses an 8-phase subpixel jitter at the half-resolution history
grid. Geometry validation remains unjittered. Neighborhood clamping is applied
after the jittered history fetch.

First runtime test
------------------
1. Install only SL_SSR_Temporal_v0_2.fx. No add-on/native rebuild is required.
2. Disable the experimental effects listed above.
3. Verify the exact current-v0.2 technique order above.
4. Start with defaults.
5. Temporal Display -> History weight:
   stable reflective receivers should accumulate; moving/disoccluded areas should drop.
6. Temporal Display -> History rejection reason:
   red = depth, yellow = normal, cyan = hit transition, salmon = radiance/clamp.
7. Slowly pan the camera; Reprojected motion should respond and history should remain stable.
8. Move the avatar across a reflective receiver and inspect the area behind the moving reflection.
   There should be no persistent reflected-avatar trail.
9. Force a camera cut/teleport and verify Camera cut status resets history.
10. Compare Current SSR contribution vs Temporal SSR contribution on grazing/static-world stipple.

Rejection reason colors
-----------------------
green      accepted/no reject
gray       reset/disabled/first frames
magenta    bridge/motion unavailable
orange     camera cut
blue       screen edge/reprojection/invalid receiver
red        depth/disocclusion
yellow     normal mismatch
cyan       invalid contribution transition
salmon     radiance/clamp reactive rejection
