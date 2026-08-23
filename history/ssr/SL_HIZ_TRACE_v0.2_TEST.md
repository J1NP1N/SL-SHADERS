# SL Hi-Z Trace v0.2 — fine hit validation

v0.1 runtime result: the `v0.35 vs Hi-Z hit mask` comparison showed broad GREEN regions, including the grazing avatar-reflection region. That means the hierarchy itself is functioning, but v0.1's mip-0 acceptance rule was too permissive and introduced additional Hi-Z-only hits.

Root cause in v0.1: when the ray segment did not actually cross the visible depth sample, mip 0 still chose whichever segment endpoint was closest to the sample and accepted it if the depth error was within `Hit Thickness`.

v0.2 leaves the validated v0.1b hierarchy and coarse traversal unchanged. It changes only fine-hit validation:

- requires a monotonic front-to-back crossing of the visible mip-0 depth sample;
- removes the closest-endpoint-within-thickness fallback;
- refines the crossing with five bisection steps;
- requires `-dot(rayDir, hitNormal) >= 0.05` by default;
- continues traversal after a rejected fine candidate instead of treating the candidate as a hit;
- records crossing failure and hit-facing failure as separate reject reasons.

Technique order:
1. `SL Hi-Z v0.1b - Min/Max Infrastructure`
2. `SL SSR v0.35 - Legacy Resolve`
3. `SL SSR Temporal v0.1 - Reprojected History`
4. `SL Hi-Z Trace v0.2 - Fine Hit Validate`

First runtime: do not tune defaults. Return to the same grazing-ghost camera angle and use `v0.35 vs Hi-Z hit mask`.

- WHITE = both hit
- GREEN = v0.2 Hi-Z only
- RED = v0.35 only
- BLACK = neither

Desired evidence: the broad GREEN additions from v0.1 collapse. Best case is RED in the long ghost region while the valid avatar reflection remains mostly WHITE.

If needed, use `Reject reason`:
- RED = strict depth crossing failed
- CYAN = hit-surface facing failed
- BLUE = traversal exhausted / no surviving overlap
- ORANGE = offscreen/build failure
- MAGENTA = rejected ray direction
- YELLOW = confidence failure

Package: `SL_HiZ_Trace_v0_2_FineValidate.zip`
SHA-256: `48f19b110e2e5a7eb47048f47daaad1129b7b749cac2ceb0777af605f496f773`

Full FX SHA-256: `9594d4f80007b58c56512b1d4a3982287086870e1d58b2b38430f069d65eef3b`
Link C++ SHA-256: `b58f4b847eb810262379acc351bd79fea4b29166170a3cc7c101879291c617eb`
