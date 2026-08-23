from pathlib import Path
import base64
import gzip
import hashlib

root = Path(__file__).resolve().parent
parts = sorted(root.glob("SL_SSR_v0_49_AvatarThicknessTrace.fx.gz.b64.part*"))
if len(parts) != 5:
    raise SystemExit(f"expected 5 parts, found {len(parts)}")

data = "".join(p.read_text(encoding="ascii").strip() for p in parts)
raw = gzip.decompress(base64.b64decode(data))
out = root / "SL_SSR_v0_49_AvatarThicknessTrace.fx"
out.write_bytes(raw)

sha = hashlib.sha256(raw).hexdigest()
expected = "354dd1deafedaabf25e7345632ce95c7b3f0627f5b1722ba6d8ce5e2037a6a7c"
print(out)
print("SHA-256:", sha)
if sha != expected:
    raise SystemExit("checksum mismatch")
print("PASS")
