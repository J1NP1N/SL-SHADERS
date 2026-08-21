from pathlib import Path
import hashlib, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / "core-spatial-v0.2"
base_fx = BASE / "SL_SSR_CORE_SPATIAL_v0_2.fx"
if not base_fx.exists():
    subprocess.check_call([sys.executable, str(BASE / "restore_core_spatial_v0.2.py")], cwd=BASE)

local_base = ROOT / "SL_SSR_CORE_SPATIAL_v0_2.fx"
out = ROOT / "SL_SSR_CORE_SPATIAL_v0_5.fx"
shutil.copy2(base_fx, local_base)
with (ROOT / "V0_2_TO_V0_5.patch").open("rb") as patch:
    subprocess.run(["patch", "-o", str(out), str(local_base)], stdin=patch, check=True)
local_base.unlink()

actual = hashlib.sha256(out.read_bytes()).hexdigest()
expected = "90f875b3f622d7e5301ce98413d52a9c0755adb1b10683079bf2c05773ff86c7"
print(out.name)
print("SHA-256", actual)
if actual != expected:
    raise SystemExit("SHA-256 mismatch")
print("PASS")
