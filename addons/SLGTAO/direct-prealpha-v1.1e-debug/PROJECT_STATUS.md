# SL Direct GTAO — v1.1e basis diagnostics

Date: 2026-08-23
Branch: `agent/direct-gtao-integration`

## Preserved runtime proof
- Direct pre-alpha GTAO applies successfully once per frame at the proven Firestorm straight-alpha boundary.
- D0, N0, raw AO, and denoised AO debug semantics are runtime-bound.
- D0 is spatially coherent; depth binding/sampling is not the cause of the globally dark AO field.
- Raw and denoised AO are populated but overwhelmingly dark.

## v1.1e diagnostic addition
No GTAO tuning and no alpha-path changes.

- `SL_GTAO_NV`: `saturate(dot(decoded N0, normalize(-viewPosition)))`.
- `SL_GTAO_BASELINE`: average slice visibility from the exact raw-pass basis and arc integral with horizon sampling removed.

Both are full-resolution validation-only `R16_FLOAT` targets generated after raw GTAO and exposed read-only to ReShade.

`SL_DirectGTAO_Debug.fx` adds:
- N dot V
- Unoccluded slice baseline

Interpretation:
- N dot V mostly black => normal/view basis or reconstruction convention failure.
- N dot V coherent but baseline black => slice basis / arc-integral failure.
- Baseline coherent but raw AO black => horizon sampling/update is collapsing visibility.

## Artifact
`packages/SLGTAO/SLAlphaGTAOHook_direct_merge_v1_1e_debug.zip`

SHA-256: `0fffbfb4466d8340821302dc3f7ee8b3705ce84de9c212244ba480fbefc96403`
