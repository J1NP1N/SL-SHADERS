SL Direct GTAO Debug v1.1d
===========================

Build:
  build-msvc.bat C:\Users\Duck\source\repos\reshade

Install:
  - SLAlphaGTAOHook.addon -> ReShade addon directory
  - SL_DirectGTAO_Debug.fx -> ReShade Shaders directory

Validation:
  1. Open the `SL Direct GTAO Debug v1.1d` addon panel.
  2. Confirm `Direct GTAO attempts last frame: 1` and `Direct GTAO applied last frame: 1`.
  3. Confirm `inv_proj capture failures total` is not increasing.
  4. Enable `DIRECT GTAO - Buffer Debug`.
  5. Inspect Raw AO, Denoised AO, D0 depth, and N0 normals.

This FX is diagnostic-only. GTAO generation and opaque-scene application still occur directly at Firestorm's pre-alpha boundary.
