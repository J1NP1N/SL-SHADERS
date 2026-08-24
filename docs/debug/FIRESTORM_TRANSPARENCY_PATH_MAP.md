# Firestorm Transparency Path Map

## Scope

Native Firestorm transparency ownership map. This maps visible transparent objects to native renderer ownership and identifies where semantic capture would need coverage. It does not map semantic publisher internals.

## Native Transparency Ownership Matrix

| Visual object | Native owner | Pass | Function | Shader family | Reaches LLDrawPoolAlpha? | Semantic hook needed |
|---|---|---|---|---|---|---|
| Ordinary transparent attachment hair | LLDrawPoolAlpha | alpha forward | LLDrawPoolAlpha::renderPostDeferred -> forwardRender -> renderAlpha | deferred alpha/simple/material variants | Usually yes | LLDrawPoolAlpha coverage |
| System avatar hair | LLDrawPoolAvatar / avatar rendering | transparent avatar pass | LLVOAvatar::renderTransparent | avatar alpha variants | Not guaranteed | Avatar transparent hook |
| Eyelashes | LLDrawPoolAvatar | avatar transparent | LLVOAvatar::renderTransparent | avatar alpha/mask variants | Not guaranteed | Avatar transparent hook |
| Alpha masked foliage | LLDrawPoolAlpha alpha-mask batches | alpha mask | renderAlpha batch path | alpha mask variants | Yes when routed through alpha pool | Alpha mask coverage |
| Fullbright alpha mask | LLDrawPoolAlpha | alpha forward | forwardRender/renderAlpha | gDeferredFullbrightAlphaMaskProgram family | Yes | Fullbright alpha coverage |
| Glass/window legacy blend | LLDrawPoolAlpha when legacy material blend | alpha forward | renderAlpha | material/simple alpha variants | Usually yes | Alpha material coverage |
| Legacy material blend | LLDrawPoolAlpha | material alpha | renderAlpha | material alpha variants | Yes | Material alpha coverage |
| Per-face glTF blend | LLDrawPoolGLTFPBR / GLTF renderer | glTF alpha | GLTF scene rendering | glTF PBR alpha variants | Not guaranteed | GLTF renderer hook |
| Whole-scene glTF blend | GLTFSceneManager | glTF scene pass | GLTFSceneManager::render | glTF PBR variants | No guarantee | GLTF scene hook |
| Rigged alpha | LLDrawPoolAlpha rigged path / avatar paths | rigged alpha | forwardRender(true), renderAlpha(..., rigged) | rigged alpha variants | Only if entering alpha pool | Rigged alpha coverage |
| Unrigged alpha | LLDrawPoolAlpha | regular alpha | forwardRender(), renderAlpha | simple/material alpha variants | Yes | Alpha hook |
| Particles | Particle renderer | particle pass | particle rendering path | particle shaders | No | Particle renderer hook |

## LLDrawPoolAlpha::renderAlpha Coverage

Guaranteed from this hook:

- legacy alpha objects routed through LLDrawPoolAlpha
- unrigged alpha batches in the alpha pool
- rigged alpha batches that use the alpha pool rigged path
- simple, fullbright, material, and PBR alpha variants prepared by the alpha pool

Outside this hook:

- dedicated avatar transparent rendering paths
- dedicated GLTF scene rendering
- particles and other specialized renderers

## Source Notes

LLDrawPoolAlpha is the main forward transparency owner. Its render path prepares simple, fullbright, material, and PBR alpha shaders, then performs regular and rigged alpha rendering.

GLTF has separate ownership and must not be assumed to enter LLDrawPoolAlpha.

## Runtime Interpretation

Observed:

- friend non-PBR hair works
- user's non-PBR unrigged hair is missing
- windows/glass are missing

These observations can be explained by different native ownership paths. A single LLDrawPoolAlpha hook cannot guarantee coverage of avatar, GLTF, or specialized transparency paths.

## Minimum Native Coverage Set

1. LLDrawPoolAlpha
2. LLDrawPoolAvatar transparent rendering
3. GLTFSceneManager / GLTF PBR transparency
4. particle renderer if particles are required

## Status

SOURCE-PROVEN:
- LLDrawPoolAlpha owns the main legacy alpha forward path.
- GLTF rendering is separately owned.
- Alpha has distinct rigged and non-rigged rendering paths.

UNRESOLVED:
- Complete content-to-pass routing for every asset class.
- Exact shader permutation names for every avatar/material combination.
