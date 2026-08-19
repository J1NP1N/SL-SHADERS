# SL-SHADERS

> **Starting a new chat? Read [`docs/HANDOFF.md`](docs/HANDOFF.md) first.** It is the live project checkpoint: current build, proven facts, current failure, next runtime test, and exact report-back requested.

Second Life / Firestorm shader, ReShade FX, and native ReShade add-on work.

This repository is the source of truth for project state, renderer findings, version history, installer behavior, diagnostics, and verified recovery artifacts. It is broader than SSR: SSR is one subsystem alongside native depth/normals, AO, SSGI/HybridGI, probe lighting, volumetrics, UI separation, and third-party ReShade integration work.

## Upstream viewer source references

- Firestorm: https://github.com/FirestormViewer/phoenix-firestorm
- Black Dragon: https://github.com/NiranV/Black-Dragon-Viewer
- ReShade: https://github.com/crosire/reshade

Firestorm is the implementation target. Black Dragon is a comparative renderer reference, not assumed to have identical buffer lifetime or render ordering.

Reusable source findings go in [`docs/UPSTREAM_RENDERER_NOTES.md`](docs/UPSTREAM_RENDERER_NOTES.md), with pinned commits and paths, so a replacement chat does not repeat broad upstream audits.

## Package and installer contract

Every installable archive **must begin with `SL_` and end in `.zip`**. [`tools/installer/SL_InstallLatest.ps1`](tools/installer/SL_InstallLatest.ps1) intentionally selects only the newest `SL_*.zip` from the configured Downloads folder.

**FX-only / hot install:** no `build-msvc.bat` and no `.addon`; Firestorm can remain running and ReShade recompiles the copied FX.

**Native add-on install:** contains `build-msvc.bat` and/or `.addon`; Firestorm must be closed before installation. The helper resolves MSVC, builds the add-on, copies `.addon` files to the Firestorm root, and installs accompanying FX.

Packages should contain one top-level project directory.

## Run-and-report development contract

Source review is not runtime proof. The normal loop is:

1. build/package one explicit hypothesis;
2. user installs/runs it in real Firestorm;
3. user reports requested diagnostic screens, overlay values, numeric readouts, compile/runtime errors, and behavior;
4. use that evidence for the next revision.

**Debug screens are mandatory for experimental renderer work.** A black final output is not an adequate diagnostic. See [`docs/DEBUG_PROTOCOL.md`](docs/DEBUG_PROTOCOL.md).

## Current recovered checkpoints

| Subsystem | Newest recovered checkpoint | Remote package state |
|---|---|---|
| SLNativeBridge | v0.9a AlphaReplayMask | recovered; large ZIP not yet byte-valid in GitHub |
| SLProbeBridge | v0.3b FBOAtlas | **verified ZIP in GitHub** |
| SLProbeLighting | v1.6.6 / SSR v0.8 SourceProof | **current active work; recovered ZIP exists, remote large ZIP not yet byte-valid** |
| SLVolumetricBridge | v0.1d PrivateShadowCopies | recovered; large ZIP not yet byte-valid in GitHub |
| SLSceneLayer | v0.1 UISeparation | **verified ZIP in GitHub** |
| iMMERSE Firestorm Native | v0.6 RawAOAlphaReceiver | recovered integration checkpoint |
| HybridGI | v0.14 BalancedAreaTemporal | recovered; large ZIP not yet byte-valid in GitHub |
| HBAO | v0.5 SmoothAO | **verified ZIP in GitHub** |
| SSGI | v0.3 RayMarch | recovered; large ZIP not yet byte-valid in GitHub |
| Firestorm DEPTH override | v0.2.1 / SLProbeLighting v1.6.1 | historical/superseded infrastructure checkpoint |

For exact byte counts/checksums and what is genuinely verified, read [`packages/RECOVERY_STATUS.md`](packages/RECOVERY_STATUS.md). A successful upload response is **not** considered proof of a valid package.

## Current SSR state

Current active package name: `SL_SSR_v0_8_SourceProof.zip` / SLProbeLighting v1.6.6.

The ray transport and scene-color path are already proven. v0.8 is a source-proof diagnostic pass for Firestorm's authoritative material G-buffer (`specularRect`) and the copy/binding lifetime into ReShade. Do not resume SSR appearance/weight tuning until that material source is numerically proven.

The v0.8 analyzer samples nine 8x8 blocks on a 3x3 screen grid = 576 pixels, not the whole frame. The test material must occupy a substantial portion of the viewport.

For the exact test and the v0.5 -> v0.8 reasoning, read [`docs/HANDOFF.md`](docs/HANDOFF.md).

## Repository layout

```text
README.md
packages/latest/        only package ZIPs verified byte-valid in GitHub
packages/RECOVERY_STATUS.md
packages/README.md
tools/installer/SL_InstallLatest.ps1
docs/HANDOFF.md         live chat-swap/current-state checkpoint
docs/DEBUG_PROTOCOL.md
docs/UPSTREAM_RENDERER_NOTES.md
history/                 recovered prior-Git commit inventory
```

## Version rule

A loose `.fx` or `.addon` is not automatically newer than the corresponding versioned package. Runtime/package version evidence is authoritative. Older versions stay historical unless they preserve otherwise-lost source or explain an architectural change.

New ReShade builds must have unambiguous visible version/technique identifiers; an older technique previously remained active during a supposed newer test.

## Historical Git recovery

A real prior `SL_Firestorm_Render_Extensions` Git repository was recovered from an older archive. Its 12 original commit IDs/messages are recorded in [`history/SL_Firestorm_Render_Extensions/RECOVERED_GIT_LOG.md`](history/SL_Firestorm_Render_Extensions/RECOVERED_GIT_LOG.md). That graph is treated as genuine history and will not be replaced with invented commits.

## Working rule

Every meaningful source, diagnostic, or architectural change gets committed here with the relevant state update. **If the current test or conclusion changes, update `docs/HANDOFF.md` in the same commit.** Chat history is never the only copy of project state.
