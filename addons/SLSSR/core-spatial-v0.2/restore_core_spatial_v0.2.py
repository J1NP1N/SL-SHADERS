from pathlib import Path
import base64, gzip, hashlib

HERE = Path(__file__).resolve().parent
PARTS = sorted(HERE.glob("SL_SSR_CORE_SPATIAL_v0_2.fx.gz.b64.part*"))
EXPECTED = "89c2bef07f9e7b43163ee947c471906777dbfabc1c6dfbda3bb9719520954348"
OUT = HERE / "SL_SSR_CORE_SPATIAL_v0_2.fx"

if not PARTS:
    raise SystemExit("No source archive parts found")

payload = "".join(p.read_text().strip() for p in PARTS)
data = gzip.decompress(base64.b64decode(payload))
sha = hashlib.sha256(data).hexdigest()
OUT.write_bytes(data)
print(f"Restored: {OUT.name}")
print(f"SHA-256: {sha}")
if sha != EXPECTED:
    raise SystemExit(f"FAIL: expected {EXPECTED}")
print("PASS")
