from pathlib import Path
import base64, gzip, hashlib

ROOT = Path(__file__).resolve().parent
PARTS = sorted(ROOT.glob("SL_SSR_CORE_SPATIAL_v0_3.fx.gz.b64.part*"))
EXPECTED_SHA256 = "0da5556600465b14972b0f7494f4f2f6c5bc3683f8dc747022a7f4933371a5ce"
OUT = ROOT / "SL_SSR_CORE_SPATIAL_v0_3.fx"

blob = "".join(p.read_text().strip() for p in PARTS)
data = gzip.decompress(base64.b64decode(blob))
actual = hashlib.sha256(data).hexdigest()
if actual != EXPECTED_SHA256:
    raise SystemExit(f"SHA-256 mismatch: {actual} != {EXPECTED_SHA256}")
OUT.write_bytes(data)
print(f"Restored: {OUT.name}")
print(f"SHA-256: {actual}")
print("PASS")
