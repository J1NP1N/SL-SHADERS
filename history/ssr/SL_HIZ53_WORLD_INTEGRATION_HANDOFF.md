# Hi-Z v0.53 WORLD tracer — production integration handoff

Source workstream: `agent/ssr-hiz`

Validated standalone reference:
- technique: `HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.53 Edge Coverage`
- corrected standalone FX SHA-256: `d1b7870345c9a418b9a54c018271f8307768d244c4a0490b30dba6840624e8a1`
- compile-fix lineage commit: `e48184eb7b78ff87480b97e4482834b4443d52d5`

This handoff is **not** a CORE edit and is not a merge. It packages only the code/resources Spatial needs to transplant the validated v0.53 WORLD tracer into production CORE.

## Immutable integration contract

Preserve exactly:

- WORLD geometry source: `Dstatic = SL_DEPTH_BACKGROUND`.
- WORLD hit color: `Cstatic = SL_COLOR_BACKGROUND`.
- Receiver origin may use `SL_DEPTH_PRIMARY_NATIVE` and `SL_NORMALS`, exactly as v0.53 does, but **WORLD hit testing never substitutes D0 for Dstatic**.
- Fresh full-resolution Dstatic at the refined UV is authoritative for final acceptance.
- The mip-0 hierarchy guide depth is a traversal/refinement guide only; it must not veto a candidate already proven inside the fresh Dstatic finite slab.
- v0.52/v0.53 grazing recovery remains unchanged.
- `StaticHiZDiscontinuityTolerance = 0.20`; do not widen it.
- hierarchical tile-boundary traversal only; no screen-pixel DDA.
- no `SL_DEPTH_AVATAR_BACK`, no avatar hit tracing, no avatar-thickness changes.
- do not change WORLD/AVATAR arbitration, CORE composite, Spatial resolve, materials, or roughness behavior as part of this transplant.

## Files for Spatial

`addons/SLSSR/static-hiz-v0.53/integration/SL_HIZ53_WORLD_TRACE_INTEGRATION.fxinc`

This is the production transplant block. It contains only:

1. validated v0.53 settings;
2. ten Dstatic min/max hierarchy textures/samplers;
3. Dstatic hierarchy build pixel shaders;
4. exact bridge/projection helpers under an `SLH53` prefix;
5. perspective-correct screen ray + hierarchical tile traversal;
6. v0.52/v0.53 mip-0 grazing recovery;
7. v0.53 fresh-Dstatic-authoritative final acceptance;
8. `SLH53TraceWorld(receiverUV, hitUV, hitDistance)`;
9. `SLH53SampleWorldColor(hitUV)`;
10. the exact ten build passes to place before CORE trace.

Standalone-only debug MRTs, display modes, termination colors, reject counters, and classifier textures are deliberately omitted because they do not affect traversal/acceptance.

## Existing CORE prerequisites — reuse, do not duplicate semantically

The include assumes CORE already exposes the v0.49 bridge uniforms:

```hlsl
SLBridgeViewport
SLBridgeBufferInfo
SLBridgeRegistrationValid
SLGIInvProjC0..3
SLGIProjC0..3
SLGIProjectionValid
SLProbeNativeValid
```

It also assumes these existing samplers, or aliases to equivalent CORE samplers:

```hlsl
SLPrimaryNativeDepthSampler  // SL_DEPTH_PRIMARY_NATIVE; receiver setup only
SLStaticDepthSampler         // SL_DEPTH_BACKGROUND; all WORLD candidates
SLStaticColorSampler         // SL_COLOR_BACKGROUND; accepted WORLD color
SLNativeNormalsSampler       // SL_NORMALS; receiver normal
```

If production CORE uses different sampler identifiers, define the four `SLH53_*_SAMPLER` aliases before including the file. Do not change their semantics.

## New resources CORE actually needs

Ten `RG32F` hierarchy targets, rebuilt each frame:

```text
SLH53L0Tex  BUFFER_WIDTH x BUFFER_HEIGHT
SLH53L1Tex  ceil(L0/2)
SLH53L2Tex  ceil(L1/2)
SLH53L3Tex  ceil(L2/2)
SLH53L4Tex  ceil(L3/2)
SLH53L5Tex  ceil(L4/2)
SLH53L6Tex  ceil(L5/2)
SLH53L7Tex  ceil(L6/2)
SLH53L8Tex  ceil(L7/2)
SLH53L9Tex  ceil(L8/2)
```

