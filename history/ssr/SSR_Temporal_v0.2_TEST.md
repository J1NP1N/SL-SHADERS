# SSR Temporal v0.2 runtime milestone

Baseline: `agent/ssr-background-depth` commit
`6b27f039f4c67fabdf5a1f37b490feffbde06b9b`.

Feature branch: `agent/ssr-spatial`.

## Scope

Temporal accumulation/reprojection only.

No changes to:
- v0.49 trace/hit logic;
- Dstatic/Cstatic world path;
- D0/DavatarBack avatar thickness;
- DDA state;
- native bridge.

## Pipeline

The new effect brackets v0.49:

1. `SL SSR Temporal v0.2 - Capture Before SSR`
2. `SL SSR v0.49 - Avatar Thickness Trace`
3. `SL SSR Temporal v0.2 - Resolve After SSR`

The temporal layer records the exact presentation-space contribution produced by
v0.49, reprojects that contribution with the existing camera-delta matrices, and
adds only `(temporal contribution - current contribution)` back to the frame.

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
