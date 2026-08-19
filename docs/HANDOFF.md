# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint. A replacement chat should resume from this file and should not reconstruct the project from old chat history unless a required artifact is actually missing.

## Current focus

Opaque SSR plumbing and material response are proven. The long-chased visual defect has now been **reclassified**.

It is **not** a missing avatar reflection and not a dark shadow. The avatar already reflects correctly where specular response exists. The actual defect is a **faint stretched ghost copy of the avatar behind the correct reflection**, visible in `Ray hit mask` as a gray / partial-confidence column trailing from the feet next to the solid correct reflection.

Current FX lineage: **SSR v0.34 GhostCull**.

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe** from the prior line; v0.31-v0.34 were FX-only experiments.

There is **no next runtime build prepared yet** after v0.34. The next implementation decision should be based on ray length / grazing stretch, or move structurally to a native planar reflection path.

## Corrected cause

The current ghost is a camera-space SSR grazing artifact.

The reflection ray is derived from the camera/view-space surface point and normal, marched against the camera depth buffer, then samples on-screen scene color. Floor pixels behind/around the avatar can therefore launch long grazing reflected rays that accept the avatar far from where a true 3D reflection would place it. This produces the stretched secondary image and makes the artifact camera-dependent.

The good reflection under the feet is generally a shorter path. The ghost behind it is a longer grazing path.

**Confidence is not a reliable separator.** v0.34 proved that the correct reflection and ghost overlap enough in confidence that raising a confidence floor removes the ghost but also punches a hole in the real reflection.

## v0.31-v0.34 runtime results

### v0.31 DDATrace — FAIL for target

Added a perspective-correct screen-pixel DDA trace core behind `Use Screen-Pixel DDA`. It removes the oversized-skip path and slab-tests stepped screen pixels directly.

Runtime: DDA accepts on the avatar but does not remove the ghost. Finer stride reduces reflection overall rather than correcting the artifact.

### v0.32 SeeThrough — FAIL / design mistake

`Trace Through Foreground` attempted unlimited foreground skipping and reflected the surface behind.

Runtime: no visible difference. The toggle only affected the oversized-skip branch, which the target rays do not reliably enter.

### v0.33 PlanarProto — concept only

Added a rough FX-only vertical screen-space mirror fill for missing SSR floor pixels.

It demonstrated the general planar-reflection idea but is not geometrically correct and is not the fix.

### v0.34 GhostCull — FAIL / informative

Added `Min Reflection Confidence`.

Runtime: raising it can kill the gray ghost streak, but it also removes valid reflection under the avatar's feet. This proves confidence is the wrong discriminator.

Exact session record: `history/ssr/SSR_v0.31-v0.34_SESSION_RUNTIME.md`.

## Prior proven infrastructure that remains valid

- Firestorm full-resolution main-pass `specularRect` acquisition is proven.
- ReShade-owned material publication is proven.
- Legacy `specularRect.rgb` can drive SSR even when alpha/glossiness is zero.
- PBR and legacy material classification infrastructure exists.
- Scene-linear reflection source is proven.
- SSR geometry transport works and produces real scene-color hits.
- `Disocclusion Skips = 3` solved a separate known issue and should not be casually removed without regression testing.
- Ray-origin bias was previously incorrectly coupled to `Hit Thickness`; that was corrected.

The v0.17-v0.30 recovery machinery was built while the target was being interpreted as a missing reflected-avatar region. The new diagnosis means those paths should **not** automatically be treated as the architecture for fixing the current ghost. They have also created substantial settings/debug sprawl.

## Recommended next direction

### Option A — next cheap diagnostic/fix

Instrument and gate by **hit distance / grazing stretch**, not confidence.

Goal: distinguish the short correct reflection from the long behind-avatar ghost. A useful next diagnostic should visualize accepted-hit distance or normalized screen/ray stretch directly before changing composite behavior.

If the ghost consistently occupies a separable long-ray band, test a conservative long-hit rejection/fade while checking that legitimate distant reflections are not removed.

### Option B — structural fix

Implement a **scene-based planar reflection** in the native add-on: reflect scene/avatar geometry across the receiving floor plane rather than relying on the camera depth buffer for that class of reflection.

This removes the camera-space failure class instead of tuning around it.

`SLProbeLighting.cpp` is **not currently present as a normal source file on GitHub `main`**. Earlier recovery artifacts may contain/reconstruct it, but it must be imported and verified before the native planar path should be treated as buildable from GitHub alone.

## Current source/recovery state

Uploaded bundle:

`SL-SHADERS_ssr-v0.31-v0.34-session.bundle`

- prerequisite: `47ba4ad3b9e884ab129f2558410f2c117ed06e2c`
- bundle HEAD: `fc5d5c5ec5c78a16434ea441495301e811578d50`
- SHA-256: `81e4578444077df9a6dbcc9f7e80c32a6f76500d2fb798bbc5f50ccfb2956d14`

The bundle contains:

- full v0.34 FX blob `08f9c78e0eeb50ec9c3f08c0e278afc9f841a78`
- exact runtime record blob `17b574ec29edfef5913c0f0d6c4538abfbd7cd19`
- v0.30 -> v0.34 patch blob `48321d06ec9868f59645557c0a09616f765c7dd5`

See `history/ssr/SSR_v0.31-v0.34_BUNDLE_PROVENANCE.md` for import verification.

Important: the uploaded bundle proves the full FX exists and is recoverable, but the GitHub connector in this chat does not expose a direct local-file-to-repository upload path. Do not claim the 69 KB full FX is a normal GitHub source file until the expected blob/path is independently verified on GitHub.

## Glass checkpoint

Known glass fixture remains parked while reflection transport is stabilized:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

v0.15 first-segment PBR-alpha probe was inconclusive/black. Do not mix glass debugging into the current ghost investigation.

## Runtime-development rules

1. Every installable ZIP starts with `SL_`.
2. FX-only package = hot install; Firestorm may remain open.
3. Native add-on/build package = close Firestorm before install.
4. Debug screens/readouts are mandatory for experimental renderer changes.
5. Loop: build -> commit source/checkpoint -> user runs real Firestorm -> report screenshots/readouts/errors -> update handoff -> next revision.
6. Semantic-bound alone is not proof of shader-visible payload.
7. Every new FX version needs an unambiguous visible technique/version identifier.
8. Never call a binary package remotely backed up until byte count/checksum is independently verified.
9. When runtime evidence changes the diagnosis, update this handoff immediately rather than carrying the old framing forward.

## Fresh-chat bootstrap

Read in this order:

1. `docs/HANDOFF.md`
2. `history/ssr/SSR_v0.31-v0.34_SESSION_RUNTIME.md`
3. `history/ssr/SSR_v0.31-v0.34_BUNDLE_PROVENANCE.md`
4. `docs/SSR_TRACE_CORE_AUDIT_2026-08-19.md` only if changing the trace core
5. `docs/UPSTREAM_RENDERER_NOTES.md` only if viewer-source details are needed

Do not ask the user to retell the v0.31-v0.34 session unless these files are demonstrably missing the needed runtime observation.
