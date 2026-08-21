from pathlib import Path
import hashlib, re, subprocess, sys

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / "core-spatial-hiz-v0.8"
base_fx = BASE / "SL_SSR_CORE_SPATIAL_HIZ_v0_8.fx"
if not base_fx.exists():
    subprocess.check_call([sys.executable, str(BASE / "build_v0.8_viewport_reset.py")], cwd=BASE)

s = base_fx.read_text()
s = s.replace('// SL_SSR_CORE_SPATIAL_HIZ_v0_8.fx', '// SL_SSR_CORE_SPATIAL_HIZ_v1_0.fx', 1)
s = s.replace('// CORE+SPATIAL v0.6: accepted v0.5 core/spatial + validated Hi-Z v0.53 WORLD tracer A/B.',
              '// CORE+SPATIAL v1.0: accepted core/spatial + validated Hi-Z v0.53 WORLD tracer A/B.\n'
              '// v1.0 restores v0.49 normalized-TEXCOORD addressing and isolates all private RT names.', 1)
s = s.replace('technique SL_SSR_CORE_SPATIAL_HIZ_v0_8', 'technique SL_SSR_CORE_SPATIAL_HIZ_v1_0', 1)
s = s.replace('ui_label = "CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.8";',
              'ui_label = "CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v1.0";', 1)

s = re.sub(
    r'// OpenGL/ReShade integration guard: after the reduced Hi-Z L9 target, force\n'
    r'// the raster viewport back to the full backbuffer domain before CORE Trace\.\n'
    r'texture SLH53ViewportResetTex\n\{\n    Width = BUFFER_WIDTH;\n    Height = BUFFER_HEIGHT;\n    Format = R8;\n\};\n\n'
    r'float4 SLH53ViewportResetPS\(float4 pos : SV_Position, float2 uv : TEXCOORD\) : SV_Target\n\{\n    return 0\.0;\n\}\n\n',
    '', s, count=1)
s = re.sub(
    r'\n    // Required on the Firestorm/OpenGL runtime: L9 leaves a reduced viewport\n'
    r'    // active unless a full-size target is explicitly rebound before CORE Trace\.\n'
    r'    pass SLH53ViewportReset\n    \{\n'
    r'        VertexShader = PostProcessVS;\n'
    r'        PixelShader = SLH53ViewportResetPS;\n'
    r'        RenderTarget = SLH53ViewportResetTex;\n'
    r'    \}\n',
    '\n', s, count=1)

for i in range(10):
    s = s.replace(f'SLH53L{i}Sampler', f'SLCSH10H53L{i}Sampler')
    s = s.replace(f'SLH53L{i}Tex', f'SLCSH10H53L{i}Tex')

for old, new in {
    'SLSSRRawSampler':'SLCSH10RawSampler',
    'SLSSRRawTex':'SLCSH10RawTex',
    'SLSSRMetaSampler':'SLCSH10MetaSampler',
    'SLSSRMetaTex':'SLCSH10MetaTex',
    'SLSSRBlurHSampler':'SLCSH10BlurHSampler',
    'SLSSRBlurHTex':'SLCSH10BlurHTex',
    'SLSSRResolvedSampler':'SLCSH10ResolvedSampler',
    'SLSSRResolvedTex':'SLCSH10ResolvedTex',
}.items():
    s = s.replace(old, new)

anchor = 'texture SLCSH10RawTex\n{\n'
comment = (
    '// v1.0 private RT isolation. ReShade shares same-named textures across loaded\n'
    '// effects, so production intermediates must not reuse the v0.49 / Spatial-v0.1\n'
    '// names (those older effects declare half-resolution storage).\n'
    '// Raster/scene coordinates intentionally remain the v0.49 TEXCOORD contract.\n'
)
assert s.count(anchor) == 1
s = s.replace(anchor, comment + anchor, 1)

assert 'SLH53ViewportReset' not in s
assert 'SSRFullResPixelCoord' not in s
assert 'SSRFullResScreenUV' not in s
assert s.count('{') == s.count('}')
for name in ('SLCSH10RawTex','SLCSH10MetaTex','SLCSH10BlurHTex','SLCSH10ResolvedTex'):
    m = re.search(r'texture ' + name + r'\s*\{([^}]*)\}', s, re.S)
    assert m and 'Width = BUFFER_WIDTH;' in m.group(1) and 'Height = BUFFER_HEIGHT;' in m.group(1)

out = ROOT / 'SL_SSR_CORE_SPATIAL_HIZ_v1_0.fx'
out.write_text(s)
actual = hashlib.sha256(out.read_bytes()).hexdigest()
expected = '715deb015938b879ae9a23cd24f1cc26adac2ffe3d731f9edaf70a911e0bb755'
print(out.name)
print('SHA-256', actual)
if actual != expected:
    raise SystemExit('SHA-256 mismatch')
print('PASS')
