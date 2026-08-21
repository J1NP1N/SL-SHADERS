from pathlib import Path
import hashlib, re, subprocess, sys

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / "core-spatial-hiz-v0.8"
base_fx = BASE / "SL_SSR_CORE_SPATIAL_HIZ_v0_8.fx"
if not base_fx.exists():
    subprocess.check_call([sys.executable, str(BASE / "build_v0.8_viewport_reset.py")], cwd=BASE)

s = base_fx.read_text()
s = s.replace('SL_SSR_CORE_SPATIAL_HIZ_v0_8.fx', 'SL_SSR_CORE_SPATIAL_HIZ_v0_9.fx')
s = s.replace('SL_SSR_CORE_SPATIAL_HIZ_v0_8', 'SL_SSR_CORE_SPATIAL_HIZ_v0_9')
s = s.replace('CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.8', 'CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.9')

# Remove the failed v0.8 viewport-reset theory/workaround.
s = re.sub(r'\n// OpenGL/ReShade integration guard:[\s\S]*?float4 SLH53ViewportResetPS\(float4 pos : SV_Position, float2 uv : TEXCOORD\) : SV_Target\n\{\n    return 0\.0;\n\}\n', '\n', s, count=1)
s = re.sub(r'\n    // Required on the Firestorm/OpenGL runtime:[\s\S]*?    pass SLH53ViewportReset\n    \{\n        VertexShader = PostProcessVS;\n        PixelShader = SLH53ViewportResetPS;\n        RenderTarget = SLH53ViewportResetTex;\n    \}\n', '\n', s, count=1)

anchor = 'texture SLSSRRawTex\n'
helper = '''// -----------------------------------------------------------------------------\n// v0.9 canonical full-resolution raster contract\n// -----------------------------------------------------------------------------\nint2 SSRFullResPixelCoord(float4 pos)\n{\n    float2 hi = float2(BUFFER_WIDTH - 1, BUFFER_HEIGHT - 1);\n    return int2(clamp(floor(pos.xy), 0.0, hi));\n}\n\nfloat2 SSRFullResScreenUV(float4 pos)\n{\n    return (float2(SSRFullResPixelCoord(pos)) + 0.5) *\n           float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);\n}\n\n'''
assert s.count(anchor) == 1
s = s.replace(anchor, helper + anchor, 1)

def function_span(text, name):
    i = text.index(name)
    start = text.rfind('\n', 0, i) + 1
    brace = text.index('{', i)
    depth = 0
    for j in range(brace, len(text)):
        if text[j] == '{': depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0: return start, j + 1
    raise RuntimeError(name)

def canonicalize(text, name):
    a, b = function_span(text, name)
    fn = text[a:b]
    fn = re.sub(r'float2 uv : TEXCOORD', 'float2 rasterUV : TEXCOORD', fn, count=1)
    brace = fn.index('{')
    head, body = fn[:brace + 1], fn[brace + 1:]
    body = re.sub(r'\buv\b', 'screenUV', body)
    body = '\n    int2 pixelCoord = SSRFullResPixelCoord(pos);\n    float2 screenUV = SSRFullResScreenUV(pos);\n' + body
    return text[:a] + head + body + text[b:]

for name in ('SSRTracePS', 'SSRResolveHorizontalPS', 'SSRResolveVerticalPS', 'SSRCompositePS'):
    s = canonicalize(s, name)

# Exact center texel identity for all full-resolution SSR intermediates.
s = s.replace('float4 center = tex2D(SLSSRRawSampler, screenUV);', 'float4 center = tex2Dfetch(SLSSRRawSampler, pixelCoord);', 1)
s = s.replace('float4 meta = tex2D(SLSSRMetaSampler, screenUV);', 'float4 meta = tex2Dfetch(SLSSRMetaSampler, pixelCoord);', 1)
s = s.replace('float4 centerRaw = tex2D(SLSSRRawSampler, screenUV);', 'float4 centerRaw = tex2Dfetch(SLSSRRawSampler, pixelCoord);', 1)
s = s.replace('float4 center = tex2D(SLSSRBlurHSampler, screenUV);', 'float4 center = tex2Dfetch(SLSSRBlurHSampler, pixelCoord);', 1)
s = s.replace('float4 meta = tex2D(SLSSRMetaSampler, screenUV);', 'float4 meta = tex2Dfetch(SLSSRMetaSampler, pixelCoord);', 1)
s = s.replace('float4 rawSSR = tex2D(SLSSRRawSampler, screenUV);', 'float4 rawSSR = tex2Dfetch(SLSSRRawSampler, pixelCoord);', 1)
s = s.replace('float4 traceMeta = tex2D(SLSSRMetaSampler, screenUV);', 'float4 traceMeta = tex2Dfetch(SLSSRMetaSampler, pixelCoord);', 1)
s = s.replace('float4 resolvedSSR = SSRResolveEnable > 0 ? tex2D(SLSSRResolvedSampler, screenUV) : rawSSR;', 'float4 resolvedSSR = SSRResolveEnable > 0 ? tex2Dfetch(SLSSRResolvedSampler, pixelCoord) : rawSSR;', 1)

s = s.replace('Accepted v0.5 CORE+SPATIAL with validated Hi-Z v0.53 transplanted into WORLD/Dstatic only. Temporary WORLD tracer A/B selector retained; AVATAR, arbitration, Raw/Meta, Spatial and composite remain unchanged.', 'Accepted CORE+SPATIAL + validated Hi-Z v0.53 WORLD A/B. v0.9 fixes the pre-Hi-Z full-resolution regression by deriving Trace/Resolve/Composite receiver coordinates from SV_Position and using exact same-pixel Raw/Meta/Resolved center fetches.', 1)

assert 'SLH53ViewportReset' not in s
out = ROOT / 'SL_SSR_CORE_SPATIAL_HIZ_v0_9.fx'
out.write_text(s)
actual = hashlib.sha256(out.read_bytes()).hexdigest()
expected = '70d33f4dbc62bb35f65b8d2a9420afa96fdd4bb14aca6e70b974d09469bc6e52'
print(out.name)
print('SHA-256', actual)
assert actual == expected, (actual, expected)
print('PASS')
