# SL-SHADERS

> **Starting a new chat? Read [`docs/HANDOFF.md`](docs/HANDOFF.md) first.** It is the live project checkpoint: current build, proven facts, current failure, next runtime test, and exact report-back requested.

Second Life / Firestorm shader, ReShade FX, and native ReShade add-on work.

This repository is the source of truth for the renderer-data bridges and effects developed for Firestorm. It is intentionally broader than SSR: SSR is one subsystem alongside native depth/normals, AO, SSGI/HybridGI, probe lighting, volumetrics, UI separation, and third-party ReShade integration work.

## Upstream viewer source references

These are the renderer-source references used when auditing Firestorm and comparing viewer implementations:

- Firestorm: https://github.com/FirestormViewer/phoenix-firestorm
- Black Dragon: https://github.com/NiranV/Black-Dragon-Viewer
- ReShade: https://github.com/crosire/reshade

Firestorm is the implementation target. Black Dragon is a useful comparative reference for features it already implements natively, such as SSR and volumetric lighting; it is not assumed to have identical buffer lifetime or render ordering.

Reusable findings from those repositories belong in [`docs/UPSTREAM_RENDERER_NOTES.md`](docs/UPSTREAM_RENDERER_NOTES.md), with pinned commit/path references, so future chats do not repeat broad source audits.

## Package and installer contract

Every installable archive **must begin with `SL_` and end in `.zip`**. The installer at `tools/installer/SL_InstallLatest.ps1` intentionally discovers only the newest `SL_*.zip` in the configured Downloads directory. A package that does not follow this naming rule will not be selected automatically.

The installer has two operating modes.

**FX-only / hot-install package**

- Contains `.fx` shader files but no `build-msvc.bat` and no `.addon`.
- Firestorm may remain running.
- The installer copies FX files into `reshade-shaders\Shaders`; ReShade can recompile/reload them in place.
- Use this for shader-only tuning or a hotfix that does not change native bridge code.

**Native add-on package**

- Contains `build-msvc.bat` and/or an `.addon`.
- Firestorm **must be closed** before installation because a loaded native add-on DLL cannot safely be replaced.
- The installer resolves MSVC/Visual Studio, runs the package build, copies built `.addon` files into the Firestorm root, then installs accompanying `.fx` files.
- Use this whenever bridge/interception code changes.

Packages should contain one top-level project directory. The installer extracts that directory into the local source-repo root before building/installing.

## Run-and-report development contract

This project is developed against the real Firestorm/ReShade runtime. Source review alone is not treated as proof that a renderer hook, buffer capture, semantic binding, or temporal path works.

The normal loop is:

1. Build/package one explicit hypothesis.
2. Install it in Firestorm using the `SL_*.zip` convention.
3. Run the requested diagnostic views in the actual scene.
4. Report overlay state, diagnostic screenshots, numeric readouts, and compile/runtime errors.
5. Use those observations to decide the next code change.

**Debug screens are mandatory for experimental renderer work.** New effects and bridge changes must expose enough diagnostics to distinguish source capture, registration, material data, geometry/ray transport, temporal state, and final composite problems. A black final output is not an adequate diagnostic.

See `docs/DEBUG_PROTOCOL.md` for the required diagnostic design.

## Current recovered checkpoints

| Subsystem | Newest recovered checkpoint | Notes |
|---|---|---|
| SLNativeBridge | v0.9a AlphaReplayMask | Native Firestorm depth/normals/alpha bridge line |
| SLProbeBridge | v0.3b FBOAtlas | Earlier probe-irradiance bridge line |
| SLProbeLighting | v1.6.6 / SSR v0.8 SourceProof | **Current active bridge source**; current SSR diagnostic work |
| SLVolumetricBridge | v0.1d PrivateShadowCopies | Firestorm cascaded-shadow bridge |
| SLSceneLayer | v0.1 UISeparation | Scene/UI boundary add-on |
| iMMERSE Firestorm Native | v0.6 RawAOAlphaReceiver | Patches existing iMMERSE Launchpad/MXAO; no new C++ add-on |
| HybridGI | v0.14 BalancedAreaTemporal | Latest recovered HybridGI effect package |
| HBAO | v0.5 SmoothAO | Latest recovered standalone HBAO FX |
| SSGI | v0.3 RayMarch | Latest recovered standalone SSGI package |
| Firestorm DEPTH override | v0.2.1 / SLProbeLighting v1.6.1 | Historical infrastructure milestone; superseded by later SLProbeLighting work |

## Current SSR state

The active SSR work is `addons/SLProbeLighting/current-ssr-v0.8-sourceproof/`.

The ray transport and scene-color path have already been proven. v0.8 is a source-proof diagnostic pass for Firestorm's authoritative material G-buffer (`specularRect`) and the copy/binding lifetime into ReShade. Do not resume SSR appearance/weight tuning until that material source is numerically proven.

The v0.8 analyzer samples nine 8x8 blocks on a 3x3 screen grid (576 pixels total), not the whole frame. Test material objects must therefore occupy a substantial part of the viewport.

## Repository layout

```text
addons/         Native ReShade add-on source, grouped by add-on/version
builds/         Observed built .addon snapshots; source is canonical
effects/        ReShade FX/effect checkpoints
integrations/   Third-party integration/patch work (currently iMMERSE)
packages/       Installable SL_*.zip checkpoints
tools/          Installer/helper scripts
history/        Recovered historical project state and Git bundle
docs/           Recovery/version/debug notes
```

## Version rule

A higher-version FX/package is the active recovered checkpoint unless the documentation explicitly says it was a failed branch. Older versions are retained only when they explain an architectural change or preserve otherwise-lost source.

Do not put multiple old FX files into the active shader folder and assume the newest-looking file is running. Runtime testing previously showed ReShade could continue running an older technique/file after a newer package was expected. Keep active filenames/version identifiers unambiguous.

## Historical Git recovery

`history/SL_Firestorm_Render_Extensions.bundle` preserves the actual Git history recovered from the previous `SL_Firestorm_Render_Extensions` repository archive. It contains the HybridGI/Firestorm-depth development history through the v0.14/depth-normalization work.

The readable snapshot from that project is under `history/SL_Firestorm_Render_Extensions/`.

## Working rule

Every meaningful source, diagnostic, or architectural change gets committed here with the relevant README/status update. **If the current test or conclusion changes, update `docs/HANDOFF.md` in the same commit.** Generated ZIPs and chat history are not the only copy of project state.
