# Direct GTAO integration status

Date: 2026-08-23
Branch: `agent/direct-gtao-integration`

## Validated

- Native alpha producer/bridge classification and coverage were previously runtime validated.
- `SL Alpha GTAO Hook SAFE v1.1a` identified the Firestorm opaque-to-straight-alpha boundary without nested ReShade technique execution.
- Runtime screenshot showed one qualifying MRT+depth candidate, one qualified alpha transition per frame, Firestorm alpha draws continuing, and valid pre-alpha scene capture.
- Direct GTAO integration source compiles with MSVC after callback signature and const-pointer fixes.
- Direct GTAO runtime counter increments once per frame in the integrated add-on.

## Rejected paths

- Calling `effect_runtime::render_technique()` from the application bind/draw callback: crashes/re-enters ReShade on OpenGL.
- End-of-frame PRE/POST alpha algebraic recomposition: Firestorm scene-color and later ReShade presentation spaces do not match.

## Current build

`addons/SLGTAO/direct-prealpha-v1.1c/`

Build command:

```bat
build-msvc.bat C:\Users\Duck\source\repos\reshade
```

`opengl32` is explicitly linked because the direct module uses WGL/OpenGL entry points.

## Current gate

The direct GTAO function executes, but visual output has not yet been proven. The next task is diagnostic visibility only:

- D0
- N0
- raw AO
- denoised AO
- final opaque composite

Do not redesign alpha handling or tune hair during this gate.
