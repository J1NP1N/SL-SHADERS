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
expected = "420fcf3f5bc3c0cfad4cf85cf14e56a8a4a5c8cc82239fb86be7904714a7b6c4"
print(out)
print("SHA-256:", sha)
if sha != expected:
    raise SystemExit("checksum mismatch")
print("PASS")
