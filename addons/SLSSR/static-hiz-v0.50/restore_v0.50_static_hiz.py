from pathlib import Path
import base64
import gzip
import hashlib

root = Path(__file__).resolve().parent
parts = sorted(root.glob("SL_SSR_StaticHiZ_v0_50_Diagnostic.fx.gz.b64.part*"))
if len(parts) != 2:
    raise SystemExit(f"expected 2 parts, found {len(parts)}")

data = "".join(p.read_text(encoding="ascii").strip() for p in parts)
raw = gzip.decompress(base64.b64decode(data))
out = root / "SL_SSR_StaticHiZ_v0_50_Diagnostic.fx"
out.write_bytes(raw)

sha = hashlib.sha256(raw).hexdigest()
expected = "b2849d0ea8b82e0a95c9b8f29723952f034ff7a1d104338c61db2d744554c242"
print(out)
print("SHA-256:", sha)
if sha != expected:
    raise SystemExit("checksum mismatch")
print("PASS")
