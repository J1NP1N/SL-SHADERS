from pathlib import Path
import base64, gzip, hashlib

ROOT = Path(__file__).resolve().parent
STEM = "SL_SSR_CORE_SPATIAL_HIZ_ENV_OCCLUSION_DIAG_v0_1.fx"
EXPECTED = "b17afe7222e22cc7c4011d47910d81ca126256f82e2c6627c299eebb8f97c9ba"
parts = sorted(ROOT.glob(STEM + ".gz.b64.part*"))
if not parts:
    raise SystemExit("encoded FX parts not found")
encoded = "".join(p.read_text(encoding="ascii").strip() for p in parts)
raw = gzip.decompress(base64.b64decode(encoded))
sha = hashlib.sha256(raw).hexdigest()
if sha != EXPECTED:
    raise SystemExit(f"FX SHA-256 mismatch: {sha} != {EXPECTED}")
out = ROOT / STEM
out.write_bytes(raw)
print(out)
print("SHA-256", sha)
