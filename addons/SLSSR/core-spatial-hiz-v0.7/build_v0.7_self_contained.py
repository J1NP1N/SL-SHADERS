from pathlib import Path
import hashlib, subprocess, sys

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / "core-spatial-hiz-v0.6"
base_fx = BASE / "SL_SSR_CORE_SPATIAL_HIZ_v0_6.fx"
inc = BASE / "SL_HIZ53_WORLD_TRACE_INTEGRATION.fxinc"

if not base_fx.exists():
    subprocess.check_call([sys.executable, str(BASE / "build_v0.6_from_v0.5.py")], cwd=BASE)
if not inc.exists():
    raise FileNotFoundError(inc)

s = base_fx.read_text()
include_line = '#include "SL_HIZ53_WORLD_TRACE_INTEGRATION.fxinc"'
assert s.count(include_line) == 1
inc_text = inc.read_text().rstrip("\n")
inline_block = (
    '// BEGIN INLINED VALIDATED Hi-Z v0.53 WORLD TRACER\n'
    + inc_text
    + '\n// END INLINED VALIDATED Hi-Z v0.53 WORLD TRACER'
)
s = s.replace(include_line, inline_block, 1)

s = s.replace('// SL_SSR_CORE_SPATIAL_HIZ_v0_6.fx',
              '// SL_SSR_CORE_SPATIAL_HIZ_v0_7.fx', 1)
s = s.replace('technique SL_SSR_CORE_SPATIAL_HIZ_v0_6',
              'technique SL_SSR_CORE_SPATIAL_HIZ_v0_7', 1)
s = s.replace('ui_label = "CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.6";',
              'ui_label = "CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.7";', 1)

out = ROOT / "SL_SSR_CORE_SPATIAL_HIZ_v0_7.fx"
out.write_text(s)
sha = hashlib.sha256(out.read_bytes()).hexdigest()
expected = "387229c2afdbb1257c32c6a327cc5a55f25e970d7da0492b54e4df35bcc09bde"
print(out.name)
print("SHA-256", sha)
assert sha == expected, (sha, expected)
assert '#include "SL_HIZ53_WORLD_TRACE_INTEGRATION.fxinc"' not in s
print("PASS")
