# SSR v0.31–v0.34 session — runtime findings

Date: 2026-08-19

## What was tried (all FX-only, on top of v0.30 DeferredCandidate)

- **v0.31 DDATrace** — added a perspective-correct screen-pixel DDA trace core as
  a toggle (`Use Screen-Pixel DDA`), no oversized-skip path. Runtime: DDA accepts
  on the avatar but does NOT resolve the artifact; finer stride reduces reflection
  overall rather than fixing it. **FAIL for the target.**
- **v0.32 SeeThrough (debug)** — `Trace Through Foreground`: skip foreground
  crossings without limit and reflect the surface behind. Runtime: no visible
  change vs off. The toggle only fires inside the oversized-skip branch, which the
  target rays don't reliably enter. **FAIL / design mistake.**
- **v0.33 PlanarProto (debug)** — screen-space vertical-mirror planar fill in the
  SSR holes, additive (walls untouched). Rough approximation. Demonstrated concept
  but not correct; not the fix.
- **v0.34 GhostCull** — `Min Reflection Confidence`: cull reflections below a
  confidence floor. Runtime: killed the gray "ghost" streak BUT left a hole in the
  real reflection under the feet. **FAIL — confidence is the wrong discriminator.**

## What the artifact actually is (corrected understanding)

The long-standing artifact is **NOT** a missing/broken avatar reflection and NOT a
dark shadow. Per the user: the avatar already reflects correctly wherever specular
is present. The real defect is a **faint stretched "ghost" copy of the avatar
behind her** in the reflection.

`Ray hit mask` shows it as a **gray** (partial-confidence) column trailing from her
feet, distinct from the solid white (full-confidence) correct reflection.

### Cause

This is camera-space SSR grazing behavior. SSR is built entirely off the CAMERA
(view-space ray reflected about the normal, marched against the camera depth
buffer, sampling on-screen color). Floor pixels behind/around her shoot grazing
reflection rays that travel a long screen distance and accept the avatar far from
where a true 3D reflection would put her → a stretched, low-confidence second
image. It is inherently camera-dependent and moves with the camera.

### Why it resists fixing

The correct reflection (short ray, under the feet) and the ghost (long grazing ray,
behind) are at **similar confidence**, so a confidence threshold cannot separate
them: culling the ghost also punches a hole in the real reflection (observed in
v0.34). The distinguishing axis is **ray length / grazing stretch**, not confidence.

## Recommended next direction (not yet built)

1. Cheap/symptomatic: cull by **hit distance / grazing stretch** instead of
   confidence — reject long-ray hits (the behind-ghost) while keeping short-ray hits
   (the under-feet reflection). Better axis than confidence; may still nick real
   reflection if any good hits are long-ray.
2. Correct/structural: a **scene-based planar reflection** (reflect avatar geometry
   across the floor plane, camera-independent) in the native add-on. Removes the
   entire camera-space failure class. Requires `SLProbeLighting.cpp` (NOT in repo).

## Repo note

The current full FX source is now stored at `addons/SLSSR/current-fx/` so the repo
can rebuild its own shader (previously only patches were tracked). The native
add-on source `SLProbeLighting.cpp` is still NOT in the repo — only the compiled
`.addon` exists — which blocks the structural (planar) fix.

## Settings note

The recovery machinery accumulated across v0.17–v0.30 (disocclusion skip,
background-entry, silhouette edge/gate, deferred candidate) plus this session's
debug toggles has produced heavy settings sprawl. Since the reflection itself is
largely correct, a cleanup pass (remove recovery paths that solve the mis-diagnosed
"hole", keep the core) is worth considering before further feature work.
