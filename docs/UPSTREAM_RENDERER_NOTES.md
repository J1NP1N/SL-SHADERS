# Firestorm / Black Dragon renderer notes

Purpose: store already-audited upstream facts so future chats do not repeatedly re-read the viewer repositories. Add findings here with a source path and pinned commit whenever upstream source review materially changes our implementation.

These notes are architectural references, not copied upstream source. Firestorm remains the implementation target; Black Dragon is a comparison/reference viewer.

## Pinned source snapshots used for the current SSR audit

Firestorm:

- Repository: `FirestormViewer/phoenix-firestorm`
- Inspected commit: `f0d4a81c5ded331fb35d19e88544f0d22723bee5`

Black Dragon:

- Repository: `NiranV/Black-Dragon-Viewer`
- Inspected commit: `b2ca434b39bcd93aff0e23414999dddd73527e05`

Re-check upstream only when a newer viewer source version is relevant to the runtime being tested or when these notes do not answer the question.

## Firestorm G-buffer contract

### Common reader

Path:

`indra/newview/app_settings/shaders/class1/deferred/gbufferUtil.glsl`

Finding: `getGBuffer()` samples `diffuseRect`, `specularRect`, and the encoded normal buffer. It stores the sampled `specularRect` directly as `GBufferInfo.specular`. Thus `specularRect` is a first-class deferred material attachment, not an incidental temporary texture.

### Legacy materials

Path:

`indra/newview/app_settings/shaders/class3/deferred/materialF.glsl`

Deferred legacy output is explicit:

```text
frag_data[0] = diffuse RGB + emissive
frag_data[1] = specular RGB + glossiness in A
frag_data[2] = encoded normal + environment intensity + flags
```

The source comment identifies `frag_data[1].xyz` as specular color and `.w` as specular exponent/glossiness.

Implementation consequence: for a known legacy material with nonzero specular color, authoritative `specularRect.rgb` should not be identically zero. Alpha alone is not sufficient proof of a correct capture.

### PBR materials

Path:

`indra/newview/app_settings/shaders/class1/deferred/pbropaqueF.glsl`

PBR deferred output writes:

```text
frag_data[0] = linear base color
frag_data[1].rgb = Occlusion, Roughness, Metal
frag_data[2] = encoded normal with GBUFFER_FLAG_HAS_PBR
```

The code multiplies G by `roughnessFactor` and B by `metallicFactor`, confirming the active packed order used in this path is **O / R / M**.

Implementation consequence: PBR roughness comes from `specularRect.g`; metallic comes from `.b`; the normal-buffer G-buffer flag distinguishes PBR interpretation from legacy interpretation.

## Native SSR material interpretation

Paths in both inspected viewers:

`indra/newview/app_settings/shaders/class3/deferred/screenSpaceReflPostF.glsl`

At the pinned Firestorm and Black Dragon commits, the inspected SSR post shader is materially the same.

It samples:

- `specularRect`
- `diffuseRect`
- a scene/reflection color source (`diffuseMap` in this pass)
- depth
- normals / G-buffer flags

Material interpretation:

**Legacy**

- `specCol = specularRect.rgb`

**PBR**

- read `orm = specularRect.rgb`
- roughness = `orm.g`
- metallic = `orm.b`
- base color = `diffuseRect.rgb`
- dielectric F0 begins at ~0.04
- specular color is mixed from dielectric F0 toward base color using metallic

The reflected hit color is multiplied by the derived material specular color before being added to the scene result.

Implementation consequence: our ReShade SSR should obtain the same authoritative material data if we want Firestorm-aware material response. Reconstructing it later from final scene color is inferior and unnecessary if the live deferred attachment can be captured correctly.

## Native SSR temporal/camera-space clue

Path:

`indra/newview/app_settings/shaders/class3/deferred/screenSpaceReflUtil.glsl`

The utility declares both `modelview_delta` and `inv_modelview_delta`. In `traceScreenRay`, current position/reflection are transformed with `inv_modelview_delta` into the coordinate frame used by stored scene/depth inputs before marching.

This matches the earlier HybridGI runtime finding that Firestorm exposed `inv_modelview_delta` even when `modelview_delta` was absent. That inverse matrix is sufficient for current -> previous camera-space reprojection when the stored history is in the previous camera frame.

Limitation: camera delta does not provide true per-object velocity. Animated avatars/objects still require depth/normal/disocclusion rejection unless a separate motion-vector source is captured.

## Probe / indirect-lighting findings carried from the recovered project

Already established by prior source review + runtime testing:

- Firestorm reflection/irradiance probes can be captured by the native bridge when probes are enabled in viewer preferences.
- Firestorm already applies probe/environment lighting through its deferred lighting path. Broadly adding captured probe irradiance again would double-light the scene.
- HybridGI should therefore be a near-field/residual transport term over the viewer's stable low-frequency probe contribution, not a second full ambient solution.
- One shared temporal reprojection/rejection core is the intended long-term architecture for HybridGI, GTAO, SSR, and potentially later volumetric accumulation.

## HybridGI findings worth not rediscovering

- Smoothly interpolated per-pixel sample rotation (`SmoothPhase01`) caused coherent labyrinth/squiggle artifacts.
- Removing that smooth phase exposed translated ghost copies from a fixed kernel.
- High-frequency stochastic angular/radial scrambling converted coherent copies into fine sampling noise suitable for temporal accumulation.
- Runtime proved camera-space temporal reprojection can work using Firestorm `inv_modelview_delta` plus previous depth/normal rejection.
- Close-camera artifacts were strongly affected by projected gather footprint and represented-area normalization; v0.13/v0.14 addressed this rather than treating the symptom as a generic denoising problem.
- ReShade version ambiguity is a real failure mode: an older technique remained active during a supposed newer test. Unique FX/technique version labels are required.

## Firestorm standard DEPTH interoperability finding

Recovered prior work established that the bridge can take ownership of ReShade's standard `DEPTH` semantic, but directly aliasing Firestorm's native deferred depth was not enough for untouched stock depth effects. The follow-up approach was a normalized full-ReShade-sized R32F compatibility surface with Firestorm viewport registration and reconstructed depth convention.

Exact Firestorm normals remain a project-specific semantic because ReShade does not provide an equivalent universal normal semantic.

## Notes-maintenance rule

When source review finds something we expect to use again:

1. record the viewer + pinned commit;
2. record the exact file/path;
3. write the renderer contract in our own words;
4. state the implementation consequence;
5. update `HANDOFF.md` only if the finding changes the active hypothesis/test.

This file should prevent repeated broad source audits. Re-open upstream only for unanswered details or changed viewer versions.
