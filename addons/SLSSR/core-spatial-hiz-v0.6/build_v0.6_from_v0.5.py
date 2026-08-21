from pathlib import Path
import hashlib, subprocess, sys

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / "core-spatial-v0.5"
base_fx = BASE / "SL_SSR_CORE_SPATIAL_v0_5.fx"
if not base_fx.exists():
    subprocess.check_call([sys.executable, str(BASE / "build_v0.5_from_v0.2.py")], cwd=BASE)
s = base_fx.read_text()

# Runtime/version label.
s = s.replace('// SL_SSR_CORE_SPATIAL_v0_2.fx', '// SL_SSR_CORE_SPATIAL_HIZ_v0_6.fx', 1)
s = s.replace('// CORE+SPATIAL v0.2: production cleanup + full-resolution receiver coverage.',
              '// CORE+SPATIAL v0.6: accepted v0.5 core/spatial + validated Hi-Z v0.53 WORLD tracer A/B.', 1)

# Temporary WORLD A/B selector.
a = '''uniform int SSRTraceSteps\n<\n    ui_label = "Trace Steps";'''
b = '''uniform int SSRWorldTracerAB\n<\n    ui_label = "WORLD Tracer A/B";\n    ui_tooltip = "Temporary integration selector. 0 = accepted v0.5 exponential WORLD/Dstatic marcher; 1 = validated Hi-Z v0.53 WORLD/Dstatic tracer. AVATAR [D0,DavatarBack], arbitration, Raw/Meta, Spatial and composite are unchanged.";\n    ui_type = "combo";\n    ui_items = "Old CORE WORLD tracer\\0Hi-Z v0.53 WORLD tracer\\0";\n> = 1;\n\nuniform int SSRTraceSteps\n<\n    ui_label = "Trace Steps";'''
assert a in s
s = s.replace(a, b, 1)

# Diagnostic labels.
a = '        "Blocked background-entry crossing mask\\0";'
b = '        "Old-WORLD blocked background-entry crossing mask\\0"\n        "WORLD tracer A/B coverage: old R / Hi-Z G / both white\\0";'
assert a in s
s = s.replace(a, b, 1)

# Exact validated Hi-Z include aliases; include file must be adjacent to generated FX.
a = '''sampler SLBackgroundColorSampler\n{\n    Texture = SLBackgroundColorTex;\n    AddressU = CLAMP;\n    AddressV = CLAMP;\n    MinFilter = LINEAR;\n    MagFilter = LINEAR;\n    MipFilter = POINT;\n};\n'''
b = a + '''\n// -----------------------------------------------------------------------------\n// Validated Hi-Z v0.53 WORLD/Dstatic tracer transplant. Geometry only.\n// The include is kept separate so its validated standalone code remains auditable.\n// -----------------------------------------------------------------------------\n#define SLH53_PRIMARY_DEPTH_SAMPLER SLNativeDepthSampler\n#define SLH53_STATIC_DEPTH_SAMPLER SLBackgroundDepthSampler\n#define SLH53_STATIC_COLOR_SAMPLER SLBackgroundColorSampler\n#define SLH53_NORMALS_SAMPLER SLNativeNormalsSampler\n#include "SL_HIZ53_WORLD_TRACE_INTEGRATION.fxinc"\n'''
assert a in s
s = s.replace(a, b, 1)

# Geometry diagnostic bypass includes A/B coverage mode 38.
a = '(SSRDisplayMode >= 22 && SSRDisplayMode <= 33) || SSRDisplayMode == 37);'
b = '(SSRDisplayMode >= 22 && SSRDisplayMode <= 33) || SSRDisplayMode == 37 || SSRDisplayMode == 38);'
assert a in s
s = s.replace(a, b, 1)

