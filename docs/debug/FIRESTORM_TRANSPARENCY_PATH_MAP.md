# Firestorm Transparency Path Map

## Scope

Source-backed map of Firestorm transparency rendering relevant to semantic capture. This document separates proven behavior from unresolved path coverage. It does not assign meanings to semantic family IDs without enum/call-site tracing.

## Current Proven State

| Area | Status | Evidence |
|---|---|---|
| ALPHA_DEPTH publication | SOURCE-PROVEN / RUNTIME-VALIDATED | Published semantic depth is readable by ReShade. |
| ALPHA_GEOMETRY publication | SOURCE-PROVEN / RUNTIME-VALIDATED | Resource registration/publication works. |
| Transform bypass replay | RUNTIME-VALIDATED | Semantic geometry becomes visible when replay transform bypass is used. |
| Normal replay | UNRESOLVED | Produces zero samples in current validation. |

## Observed Transparency Matrix

| Surface/material | Draw pool | Render branch | Shader variant | Rigged | Lit/fullbright | Alpha | Water order | Semantic sidecar | Support |
|---|---|---|---|---|---|---|---|---|---|
| Non-PBR hair (observed working case) | Unknown | Alpha path unknown | Unknown | Unknown | Unknown | Alpha | Unknown | Alpha geometry sidecar path observed | YES (runtime observation) |
| Non-PBR unrigged hair (missing case) | Unknown | Alpha path unknown | Unknown | Unrigged | Unknown | Alpha | Unknown | Unknown | NO/UNKNOWN |
| Windows/glass | Unknown | Unknown | Unknown | Unknown | Unknown | Alpha/transmission unknown | Unknown | No confirmed semantic path | NO/UNKNOWN |
| PBR alpha | Unknown | Unknown | Unknown | Unknown | Unknown | Alpha | Unknown | Unknown | UNRESOLVED |
| GLTF alpha | Separate alpha path not fully mapped | GLTF alpha path | Unknown | Unknown | Unknown | Alpha | Unknown | Unknown | UNRESOLVED |
| Particles/foliage | Unknown | Unknown | Unknown | Unknown | Unknown | Alpha | Unknown | Unknown | UNRESOLVED |

## Semantic Families

Observed semantic programs:

- family=0/program=86: main-view semantic path exists and can rasterize under transform bypass.
- family=1/program=87: historical observation only.
- family=3/program=0: historical observation only.

Family numbers are not assigned meanings until enum definitions and call sites are traced.

## Required Source Tracing Remaining

Not yet proven from available artifacts:

- every call site of `SLAlphaGeometrySidecar::bindForDraw`
- alpha branches that bypass sidecar publication
- exact native shader variants for ordinary alpha, fullbright alpha, rigged alpha, PBR alpha, GLTF alpha, glass/windows, particles, and foliage
- one-to-one semantic shader/program coverage for each native path

## Current Interpretation

The primary blocker is not resource registration or FBO publication. The remaining likely causes are:

1. semantic replay transform/model matrix synchronization,
2. missing transparency path coverage,
3. shader-family coverage gaps.

The hair/window difference is consistent with incomplete semantic path coverage, but exact class assignment requires source call-site tracing.