Each stores `[minLinearDstatic, maxLinearDstatic]`.

Empty/background cells are exactly:

```hlsl
[SLH53_EMPTY, 0.0] // SLH53_EMPTY = 65504.0
```

Odd dimensions use ceil reduction and child bounds checks; preserve that behavior.

No standalone diagnostic textures are required in production.

## Required build-pass order inside CORE

Add these passes **before the existing production CORE trace pass**, in this exact order:

```hlsl
pass SLH53BuildL0 { VertexShader=PostProcessVS; PixelShader=SLH53Level0PS; RenderTarget=SLH53L0Tex; }
pass SLH53BuildL1 { VertexShader=PostProcessVS; PixelShader=SLH53Level1PS; RenderTarget=SLH53L1Tex; }
pass SLH53BuildL2 { VertexShader=PostProcessVS; PixelShader=SLH53Level2PS; RenderTarget=SLH53L2Tex; }
pass SLH53BuildL3 { VertexShader=PostProcessVS; PixelShader=SLH53Level3PS; RenderTarget=SLH53L3Tex; }
pass SLH53BuildL4 { VertexShader=PostProcessVS; PixelShader=SLH53Level4PS; RenderTarget=SLH53L4Tex; }
pass SLH53BuildL5 { VertexShader=PostProcessVS; PixelShader=SLH53Level5PS; RenderTarget=SLH53L5Tex; }
pass SLH53BuildL6 { VertexShader=PostProcessVS; PixelShader=SLH53Level6PS; RenderTarget=SLH53L6Tex; }
pass SLH53BuildL7 { VertexShader=PostProcessVS; PixelShader=SLH53Level7PS; RenderTarget=SLH53L7Tex; }
pass SLH53BuildL8 { VertexShader=PostProcessVS; PixelShader=SLH53Level8PS; RenderTarget=SLH53L8Tex; }
pass SLH53BuildL9 { VertexShader=PostProcessVS; PixelShader=SLH53Level9PS; RenderTarget=SLH53L9Tex; }
```

Do not place Spatial filtering between hierarchy construction and CORE trace.

## Exact WORLD-branch replacement

Replace only the existing non-DDA WORLD/Dstatic march call with:

```hlsl
float2 worldHitUV = 0.0;
float worldHitDistance = 0.0;
bool worldHit = SLH53TraceWorld(receiverUV, worldHitUV, worldHitDistance);

if (worldHit)
{
    float3 worldHitColor = SLH53SampleWorldColor(worldHitUV); // Cstatic only

    // Map these into CORE's existing WORLD hit record:
    // hit mask / valid = true
    // hit UV           = worldHitUV
    // hit distance     = worldHitDistance
    // hit color        = worldHitColor
    //
    // Keep existing CORE confidence/roughness/composite/arbitration policy unchanged.
}
```

Do not route `worldHitUV` into avatar sampling. Do not use D0 or DavatarBack to validate a WORLD hit.

The production include intentionally returns geometry data, not a new composite policy.

## Exact v0.53 final-acceptance rule

This is the critical v0.53 boundary fix:

```hlsl
float freshDepth = SLH53SampleStaticDepthLinear(candidateUV);
float candidateDepth = SLH53RayDepth(r, candidateLambda);

bool freshInside =
    freshDepth > 0.0 &&
    candidateDepth >= freshDepth - front - 0.001 &&
    candidateDepth <= freshDepth + back;

if (freshInside)
    accept WORLD hit;
```

Do **not** restore the old hard veto:

```hlsl
abs(freshDepth - mip0GuideDepth) > discontinuityTolerance
```

The guide-vs-fresh mismatch may be useful for diagnostics, but it is not final rejection authority in v0.53.

## Grazing recovery that must remain unchanged

When mip 0 is reached already inside the finite Dstatic slab:

1. sample fresh full-resolution Dstatic at the current boundary;
2. backtrack up to `2.0 px`;
3. require local continuity using the unchanged `0.20` discontinuity tolerance;
4. if the entry side is bracketed, bisect with fresh Dstatic;
5. if entry is farther back but the local slab remains continuous, use the current boundary as the conservative continuation point;
6. run fresh-Dstatic final slab validation.

