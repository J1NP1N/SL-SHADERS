from pathlib import Path
import base64
import gzip
import hashlib

root = Path(__file__).resolve().parent
parts = sorted(root.glob("SL_SSR_Spatial_v0_1.fx.gz.b64.part*"))
if len(parts) != 6:
    raise SystemExit(f"expected 6 parts, found {len(parts)}")

data = "".join(p.read_text(encoding="ascii").strip() for p in parts)
raw = gzip.decompress(base64.b64decode(data))
out = root / "SL_SSR_Spatial_v0_1.fx"
out.write_bytes(raw)

sha = hashlib.sha256(raw).hexdigest()
expected = "7edb120a901d6d24660850e8c73ed02f030d9575fa0c68b43fc7d18c16dfe385"
print(out)
print("SHA-256:", sha)
if sha != expected:
    raise SystemExit("checksum mismatch")
print("PASS")
