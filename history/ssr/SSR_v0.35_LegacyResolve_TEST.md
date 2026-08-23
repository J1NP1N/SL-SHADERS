# SSR v0.35 LegacyResolve — runtime test

Baseline: v0.34 GhostCull geometry. This build does not change `TraceSSR()` or `TraceSSR_DDA()` hit logic.

## New work

- MRT trace metadata: accepted hit distance, receiver-to-hit native screen stretch, receiver grazing factor, confidence.
- Legacy-first Blinn-Phong resolve: `specularRect.a` controls lobe width only, never reflection energy.
- Separable bilateral reflection filtering using receiver depth and normal continuity.
- Distance-driven blur broadening for long rays.
- Optional long-ray fade requiring both long view-space distance and long screen stretch. It defaults OFF.

## First runtime sequence

1. Install `SL_SSR_v0_35_LegacyResolve.zip` as an FX-only hot install.
2. Verify technique `SL SSR v0.35 - Legacy Resolve`.
3. Keep `Long-Ray Ghost Fade = 0` for the first pass.
4. Return the bad camera angle with:
   - `Display Mode -> Accepted hit distance`
   - `Display Mode -> Accepted screen stretch`
   - `Display Mode -> Long-ray fade mask`
   - `Display Mode -> Final composite`
5. On the same camera, toggle `Glossiness Resolve` OFF/ON and compare final composite.
6. Only if the fade mask isolates the faint stretched ghost without substantially covering the good reflection, enable `Long-Ray Ghost Fade = 1` and compare.

## Default resolve controls

- `Glossiness Resolve = 1`
- `Resolve Max Blur (px) = 10`
- `Legacy Gloss Curve = 1.35`
- `Distance Blur Add = 0.25`
- `Resolve Depth Edge = 0.035`
- `Resolve Normal Edge = 24`
- `Long-Ray Ghost Fade = 0`

## Package identity

Local package: `SL_SSR_v0_35_LegacyResolve.zip`

SHA-256: `dd339ca270ff81ae29daf3e7011392ef2e31c55b12c866418d2d5671073d5dee`

Source delta commit: `dd61159ba47f1b865094b284ca96d58b6d0256e5`
