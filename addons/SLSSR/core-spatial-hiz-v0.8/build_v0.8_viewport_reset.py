from pathlib import Path
import hashlib, subprocess, sys

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / "core-spatial-hiz-v0.7"
base_fx = BASE / "SL_SSR_CORE_SPATIAL_HIZ_v0_7.fx"

if not base_fx.exists():
    subprocess.check_call([sys.executable, str(BASE / "build_v0.7_self_contained.py")], cwd=BASE)

s = base_fx.read_text()

s = s.replace('// SL_SSR_CORE_SPATIAL_HIZ_v0_7.fx',
              '// SL_SSR_CORE_SPATIAL_HIZ_v0_8.fx', 1)
s = s.replace('technique SL_SSR_CORE_SPATIAL_HIZ_v0_7',
              'technique SL_SSR_CORE_SPATIAL_HIZ_v0_8', 1)
s = s.replace('ui_label = "CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.7";',
              'ui_label = "CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.8";', 1)

# Firestorm/OpenGL runtime showed Trace executing in the reduced Hi-Z raster domain
# after L9. Force a full-size render target bind before the production Trace pass.
anchor = '''texture SLSSRRawTex\n{\n'''
insert = '''// OpenGL/ReShade integration guard: after the reduced Hi-Z L9 target, force\n// the raster viewport back to the full backbuffer domain before CORE Trace.\ntexture SLH53ViewportResetTex\n{\n    Width = BUFFER_WIDTH;\n    Height = BUFFER_HEIGHT;\n    Format = R8;\n};\n\nfloat4 SLH53ViewportResetPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target\n{\n    return 0.0;\n}\n\n'''
assert s.count(anchor) == 1
s = s.replace(anchor, insert + anchor, 1)

anchor = '''    pass SLH53BuildL9 { VertexShader=PostProcessVS; PixelShader=SLH53Level9PS; RenderTarget=SLH53L9Tex; }\n\n    pass Trace\n'''
replacement = '''    pass SLH53BuildL9 { VertexShader=PostProcessVS; PixelShader=SLH53Level9PS; RenderTarget=SLH53L9Tex; }\n\n    // Required on the Firestorm/OpenGL runtime: L9 leaves a reduced viewport\n    // active unless a full-size target is explicitly rebound before CORE Trace.\n    pass SLH53ViewportReset\n    {\n        VertexShader = PostProcessVS;\n        PixelShader = SLH53ViewportResetPS;\n        RenderTarget = SLH53ViewportResetTex;\n    }\n\n    pass Trace\n'''
assert s.count(anchor) == 1
s = s.replace(anchor, replacement, 1)

out = ROOT / "SL_SSR_CORE_SPATIAL_HIZ_v0_8.fx"
out.write_text(s)
sha = hashlib.sha256(out.read_bytes()).hexdigest()
expected = "13f5b7ad3d43f1241f5bdd18495aa56b2da013875986649839d943f031b30bd9"
print(out.name)
print("SHA-256", sha)
assert sha == expected, (sha, expected)
print("PASS")
