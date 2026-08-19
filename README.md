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

Every installable archive **must begin with `SL_` and end in `.zip`**. The installer at [`tools/installer/SL_InstallLatest.ps1`](tools/installer/SL_InstallLatest.ps1) intentionally discovers only the newest `SL_*.zip` in the configured Downloads directory. A package that does not follow this naming rule will not be selected automatically.

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

See [`docs/DEBUG_PROTOCOL.md`](docs/DEBUG_PROTOCOL.md) for the required diagnostic design.

## Current recovered checkpoints

| Subsystem | Newest recovered checkpoint | Notes |
|---|---|---|
| SLNativeBridge | v0.9a AlphaReplayMask | Native Firestorm depth/normals/alpha bridge line; archived under `packages/latest/` |
| SLProbeBridge | v0.3b FBOAtlas | Earlier probe-irradiance bridge line; archived under `packages/latest/` |
| SLProbeLighting | v1.6.6 / SSR v0.8 SourceProof | **Current active bridge/SSR diagnostic package** |
| SLVolumetricBridge | v0.1d PrivateShadowCopies | Firestorm cascaded-shadow bridge; archived under `packages/latest/` |
| SLSceneLayer | v0.1 UISeparation | Scene/UI boundary add-on; archived under `packages/latest/` |
| iMMERSE Firestorm Native | v0.6 RawAOAlphaReceiver | Recovered integration checkpoint; patches existing iMMERSE Launchpad/MXAO rather than adding another standalone bridge |
| HybridGI | v0.14 BalancedAreaTemporal | Archived under `packages/latest/` |
| HBAO | v0.5 SmoothAO | Archived under `packages/latest/` |
| SSGI | v0.3 RayMarch | Archived under `packages/latest/` |
| Firestorm DEPTH override | v0.2.1 / SLProbeLighting v1.6.1 | Historical infrastructure milestone; superseded by later SLProbeLighting work |

## Current SSR state

The active recovery artifact is [`packages/latest/SL_SSR_v0_8_SourceProof.zip`](packages/latest/SL_SSR_v0_8_SourceProof.zip). The ZIP contains the v1.6.6 `SLProbeLighting.cpp`, FX, CMake/build files, README, and source-audit notes.

The ray transport and scene-color path have already been proven. v0.8 is a source-proof diagnostic pass for Firestorm's authoritative material G-buffer (`specularRect`) and the copy/binding lifetime into ReShade. Do not resume SSR appearance/weight tuning until that material source is numerically proven.

The v0.8 analyzer samples nine 8x8 blocks on a 3x3 screen grid (576 pixels total), not the whole frame. Test material objects must therefore occupy a substantial part of the viewport.

For the exact current test and the v0.5 -> v0.8 reasoning, read [`docs/HANDOFF.md`](docs/HANDOFF.md).

## Repository layout

```text
README.md
packages/latest/        recovered current installable SL_*.zip checkpoints
packages/README.md      package/version interpretation
tools/installer/        actual install helper used with SL_*.zip packages
docs/HANDOFF.md         live chat-swap/current-state checkpoint
docs/DEBUG_PROTOCOL.md  required diagnostic design
docs/UPSTREAM_RENDERER_NOTES.md
history/                 recovered history notes / prior commit inventory
```

The recovered ZIPs contain their corresponding source trees. As each subsystem is modified again, its working source should also be committed as normal browsable files alongside the package rather than relying on a ZIP as the only source representation.

## Version rule

A higher-version FX/package is the active recovered checkpoint unless the documentation explicitly says it was a failed branch. Older versions are retained only when they explain an architectural change or preserve otherwise-lost source.

Do not put multiple old FX files into the active shader folder and assume the newest-looking file is running. Runtime testing previously showed ReShade could continue running an older technique/file after a newer package was expected. Keep active filenames/version identifiers unambiguous.

## Historical Git recovery

A real prior `SL_Firestorm_Render_Extensions` Git repository was recovered from an older archive. Its 12 recovered commit IDs/messages are recorded in [`history/SL_Firestorm_Render_Extensions/RECOVERED_GIT_LOG.md`](history/SL_Firestorm_Render_Extensions/RECOVERED_GIT_LOG.md).

The original historical graph is being treated as a genuine recovered repository artifact; it will not be recreated as invented commits in this new repo.

## Working rule

Every meaningful source, diagnostic, or architectural change gets committed here with the relevant README/status update. **If the current test or conclusion changes, update `docs/HANDOFF.md` in the same commit.** Generated ZIPs and chat history are not the only copy of project state.
