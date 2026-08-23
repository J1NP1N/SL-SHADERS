# SL Direct GTAO — v1.1f passthrough validation

Date: 2026-08-23
Branch: `agent/direct-gtao-integration`

## Change
Added an independent add-on passthrough switch for diagnostic testing.

`Passthrough (generate/export GTAO only)` keeps the direct pre-alpha generation path active and continues publishing:
- `SL_GTAO_D0`
- `SL_GTAO_N0`
- `SL_GTAO_RAW`
- `SL_GTAO_DENOISED`
- `SL_GTAO_NV`
- `SL_GTAO_BASELINE`

When passthrough is enabled, the final direct composite writes the saved opaque Firestorm scene copy back unchanged instead of multiplying AO or showing a boundary diagnostic. This allows `SL_DirectGTAO_Debug.fx` to inspect the exported semantics without the add-on changing the scene underneath it.

No alpha-path, D0/N0 binding, horizon math, denoise math, or Firestorm boundary logic changed.

## Test
1. Enable `Passthrough (generate/export GTAO only)` in the add-on overlay.
2. Enable `SL_DirectGTAO_Debug.fx`.
3. Check `N dot V`, then `Unoccluded slice baseline`.

## Installable artifact
`SL_GTAO_Direct_v1_1f_Passthrough.zip`

SHA-256: `312ed80374bf1803236c6d32de54534d80aa570fefbcc4f4df35dc540d22aca7`
