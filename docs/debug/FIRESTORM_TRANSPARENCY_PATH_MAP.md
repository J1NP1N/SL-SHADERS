# Firestorm Transparency Path Map

## Scope

This document maps known Firestorm transparency rendering paths against semantic capture support. It separates source-proven rendering facts from runtime validation and unresolved areas. Shader family numbers are not assigned meanings without enum/call-site tracing.

## Transparency Path Matrix

| Surface/material | Draw pool | Render branch | Native shader variant | Rigged | Lit/fullbright | Alpha mode | Water order | Semantic sidecar family | Semantic support |
|---|---|---|---|---|---|---|---|---|---|
| Ordinary alpha | Deferred/forward alpha path | PASS_ALPHA / alpha rendering path | Source variant not yet fully traced | unresolved | lit and fullbright variants unresolved | blend/mask behavior depends on material path | unresolved | family=0/program=86 runtime validated | Partial: rasterization validated under transform bypass |
| Fullbright alpha | Alpha path variant | unresolved | unresolved | unresolved | fullbright | unresolved | unresolved | unresolved | unresolved |
| Rigged alpha | Alpha rigged path | unresolved | unresolved | yes | unresolved | unresolved | unresolved | unresolved | unresolved |
| PBR alpha | PBR alpha path | source path exists | unresolved | unresolved | unresolved | blend/mask unresolved | unresolved | unresolved | unresolved |
| GLTF alpha | GLTF alpha batch path | separate from PASS_ALPHA | unresolved | unresolved | unresolved | alpha mode from GLTF material | unresolved | unresolved | unresolved |
| Glass/windows | transparency/material-specific path | unresolved | unresolved | unresolved | unresolved | unresolved | unresolved | unresolved | unresolved |
| Particles/foliage | special paths | unresolved | unresolved | unresolved | unresolved | unresolved | unresolved | unresolved | unresolved |

## Known Evidence

### SOURCE-PROVEN

- Firestorm transparency includes paths outside deferred opaque G-buffer generation.
- Whole-scene GLTF alpha is a separate batch path from PASS_ALPHA.
- Shader/resource behavior must be traced from call sites before assigning semantic family meanings.

### RUNTIME-VALIDATED

- Main-view semantic family=0/program=86 exists.
- family=0/program=86 can rasterize under transform bypass.
- Historical logs also observed family=1/program=87 and family=3/program=0. Their meanings remain unresolved.

### IMPLEMENTED

- Semantic capture bridge work exists for publishing and validating semantic resources.
- Transform bypass path can expose semantic rasterization for the validated program path.

### SHELVED

- 8 m draw distance implementation: source-proven viable but implementation shelved.

### UNRESOLVED

- Exact SLAlphaGeometrySidecar::bindForDraw call graph.
- Exact native shader variant mapping for ordinary alpha, fullbright alpha, rigged alpha, PBR alpha, GLTF alpha, glass/windows, particles, and foliage.
- Which transparency classes receive semantic sidecar publication.
- Why some non-PBR hair appears under semantic transform bypass while other non-PBR unrigged hair does not.
- Why windows/glass do not appear under current semantic capture.

## Observed Cases

| Observation | Current interpretation |
|---|---|
| Friend's non-PBR hair appears in semantic under transform bypass | Confirms at least one hair path intersects a supported semantic path |
| User's non-PBR unrigged hair does not | Indicates a missing or different draw path; exact cause unresolved |
| Windows/glass do not appear | Indicates unsupported or unconfirmed semantic publication path |
| family=0/program=86 rasterizes | Confirms semantic shader execution path, not universal material coverage |

No renderer behavior is inferred beyond traced or runtime-confirmed evidence.