# WORLD only: keep old path for A/B, add validated Hi-Z v0.53 path. AVATAR call below is untouched.
a = '''    bool worldAccepted = TraceSSR(\n        viewPos, normal, rayDir, false,\n        worldHitUV, worldHitDistance, worldConfidence,\n        worldRejectReason, worldNoHitHistoryClass,\n        worldMinAbsDepthDelta, worldCrossingPathClass,\n        worldBackgroundEntryBlocked);\n\n    bool avatarAccepted = TraceSSR(\n'''
b = '''    // Temporary production A/B: old v0.5 WORLD marcher versus validated Hi-Z v0.53.\n    // AVATAR remains on the accepted [D0,DavatarBack] TraceSSR path below.\n    float2 oldWorldHitUV = 0.0;\n    float oldWorldHitDistance = 0.0;\n    float oldWorldConfidence = 0.0;\n    float oldWorldRejectReason = 3.0;\n    float oldWorldNoHitHistoryClass = 0.0;\n    float oldWorldMinAbsDepthDelta = 1e6;\n    float oldWorldCrossingPathClass = 0.0;\n    float oldWorldBackgroundEntryBlocked = 0.0;\n\n    bool needOldWorld = (SSRWorldTracerAB == 0) || SSRDisplayMode == 37 || SSRDisplayMode == 38;\n    bool oldWorldAccepted = false;\n    if (needOldWorld)\n    {\n        oldWorldAccepted = TraceSSR(\n            viewPos, normal, rayDir, false,\n            oldWorldHitUV, oldWorldHitDistance, oldWorldConfidence,\n            oldWorldRejectReason, oldWorldNoHitHistoryClass,\n            oldWorldMinAbsDepthDelta, oldWorldCrossingPathClass,\n            oldWorldBackgroundEntryBlocked);\n    }\n\n    float2 hizWorldHitUV = 0.0;\n    float hizWorldHitDistance = 0.0;\n    float hizWorldConfidence = 0.0;\n    bool needHiZWorld = (SSRWorldTracerAB != 0) || SSRDisplayMode == 38;\n    bool hizWorldGeometryHit = false;\n    bool hizWorldAccepted = false;\n    if (needHiZWorld)\n    {\n        hizWorldGeometryHit = SLH53TraceWorld(uv, hizWorldHitUV, hizWorldHitDistance);\n        hizWorldAccepted = hizWorldGeometryHit;\n        if (hizWorldAccepted)\n        {\n            // Preserve CORE's existing post-geometry confidence policy.\n            hizWorldConfidence = EdgeConfidence(hizWorldHitUV) * DistanceConfidence(hizWorldHitDistance);\n            if (hizWorldConfidence <= 0.0)\n                hizWorldAccepted = false;\n        }\n    }\n\n    bool useHiZWorld = SSRWorldTracerAB != 0;\n    bool worldAccepted = useHiZWorld ? hizWorldAccepted : oldWorldAccepted;\n    worldHitUV = useHiZWorld ? hizWorldHitUV : oldWorldHitUV;\n    worldHitDistance = useHiZWorld ? hizWorldHitDistance : oldWorldHitDistance;\n    worldConfidence = useHiZWorld ? hizWorldConfidence : oldWorldConfidence;\n    worldRejectReason = useHiZWorld ? (hizWorldAccepted ? 0.0 : (hizWorldGeometryHit ? 5.0 : 3.0)) : oldWorldRejectReason;\n    worldNoHitHistoryClass = useHiZWorld ? 0.0 : oldWorldNoHitHistoryClass;\n    worldMinAbsDepthDelta = useHiZWorld ? 1e6 : oldWorldMinAbsDepthDelta;\n    worldCrossingPathClass = useHiZWorld ? 0.0 : oldWorldCrossingPathClass;\n    worldBackgroundEntryBlocked = oldWorldBackgroundEntryBlocked;\n\n    bool avatarAccepted = TraceSSR(\n'''
assert a in s
s = s.replace(a, b, 1)

# Integration A/B coverage diagnostic.
a = '''    if (SSRDisplayMode == 37)\n    {\n        float blocked = worldBackgroundEntryBlocked > 0.5 ? 1.0 : 0.0;\n        return float4(blocked, blocked * 0.5, 0.0, 1.0);\n    }\n'''
b = '''    if (SSRDisplayMode == 38)\n    {\n        // BLACK neither; RED old-only; GREEN Hi-Z-only; WHITE both.\n        float o = oldWorldAccepted ? 1.0 : 0.0;\n        float h = hizWorldGeometryHit ? 1.0 : 0.0;\n        float both = min(o, h);\n        return float4(o, h, both, 1.0);\n    }\n\n''' + a
assert a in s
s = s.replace(a, b, 1)

# Composite geometry-debug passthrough includes mode 38.
a = 'if (SSRDisplayMode == 30 || SSRDisplayMode == 31 || SSRDisplayMode == 32 || SSRDisplayMode == 33 || SSRDisplayMode == 37)'
b = 'if (SSRDisplayMode == 30 || SSRDisplayMode == 31 || SSRDisplayMode == 32 || SSRDisplayMode == 33 || SSRDisplayMode == 37 || SSRDisplayMode == 38)'
assert a in s
s = s.replace(a, b, 1)

