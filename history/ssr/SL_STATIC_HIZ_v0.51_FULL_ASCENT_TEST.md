# SL Static Hi-Z v0.51 — Full-ascent A/B candidate

Parent diagnostic: `HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.50`
Feature branch: `agent/ssr-hiz`

This milestone does **not** integrate Hi-Z into CORE. It preserves the standalone Dstatic/Cstatic diagnostic and leaves the v0.49 avatar `[D0,DavatarBack]` branch untouched.

## Why this candidate exists

Static inspection of v0.50 found that `StaticHiZStartMip` currently serves two roles:

- initial traversal level: `mip = startMip`
- ascent ceiling after advancing a tile: `mip = min(mip + 1, startMip)`

Therefore `Start Mip = 6` prevents traversal from ever using levels 7, 8, or 9 after it descends and advances. Setting `Start Mip = 9` removes that ceiling only by also changing the initial traversal level.

v0.51 separates those roles. `Start Mip` remains the initial traversal level, while ascent after a tile advance is capped by the actual pyramid top (`mip 9`). No other trace acceptance/refinement logic is changed.

Exact functional change:

```hlsl
// v0.50
mip = min(mip + 1, startMip);

// v0.51
mip = min(mip + 1, SL_STATIC_HIZ_TOP_MIP); // 9
```

## Required isolated technique order

1. `CORE — ...` v0.49 baseline.
2. Exactly one Hi-Z diagnostic after CORE so its debug output is final:
   - BEFORE: `HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.50`
   - AFTER: `HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.51 Full Ascent`

Turn OFF all `TEMPORAL PRE — ...`, `SPATIAL — ...`, `TEMPORAL POST — ...`, `AVATAR RECEIVER — ...`, older/duplicate Hi-Z prototypes, and any other alternate SSR trace/resolve/composite.

## Runtime A/B sequence

Use the same grazing/corner failure camera without moving it between captures.

### A — v0.50 existing diagnostic, Start Mip = 6

Capture:

- `Static Hi-Z accepted-hit mask`
- `Termination reason`
- `Rejected fine candidates`

Record whether long/grazing boundaries are ragged and the spatial amount of yellow `termination = 7`.

### B — v0.50 existing diagnostic, Start Mip = 9

Change only `Start Mip` from 6 to 9. Capture the same three views.

Confirmation signal requested before adopting full ascent:

- yellow `termination = 7` decreases materially; and/or
- long/grazing accepted-hit coverage becomes materially less ragged;
- without broad new false-hit regions.

### C — v0.51 full-ascent candidate, Start Mip = 6

Switch from v0.50 to v0.51, restore `Start Mip = 6`, and capture the same three views.

Expected if the hypothesis is correct: v0.51 at Start Mip 6 should recover most of the coverage benefit of v0.50 at Start Mip 9, because traversal can climb back through mips 7–9 after advancing while still beginning at mip 6.

## Evidence status

No Firestorm/ReShade runtime is available in the authoring environment for this commit. The ascent-cap defect is statically confirmed from the shader source, but the requested visual confirmation at the live grazing/corner camera remains a runtime gate. Do not treat this document as a runtime PASS.

## Source integrity

`SL_SSR_StaticHiZ_v0_51_FullAscent_Diagnostic.fx`

SHA-256: `aecf6e7c7275b683951e7d4ffe5bb7425c227a78a93ab293f9191537d597983c`
