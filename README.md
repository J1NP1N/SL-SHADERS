# SL-SHADERS

Shader, rendering, and ReShade work for Second Life viewers.

This repository is the source of truth for viewer-side graphics experiments, ReShade effects, renderer-data bridges, diagnostics, and supporting notes. Individual techniques live in their own folders; generated ZIPs are test artifacts, not the canonical source.

## Current work

The first recovered subsystem is the Firestorm/ReShade screen-space reflection path. The current checkpoint is **SSR v0.8 SourceProof / SL Probe Lighting v1.6.6**.

The SSR ray transport itself is already proven usable: matrices/registration, scene-linear color, ray hits, and raw reflected scene color have worked. The unresolved issue is proving the authoritative Firestorm material G-buffer source (`specularRect`) and its lifetime into ReShade before any more reflection-weight tuning.

See [`reshade/ssr/STATUS.md`](reshade/ssr/STATUS.md) for the exact diagnostic history and current test.

## Layout

```text
SL-SHADERS/
├── README.md
├── reshade/
│   └── ssr/
│       ├── STATUS.md
│       └── v0.8-sourceproof/
│           ├── CMakeLists.txt
│           ├── README.txt
│           ├── SLProbeLighting.cpp
│           ├── SL_SSR_v0_1_LegacyFirst.fx
│           ├── SOURCE_AUDIT.txt
│           └── build-msvc.bat
└── ... future shader / ReShade work
```

## Working rule

Every meaningful code or diagnostic change gets committed here. When the active hypothesis, proven renderer contract, or next test changes, update the relevant status/readme in the same commit.

Do not rely on chat history or generated archives as the only copy of project state.