# Exact Cstatic helper for Hi-Z selected WORLD color; old WORLD color path remains unchanged.
a = '''    float3 hitColor =\n        useAvatarHit\n            ? max(GetSceneLinear(hitUV).rgb, 0.0)\n            : GetBackgroundColor(hitUV);\n'''
b = '''    float3 selectedWorldColor =\n        useHiZWorld\n            ? SLH53SampleWorldColor(worldHitUV)\n            : GetBackgroundColor(worldHitUV);\n\n    float3 hitColor =\n        useAvatarHit\n            ? max(GetSceneLinear(hitUV).rgb, 0.0)\n            : selectedWorldColor;\n'''
assert a in s
s = s.replace(a, b, 1)

# Technique identity and exact ten build passes immediately before existing Trace.
s = s.replace('technique SL_SSR_CORE_SPATIAL_v0_5', 'technique SL_SSR_CORE_SPATIAL_HIZ_v0_6', 1)
s = s.replace('ui_label = "CORE+SPATIAL — Full-Res Background-Bracket Fix v0.5";',
              'ui_label = "CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.6";', 1)
s = s.replace('ui_tooltip = "Full-file v0.49 superset: WORLD Dstatic/Cstatic + AVATAR [D0,DavatarBack], cleaned production marcher, full-resolution receiver coverage, and roughness-aware depth/normal SSR resolve. Enable this instead of ordinary v0.49.";',
              'ui_tooltip = "Accepted v0.5 CORE+SPATIAL with validated Hi-Z v0.53 transplanted into WORLD/Dstatic only. Temporary WORLD tracer A/B selector retained; AVATAR, arbitration, Raw/Meta, Spatial and composite remain unchanged.";', 1)

a = '''{\n    pass Trace\n    {\n        VertexShader = PostProcessVS;\n        PixelShader = SSRTracePS;\n        RenderTarget0 = SLSSRRawTex;\n        RenderTarget1 = SLSSRMetaTex;\n    }\n'''
b = '''{\n    pass SLH53BuildL0 { VertexShader=PostProcessVS; PixelShader=SLH53Level0PS; RenderTarget=SLH53L0Tex; }\n    pass SLH53BuildL1 { VertexShader=PostProcessVS; PixelShader=SLH53Level1PS; RenderTarget=SLH53L1Tex; }\n    pass SLH53BuildL2 { VertexShader=PostProcessVS; PixelShader=SLH53Level2PS; RenderTarget=SLH53L2Tex; }\n    pass SLH53BuildL3 { VertexShader=PostProcessVS; PixelShader=SLH53Level3PS; RenderTarget=SLH53L3Tex; }\n    pass SLH53BuildL4 { VertexShader=PostProcessVS; PixelShader=SLH53Level4PS; RenderTarget=SLH53L4Tex; }\n    pass SLH53BuildL5 { VertexShader=PostProcessVS; PixelShader=SLH53Level5PS; RenderTarget=SLH53L5Tex; }\n    pass SLH53BuildL6 { VertexShader=PostProcessVS; PixelShader=SLH53Level6PS; RenderTarget=SLH53L6Tex; }\n    pass SLH53BuildL7 { VertexShader=PostProcessVS; PixelShader=SLH53Level7PS; RenderTarget=SLH53L7Tex; }\n    pass SLH53BuildL8 { VertexShader=PostProcessVS; PixelShader=SLH53Level8PS; RenderTarget=SLH53L8Tex; }\n    pass SLH53BuildL9 { VertexShader=PostProcessVS; PixelShader=SLH53Level9PS; RenderTarget=SLH53L9Tex; }\n\n    pass Trace\n    {\n        VertexShader = PostProcessVS;\n        PixelShader = SSRTracePS;\n        RenderTarget0 = SLSSRRawTex;\n        RenderTarget1 = SLSSRMetaTex;\n    }\n'''
assert a in s
s = s.replace(a, b, 1)

out = ROOT / "SL_SSR_CORE_SPATIAL_HIZ_v0_6.fx"
out.write_text(s)
sha = hashlib.sha256(out.read_bytes()).hexdigest()
expected = "87bc0292919aaf562b73a34edecd63e24d626c9c3cc4270fe9d3de02bda7710d"
print(out.name)
print("SHA-256", sha)
assert sha == expected, (sha, expected)
print("PASS")
