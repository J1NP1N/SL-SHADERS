# SSR v0.18 RayRejectReasons — runtime result

Date: 2026-08-19

Result: **PASS as diagnostic**.

The user supplied `Display Mode -> Ray termination reason` at the camera angle containing the persistent avatar-adjacent missing-reflection strip.

The defective region is **BLUE**.

v0.18 color contract:

- WHITE = accepted hit
- RED = ray direction rejected
- MAGENTA = projection/off-screen failure
- BLUE = no accepted depth crossing before the trace-step / max-distance budget ended
- ORANGE = oversized crossing rejected after skip budget
- CYAN = geometric hit but zero edge/distance confidence

Therefore the persistent strip is not being rejected by hit thickness, material weighting, or final composite. The march is exhausting its forward-search budget before producing a hit.

Source inspection exposes a concrete budget mismatch: `SL_SSR_MAX_STEPS` is 32. With the active `Initial Ray Step = 0.12` and `Ray Step Growth = 1.18`, iteration 32 reaches only about 20.3 view-space units. The configured `Maximum Ray Distance = 32` requires roughly 35 iterations to actually be searched. Thus a ray can terminate BLUE before it has searched the configured distance.

Next revision: increase the compile-time step ceiling and test with `Trace Steps = 40` while retaining `Maximum Ray Distance = 32`. This adds only the few iterations required to reach the existing distance cap under the current exponential growth.
