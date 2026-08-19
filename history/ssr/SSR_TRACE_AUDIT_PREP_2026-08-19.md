# SSR trace-core audit — prepared follow-on builds

Date: 2026-08-19

The active runtime test remains v0.25 `SilhouetteGate`; its screenshot is still useful and should be read first. In parallel, the source-level audit found structural issues that justify preparing follow-on builds now instead of waiting for another round trip.

## Audit note

See:

`docs/SSR_TRACE_CORE_AUDIT_2026-08-19.md`

Key findings:

1. v0.25 and earlier couple ray-origin normal bias to `Hit Thickness`:
   `originNormal * max(SSRThickness * 0.75, 0.01)`.
   At thickness 0.18 this is a 0.135-unit origin displacement.
2. The current negative-to-positive sign-crossing + binary search assumes local depth continuity. A single-layer depth buffer is discontinuous at avatar silhouettes; v0.23 already proves deeper binary refinement does not collapse the positive delta into the fixed thickness interval.
3. Oversized silhouette candidates and genuine disocclusion candidates currently share one classification/skip path.
4. The current trace target is half resolution, so a full-resolution baseline should be measured before finalizing thin-silhouette workarounds.
5. Firestorm native SSR uses adaptive depth-error stepping and absolute depth-distance acceptance; it is not equivalent to the custom strict sign-bracket marcher.
6. A perspective-correct screen-pixel DDA with finite depth slabs is the preferred long-term trace-core direction if the narrow audits do not solve the artifact.

## Prepared v0.26 — OriginBiasAudit

Purpose: isolate and permanently correct the thickness/bias coupling.

Changes:

- adds independent `Ray Origin Bias`, default 0.010;
- `Hit Thickness` no longer moves the ray origin;
- all v0.25 diagnostics remain available.

Runtime comparison:

- A: `Ray Origin Bias = 0.010`
- B: `Ray Origin Bias = 0.135` (reproduces old effective bias at thickness 0.18)
- keep `Disocclusion Skips = 3` and `Hit Thickness = 0.18`.

Package:

- `SL_SSR_v0_26_OriginBiasAudit.zip`
- SHA-256 `73420208657ee49f763c9ce0475be0990781c5a048b2a114930d655a20f4694c`

Source delta commit:

`1de46b30f98143e1a4cf6d46765a61e7289f78ca`

## Prepared v0.27 — FullResBaseline

Purpose: determine whether the half-resolution receiver-ray target is materially contributing to the avatar silhouette hole.

Changes from v0.26:

- `SLSSRRawTex` becomes full `BUFFER_WIDTH x BUFFER_HEIGHT` instead of half resolution;
- trace/intersection/material/composite behavior otherwise unchanged.

This is intentionally expensive and is diagnostic only.

Package:

- `SL_SSR_v0_27_FullResBaseline.zip`
- SHA-256 `518f64b6d109c822a4d8cec55cf0880f5d78589e9da7000bbe7b113ec47194e8`

Source delta commit:

`d0945f9a894ff04259e6a1240f60698a7ff4ce0c`

## Prepared v0.28 — ScreenDDAPrototype

Purpose: test a fundamentally different intersection core instead of adding more special cases around `finalDelta > Hit Thickness`.

The DDA prototype:

- keeps the corrected independent `Ray Origin Bias`;
- projects the reflected camera-space ray to Firestorm native pixel space;
- traverses contiguous screen pixels with perspective-correct interpolation of camera-space ray Z;
- treats each visible depth sample as a finite camera-space depth slab;
- does **not** automatically stop on the first foreground silhouette sample whose depth is far in front of the reflected ray;
- leaves material response and the v0.16 energy composite unchanged;
- can be toggled live against the legacy marcher with `Use Screen-Pixel DDA`.

Defaults:

- `Use Screen-Pixel DDA = 1`
- `DDA Max Pixel Steps = 96`
- `DDA Pixel Stride = 1.0`
- `Ray Origin Bias = 0.010`
- `Hit Thickness = 0.18`

Package:

- `SL_SSR_v0_28_ScreenDDAPrototype.zip`
- SHA-256 `d21bba2c832477c37b00951237b553075033e8c9c92159d856cc538104ebc857`

Source delta commit:

`b59bc237430a81c885ac719830785b2231d25336`

## Recommended return sequence

1. Read v0.25 `Silhouette-edge gate reason` first; it remains useful evidence about the current workaround.
2. Run v0.26 A/B origin-bias comparison. This is a structural correctness test, not optional tuning.
3. If the hole remains, run v0.28 DDA ON vs OFF at the same camera angle. This is the highest-value architectural comparison.
4. Use v0.27 full-resolution baseline if needed to separate trace-core failure from half-resolution receiver undersampling.

Do not globally loosen silhouette thresholds before these comparisons.
