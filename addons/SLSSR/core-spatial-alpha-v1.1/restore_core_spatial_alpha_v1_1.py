from pathlib import Path
import base64
import gzip
import hashlib

ROOT = Path(__file__).resolve().parent
PATTERN = "SL_SSR_CORE_SPATIAL_ALPHA_DIAG_v1_1.fx.gz.b64.part*"
OUT = ROOT / "SL_SSR_CORE_SPATIAL_ALPHA_DIAG_v1_1.fx"
EXPECTED = "b26229c5041affbe2c39ae90c7437ee9f20e5fe1026a1f5c3860f8e312bdcee5"

parts = sorted(ROOT.glob(PATTERN))
if not parts:
    raise SystemExit("No archive parts found")
encoded = "".join(p.read_text().strip() for p in parts)
raw = gzip.decompress(base64.b64decode(encoded))
OUT.write_bytes(raw)
actual = hashlib.sha256(raw).hexdigest()
print(OUT.name)
print("SHA-256", actual)
if actual != EXPECTED:
    raise SystemExit("SHA-256 mismatch")
print("PASS")
