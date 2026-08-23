# Installable packages

`latest/` contains the newest recovered installable checkpoint for each subsystem currently backed up here. `history/` is reserved for superseded packages retained because they represent important bridge/infrastructure milestones.

All package names intentionally begin with `SL_` because `tools/installer/SL_InstallLatest.ps1` discovers packages using the `SL_*.zip` pattern.

Do not rename an installable package so it loses the `SL_` prefix.

FX-only packages can be hot-installed while Firestorm runs. Packages containing `build-msvc.bat` or an `.addon` require Firestorm to be closed; the installer enforces this.

## Recovery note

A loose `.fx` or `.addon` found in the Library is not automatically newer than the corresponding versioned package. The package version and runtime notes are authoritative. This prevents an older built artifact from being accidentally promoted as the active build.

The current GTAO installable checkpoint is `SL_GTAO_Direct_v1_2_0_FirestormModes.zip`. It contains the full corrective source, build scripts, debug FX, authoritative GLSL shaders, generated-header validation, static invariant checks, project status, and engineering review response. SHA-256: `c1574fae096f696276c077e55abef49e641202386e8e3bc3ae7545e77e287d47`.

The current SSR recovery package is `SL_SSR_v0_8_SourceProof.zip`. It includes the v1.6.6 `SLProbeLighting.cpp`, FX, build files, README and source-audit notes.

The iMMERSE Firestorm-native integration v0.6 is tracked in the recovery index but is not yet copied into this directory; it patches the user's existing iMMERSE files rather than acting as another standalone native bridge.
