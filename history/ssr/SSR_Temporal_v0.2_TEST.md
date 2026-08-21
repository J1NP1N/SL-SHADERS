# SSR Temporal v0.2 runtime milestone

Baseline: `agent/ssr-background-depth` commit
`6b27f039f4c67fabdf5a1f37b490feffbde06b9b`.

Feature branch: `agent/ssr-temporal`.

MAIN coordination/docs head observed: `e26406003722ecf24d2a1fafc7aacb1a987c1df8`.
This temporal branch is intentionally not rebased solely for that coordination update.

## Scope

Temporal accumulation/reprojection only.

No changes to:
- v0.49 trace/hit logic;
- Dstatic/Cstatic world path;
- D0/DavatarBack avatar thickness;
- DDA state;
- native bridge.

## Required ReShade naming contract

Per the current MAIN handoff, new experimental technique labels must use subsystem
prefixes. Temporal's next runtime FX/revision must use:

- `TEMPORAL PRE — ...` for the capture/history-input technique before CORE;
- `TEMPORAL POST — ...` for the reprojection/resolve technique after CORE.

The current v0.2 FX is preserved unchanged for the pending runtime test rather than
being rewritten for a coordination-only naming update.

## Exact pipeline order

Current v0.2 milestone labels, in exact order:

1. `SL SSR Temporal v0.2 - Capture Before SSR`
2. `SL SSR v0.49 - Avatar Thickness Trace`
3. `SL SSR Temporal v0.2 - Resolve After SSR`

Keep all three adjacent. Nothing else may run between capture and resolve.

The next prefixed runtime revision must keep the identical functional ordering:

1. `TEMPORAL PRE — ...`
2. `CORE — ...` (v0.49 Avatar Thickness Trace)
3. `TEMPORAL POST — ...`

The temporal layer records the exact presentation-space contribution produced by
v0.49, reprojects that contribution with the existing camera-delta matrices, and
adds only `(temporal contribution - current contribution)` back to the frame.

## Isolated-test effect state

For isolated temporal testing, only one v0.49 CORE and this one temporal PRE/POST
pair should be active. Turn OFF:

- every `SPATIAL — ...` technique;
- every `HIZ DEBUG — ...` technique;
- every `AVATAR RECEIVER — ...` technique;
- any other temporal PRE/POST implementation, including older temporal experiments;
- any alternate or duplicate CORE/legacy SSR experiment.

No unrelated ReShade effect may sit between temporal PRE, CORE, and temporal POST.
For clean comparison screenshots, presentation-changing post effects outside the
triplet should preferably be disabled too.

## Rejection

History rejection covers:
- missing bridge/motion state;
- camera cuts / large camera deltas;
- screen edges / off-screen reprojection;
- previous depth mismatch and disocclusion;
- receiver normal mismatch;
- current/history contribution-validity transitions;
- stale radiance and neighborhood-clamp disagreement.

The last two are the anti-trailing path for moving reflected avatars because the
current bridge does not publish per-object avatar motion vectors.

## Temporal stability

- half-resolution history, matching the SSR resolve scale;
- 8-phase subpixel history jitter;
- current 3x3 contribution-envelope clamp;
- motion-dependent history reduction;
- history is consumed before it is overwritten.

## Diagnostics

`Temporal Display` exposes:
- current contribution;
- temporal contribution;
- history weight;
- rejection reason;
- reprojected motion;
- depth agreement;
- normal agreement;
- clamp amount;
- camera cut status;
- jitter phase;
- correction magnitude.

## Runtime pass criteria

PASS if:
1. stationary/gently moving static-world SSR stipple is visibly reduced;
2. stable mirror detail is not smeared materially beyond the existing half-res SSR resolve;
3. no persistent trail remains behind a moving avatar reflection;
4. disocclusions and camera cuts reject history promptly;
5. v0.49 avatar thickness behavior remains unchanged with Temporal disabled;
6. Temporal disabled produces no presentation change.
