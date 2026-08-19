# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This file exists so a fresh ChatGPT conversation can resume the project without reconstructing prior chat history. Update it whenever the active build, proven facts, current failure, or requested runtime test changes.

## Current focus

**SSR material-source proof is complete. Firestorm `specularRect` capture is proven.**

Active recovered checkpoint: **SLProbeLighting v1.6.8 / SSR v0.10 MainPassGate**.

Recovered source commit: `dd7022c80e0acf89295b11bda00ee788ae10d166`.

The exact v0.10 source is currently preserved in the uploaded recovery patch/bundle, not yet as normal browsable source files on GitHub `main`. Do not regress the project state to v0.8 merely because the large source import has not yet been transferred through the connector.

Do not resume SSR strength/weight/roughness/appearance tuning yet. The immediate next step is to confirm whether the proven bytes are being classified as legacy or PBR by the FX.

## What is now proven at runtime

- Firestorm/ReShade registration and projection data work.
- `SL_SCENE_LINEAR` contains valid world scene color.
- SSR ray-hit geometry works.
- Raw reflected hit color contains real scene color.
- **v0.10 proves the authoritative main-pass material G-buffer capture and private snapshot copy.**

The decisive v0.10 run on a red-specular legacy test object reported:

- `Source-proof sample: tex 8, 3840 x 2027` — full-resolution main deferred pass, not the 512x512 probe pass.
- `source read: OK`, `glError 0x0000`.
- `componentType 0x8C17 (UNSIGNED_NORMALIZED)`, `redBits 8` — normal RGBA8-style material attachment.
- center material values approximately `R 0.98 / G 0.60 / B 0.017 / A 0` with RGB nonzero across the sampled center block.
- snapshot statistics matched the source, proving the private copy path as well.

Conclusion: the long-standing black material diagnostic was **not** caused by a broken bridge, source read, or snapshot copy.

## Root cause fixed in v0.9 -> v0.10

### v0.9 ReadProof

The analyzer added explicit read success, `glGetError`, attachment component type/red-bit depth, dimensions, and center-block statistics.

That exposed the actual fault: the analyzer was reading `tex 14, 512 x 512`, a probe-space deferred pass, while the real main-pass `specularRect` existed at full resolution (`tex 8, 3840 x 2027` in the proven run).

Firestorm issues several authoritative deferred/probe-related draws per frame at the same `refmapCount`. Therefore `refmapCount` alone cannot distinguish 512x512 probe-space passes from the full-resolution main pass.

### v0.10 MainPassGate

v0.10 gates the source-proof freeze/analyze path to the full-resolution main pass using a self-calibrating height rule: accept candidate specular draws at >= 75% of the tallest specular draw observed.

This rejects 512-tall probe passes once the ~2027-tall main draw is known without hardcoding the user's resolution.

It also fixes the snapshot proof read so the snapshot is sampled using the snapshot's own dimensions rather than the source texture's dimensions.

The FX itself is unchanged from v0.8 through v0.10; these fixes are in the native add-on.

## Next runtime step

On the same red-specular object, report these two diagnostic views:

```text
Material class: legacy cyan / PBR magenta
Bridge status
```

Healthy bridge status is cyan.

Interpretation:

- **Material class = cyan (legacy):** next work verifies that the FX consumes the now-proven `specularRect` under the legacy interpretation and then resumes SSR weighting/appearance.
- **Material class = magenta (PBR):** the captured bytes are being interpreted as ORM; investigate material classification before appearance tuning.

The captured `R≈0.98, G≈0.60, B≈0.017, A=0` is plausibly a red legacy specular response, but its shape can also resemble PBR ORM (`R=occlusion`, `G=roughness`, `B=metallic`). Runtime class diagnostic decides this; do not infer it from RGB alone.

## Prior diagnostic progression worth retaining

**v0.5:** yellow bridge status meant scene-linear was valid while G-buffer specular was invalid; SSR was gated before ray tracing.

**v0.6 SnapshotTimingFix:** kept the snapshot alive until ReShade consumed it, removed unreliable `glGetError()` as copy-success predicate, and made ray-hit/raw-hit diagnostics independent of material validity. Runtime proved ray geometry and scene-color transport.

**v0.7 DirectGBuffer:** bound the live Firestorm specular attachment directly, but binding alone did not prove the payload was the correct draw.

**v0.8 SourceProof:** added numeric source/snapshot analysis. The later v0.9/v0.10 work showed that prior zero reads were clean reads of the wrong 512x512 probe-space draw.

## Upstream renderer contract retained

Pinned source audit already stored in `docs/UPSTREAM_RENDERER_NOTES.md`:

- Firestorm `f0d4a81c5ded331fb35d19e88544f0d22723bee5`
- Black Dragon `b2ca434b39bcd93aff0e23414999dddd73527e05`

At those revisions, both native SSR shaders directly sample `specularRect` and branch material interpretation by PBR flag. Legacy uses specular RGB; PBR interprets RGB as ORM.

## Recovery artifact for v0.10

Uploaded recovery artifacts:

- patch: `SL-SHADERS_ssr-v0.10-mainpassgate.patch`
  - 282,690 bytes
  - SHA-256 `a855700f61e81fc1323037c370cdaffc29b8d3a78639a6e59b36fdc1c49cff57`
- bundle: `SL-SHADERS_ssr-v0.10-mainpassgate.bundle`
  - 66,505 bytes
  - SHA-256 `c750b2a7d8306b9067528a095653b273ca1b6f11c9bd3c0875bb94ffad22c217`

The bundle contains target commit `dd7022c80e0acf89295b11bda00ee788ae10d166` with parent `8c3cd8b68ac8fd1acd0fef3f83d77a4284ebda5a`. `git bundle verify` accepts the bundle metadata and the target commit object/source tree is recoverable. Fetching every advertised ref fails because its embedded `origin/main` advertises ancestry not fully included. Treat `dd7022c` plus the patch as the recovery target, not the embedded remote-tracking refs.

## Other recovered work — not the active task

Preserved checkpoints include HybridGI v0.14, HBAO v0.5, SSGI v0.3, SLNativeBridge v0.9a, SLProbeBridge v0.3b, SLVolumetricBridge v0.1d, UI separation v0.1, iMMERSE Firestorm Native v0.6, and the historical Firestorm DEPTH override v0.2.1.

A real prior `SL_Firestorm_Render_Extensions` Git history was also recovered. Preserve the original commit graph; do not fabricate replacement history.

## Runtime-development rules

1. Every installable ZIP starts with `SL_` so `SL_InstallLatest.ps1` finds it.
2. FX-only package = hot install; Firestorm may remain open.
3. Native add-on/build package = Firestorm closed before install.
4. Debug screens/readouts are mandatory for renderer experiments.
5. Loop: build -> user runs real Firestorm -> reports screenshots/readouts/errors -> next revision.
6. Never infer a renderer stage works merely because a semantic is bound. v0.10 is the case study: a cleanly bound/read semantic was still the wrong draw.
7. New versions need unambiguous visible version identifiers.
8. Never call a package remotely backed up until byte count/checksum is verified.
9. When a runtime result changes the conclusion, update this handoff state.

## Fresh-chat bootstrap

Read in order:

1. `docs/HANDOFF.md`
2. `README.md`
3. `packages/RECOVERY_STATUS.md`
4. `docs/UPSTREAM_RENDERER_NOTES.md`
5. active v0.10 source/recovery artifact only if the next code change requires it

Do not ask the user to reconstruct the old conversation when these records contain the needed state.