This is the H2 fix. Do not replace it with a reject/advance loop.

## Validated settings — transplant unchanged

```text
SLH53StartMip                   = 6
SLH53MaxIterations              = 192
SLH53MaxDistance                = 48.0
SLH53OriginBias                 = 0.02
SLH53InitialTravel              = 0.04
SLH53Thickness                  = 0.12
SLH53FrontTolerance             = 0.003
SLH53DiscontinuityTolerance     = 0.20
SLH53TileEpsilonPx              = 0.02
SLH53RefineSteps                = 6
SLH53GrazingBacktrackPx         = 2.0
SLH53_TOP_MIP                   = 9
SLH53_MAX_ITERS hard ceiling    = 256
```

`StartMip` is the **initial** hierarchy level only. After tile advancement, ascent remains:

```hlsl
mip = min(mip + 1, SLH53_TOP_MIP);
```

Do not cap ascent back at `startMip`.

## Functions Spatial must transplant

Required production functions/macros from the include:

```text
SLH53HasBridgeRegistration
SLH53HasExactMatrices
SLH53FirestormUV
SLH53ScreenUVFromFirestormUV
SLH53InsideScreen
SLH53InsideFirestormWorld
SLH53MulInvProj
SLH53MulProj
SLH53IsBackgroundDepth
SLH53ReconstructViewPosition
SLH53LinearStaticDepth
SLH53SampleStaticDepthLinear
SLH53DecodeFirestormNormalRaw

SLH53Level0PS
SLH53AccumulateInterval
SLH53_DECL_REDUCE_PS
SLH53Level1PS .. SLH53Level9PS
SLH53LevelSize
SLH53LookupUV
SLH53SampleInterval

SLH53ScreenRay
SLH53ProjectUnclipped
SLH53BuildScreenRay
SLH53RayUV
SLH53RayView
SLH53RayDepth
SLH53RayDistance
SLH53TileExitLambda

SLH53TraceWorld
SLH53SampleWorldColor
```

If CORE already has byte-equivalent bridge/reconstruction helpers, Spatial may map calls to them rather than keep duplicate `SLH53` wrappers. Do not alter coordinate conventions or projection math while deduplicating.

## Functions/resources that are NOT part of production integration

Do not transplant:

```text
StaticHiZTracePS diagnostic MRT wrapper
SLStaticHiZHitTex
SLStaticHiZTraversalTex
SLStaticHiZEventTex
SLStaticHiZRejectATex
SLStaticHiZRejectBTex
SLStaticHiZEdgeDiagTex
TerminationColor
FineRejectColor
DominantFineRejectCode
ResidualEdgeFailureColor
StaticHiZDisplayPS
HIZ DEBUG technique / Display pass
```

These remain in the standalone v0.53 reference only.

## Integration verification gate

Before Spatial resolve or other experiments are enabled, test CORE with the transplanted WORLD tracer in isolation:

ReShade order:

1. `CORE — ...` containing the ten Hi-Z build passes before its trace pass.
2. No standalone `HIZ DEBUG` technique active during the production-core comparison.
3. `TEMPORAL PRE`, `SPATIAL`, `TEMPORAL POST`, `AVATAR RECEIVER`, alternate CORE/SSR experiments OFF.

Compare against validated standalone v0.53 at the same grazing/corner/silhouette views.

PASS means:

- WORLD accepted-hit coverage retains the broad v0.52/v0.53 coherence;
- no return of v0.51 broad stipple/thrash;
- thin boundary behavior matches standalone v0.53 within expected composite differences;
- no broad new false WORLD hits;
- avatar reflection behavior is unchanged because avatar trace/arbitration was not modified.

Only after that gate should Spatial resolve be turned back on.

## Explicit non-goals

This handoff does not authorize:

- integrating or changing the avatar `[D0,DavatarBack]` branch;
- changing CORE composite/arbitration;
- widening Dstatic tolerances;
- enabling DDA;
- changing material/roughness inputs;
- changing Spatial filter behavior;
- performance optimization;
- merging this branch to MAIN.
