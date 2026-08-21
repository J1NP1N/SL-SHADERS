from pathlib import Path
import hashlib, subprocess, sys

root = Path(__file__).resolve().parent
v03 = root.parent / "core-spatial-v0.3"
src = v03 / "SL_SSR_CORE_SPATIAL_v0_3.fx"
if not src.exists():
    subprocess.check_call([sys.executable, str(v03 / "restore_core_spatial_v0.3.py")], cwd=v03)

s = src.read_text()
repls = {
    "// SL_SSR_CORE_SPATIAL_v0_3.fx": "// SL_SSR_CORE_SPATIAL_v0_4.fx",
    "// CORE+SPATIAL v0.3: explicit full-resolution pixel mapping for CORE + Spatial.": "// CORE+SPATIAL v0.4: v0.3 full-resolution pixel mapping plus diagnostic compile fix.",
    "// v0.3 keeps the v0.2 production cleanup and full-resolution receiver coverage,": "// v0.4 keeps the v0.3 production cleanup and full-resolution receiver coverage,",
    "float r = fmod(p.x, 7.0) < 1.0 ? 1.0 : 0.0;": "float r = (p.x - floor(p.x / 7.0) * 7.0) < 1.0 ? 1.0 : 0.0;",
    "float g = fmod(p.y, 11.0) < 1.0 ? 1.0 : 0.0;": "float g = (p.y - floor(p.y / 11.0) * 11.0) < 1.0 ? 1.0 : 0.0;",
    "float b = fmod(p.x + p.y * 3.0, 13.0) < 1.0 ? 1.0 : 0.0;": "float patternIndex = p.x + p.y * 3.0;\n    float b = (patternIndex - floor(patternIndex / 13.0) * 13.0) < 1.0 ? 1.0 : 0.0;",
    "technique SL_SSR_CORE_SPATIAL_v0_3": "technique SL_SSR_CORE_SPATIAL_v0_4",
    "ui_label = \"CORE+SPATIAL — Full-Res Pixel Mapping v0.3\";": "ui_label = \"CORE+SPATIAL — Full-Res Pixel Mapping v0.4\";",
}
for old, new in repls.items():
    if old not in s:
        raise RuntimeError(f"Expected v0.3 source text not found: {old}")
    s = s.replace(old, new, 1)

out = root / "SL_SSR_CORE_SPATIAL_v0_4.fx"
out.write_text(s)
sha = hashlib.sha256(out.read_bytes()).hexdigest()
print(out.name)
print(sha)
assert sha == "e1a6b85648e4469455d4ee6981ba40abca6f60918619affa2fffae5f28088049"
