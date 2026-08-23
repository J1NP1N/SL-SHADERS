from pathlib import Path
import base64
import hashlib
import io
import tarfile

root = Path(__file__).resolve().parent
parts = sorted(root.glob("SL_SSR_native_backbone_v0.49.tar.gz.b64.part*"))
if len(parts) != 3:
    raise SystemExit(f"expected 3 parts, found {len(parts)}")

data = "".join(p.read_text(encoding="ascii").strip() for p in parts)
archive = base64.b64decode(data)
sha = hashlib.sha256(archive).hexdigest()
expected = "2a7cf9fe266bb165b85c63ffe7b2520c563ef0ec223a0b93594ad59463ad4c52"
print("archive SHA-256:", sha)
if sha != expected:
    raise SystemExit("checksum mismatch")

out = root / "restored"
out.mkdir(exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tf:
    tf.extractall(out)

print("restored to:", out)
for p in sorted(out.rglob("*")):
    if p.is_file():
        print(p.relative_to(out))
print("PASS")
