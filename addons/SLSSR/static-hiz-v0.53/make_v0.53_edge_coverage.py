from pathlib import Path
import base64
import gzip
import hashlib

root = Path(__file__).resolve().parent
parts = sorted(root.glob("SL_SSR_StaticHiZ_v0_53_EdgeCoverage_Diagnostic.fx.gz.b64.part*"))
if len(parts) != 2:
    raise SystemExit(f"expected 2 v0.53 parts, found {len(parts)}")

data = "".join(p.read_text(encoding="ascii").strip() for p in parts)
raw = gzip.decompress(base64.b64decode(data))
out = root / "SL_SSR_StaticHiZ_v0_53_EdgeCoverage_Diagnostic.fx"
out.write_bytes(raw)

sha = hashlib.sha256(raw).hexdigest()
expected = "d1b7870345c9a418b9a54c018271f8307768d244c4a0490b30dba6840624e8a1"
print(out)
print("SHA-256:", sha)
if sha != expected:
    raise SystemExit("v0.53 checksum mismatch")

text = raw.decode("utf-8")
required = [
    'ui_tooltip = "Hierarchy-guide consistency only. Fresh full-resolution Dstatic slab membership is authoritative for final v0.53 edge acceptance.";',
    'ui_tooltip = "Preserves v0.52 H2 grazing recovery and targets only residual silhouette/discontinuity coverage. Dstatic/Cstatic only, no pixel DDA, avatar path untouched.";',
]
for line in required:
    if text.count(line) != 1:
        raise SystemExit(f"required compile-fix line missing or duplicated: {line}")
if text.count("{") != text.count("}"):
    raise SystemExit("brace mismatch")
print("PASS")
