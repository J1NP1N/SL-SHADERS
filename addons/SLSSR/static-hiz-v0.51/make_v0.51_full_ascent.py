from pathlib import Path
import base64
import gzip
import hashlib

root = Path(__file__).resolve().parent
v050 = root.parent / "static-hiz-v0.50"
parts = sorted(v050.glob("SL_SSR_StaticHiZ_v0_50_Diagnostic.fx.gz.b64.part*"))
if len(parts) != 2:
    raise SystemExit(f"expected 2 v0.50 parts, found {len(parts)}")

raw = gzip.decompress(base64.b64decode("".join(p.read_text(encoding="ascii").strip() for p in parts)))
sha050 = hashlib.sha256(raw).hexdigest()
expected050 = "420fcf3f5bc3c0cfad4cf85cf14e56a8a4a5c8cc82239fb86be7904714a7b6c4"
if sha050 != expected050:
    raise SystemExit(f"v0.50 checksum mismatch: {sha050}")

text = raw.decode("utf-8")
replacements = [
    ("// SL_SSR_StaticHiZ_v0_50_Diagnostic.fx", "// SL_SSR_StaticHiZ_v0_51_FullAscent_Diagnostic.fx"),
    ("#define SL_STATIC_HIZ_LEVELS 10\n#define SL_STATIC_HIZ_MAX_ITERS 256", "#define SL_STATIC_HIZ_LEVELS 10\n#define SL_STATIC_HIZ_TOP_MIP 9\n#define SL_STATIC_HIZ_MAX_ITERS 256"),
    ('ui_tooltip = "Initial hierarchy level. Correctness testing should start at 6 and only tune after the hit mask is validated.";', 'ui_tooltip = "Initial hierarchy level only. Traversal may ascend above this level up to the actual pyramid top (mip 9).";'),
    ("int startMip=clamp(StaticHiZStartMip,1,9);", "int startMip=clamp(StaticHiZStartMip,1,SL_STATIC_HIZ_TOP_MIP);"),
    ("mip=min(mip+1,startMip);", "mip=min(mip+1,SL_STATIC_HIZ_TOP_MIP);"),
    ("technique HIZ_DEBUG_SL_SSR_StaticHiZ_v0_50_Diagnostic", "technique HIZ_DEBUG_SL_SSR_StaticHiZ_v0_51_FullAscent_Diagnostic"),
    ('ui_label = "HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.50";', 'ui_label = "HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.51 Full Ascent";'),
    ('ui_tooltip = "Correctness-first hierarchical static-world tracer. Builds a min/max pyramid from Dstatic, samples Cstatic for world hits, uses no pixel DDA, and does not touch the v0.49 avatar thickness path.";', 'ui_tooltip = "v0.51 A/B candidate: Start Mip selects only the initial traversal level; ascent can reach mip 9. Dstatic/Cstatic only, no pixel DDA, avatar thickness path untouched.";'),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match for {old!r}, found {count}")
    text = text.replace(old, new, 1)

out = root / "SL_SSR_StaticHiZ_v0_51_FullAscent_Diagnostic.fx"
out.write_text(text, encoding="utf-8")
sha051 = hashlib.sha256(out.read_bytes()).hexdigest()
expected051 = "aecf6e7c7275b683951e7d4ffe5bb7425c227a78a93ab293f9191537d597983c"
print(out)
print("v0.50 SHA-256:", sha050)
print("v0.51 SHA-256:", sha051)
if sha051 != expected051:
    raise SystemExit("v0.51 checksum mismatch")
print("PASS")
