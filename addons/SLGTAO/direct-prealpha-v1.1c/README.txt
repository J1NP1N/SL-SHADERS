SL Alpha GTAO Hook direct pre-alpha integration v1.1c
===================================================

Purpose
-------
Integrates the runtime-proven Firestorm opaque -> straight-alpha boundary hook
with the direct GPU GTAO reference implementation. GTAO executes before
Firestorm resumes its ordinary straight-alpha rendering.

Runtime-proven integration state (2026-08-23)
----------------------------------------------
- Add-on loads in Firestorm/ReShade.
- Qualifying MRT+depth candidate resolves.
- Firestorm world viewport resolves.
- Exactly one alpha transition is qualified per frame in the tested scene.
- Firestorm straight-alpha draws continue after the hook.
- Pre-alpha scene capture is valid.
- Direct GTAO execution counter increments once per frame.
- Windows/MSVC source compiles after callback/const integration fixes.
- Link requires opengl32 for wglGetProcAddress/glBindTexture/glGetIntegerv.

Not yet runtime-proven
----------------------
- Correct visual contents of D0/N0 as consumed by the direct GTAO module.
- Raw AO correctness.
- Bilateral denoise correctness.
- Final opaque composite correctness.

Current validation target
-------------------------
Expose/inspect direct GTAO outputs (D0, N0, raw AO, denoised AO, final
composite). Do not change alpha handling or tune hair while this gate is open.

GTAO contract
-------------
GTAO remains alpha-blind and uses D0 + N0 only. Do not add Dalpha,
SL_ALPHA_MATERIAL, SL_ALPHA_COVERAGE, DavatarBack, avatar/hair heuristics, or
post-composite alpha protection.

Build
-----
build-msvc.bat C:\Users\Duck\source\repos\reshade

Output
------
build\SLAlphaGTAOHook.addon
