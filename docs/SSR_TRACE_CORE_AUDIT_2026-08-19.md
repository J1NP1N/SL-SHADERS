# SSR trace-core audit — 2026-08-19

This note is a source-level audit of the current custom SSR marcher after the v0.21–v0.24 runtime diagnostics. It is intentionally broader than another threshold tweak.

## Runtime evidence entering the audit

The avatar-reflection artifact has been narrowed substantially:

- it exists in ray-hit diagnostics, before material weighting/composite;
- v0.21: failed target rays sample both negative and non-negative depth deltas;
- v0.22: a real `previousDelta < 0 && delta >= 0` candidate is formed;
- v0.23: increasing binary refinement from 5 to 9 iterations does not fix it;
- v0.24: a conservative terminal silhouette-edge recovery fires on only sparse pixels.

This means the issue is not simply trace range, global thickness, or insufficient binary iterations.

## Finding 1 — ray-origin bias is incorrectly coupled to hit thickness

Current code:

```hlsl
float3 startPos = originPos + originNormal * max(SSRThickness * 0.75, 0.01);
```

At the current test value `SSRThickness = 0.18`, this shifts the reflected ray origin by:

```text
0.18 * 0.75 = 0.135 view-space units
```

In Second Life scale this is approximately 13.5 cm if the captured view-space units correspond to world meters, which is very large for a self-intersection bias.

Consequences:

1. `Hit Thickness` is not actually an isolated hit-acceptance control; changing it also moves the ray origin.
2. Earlier tests that changed thickness changed two independent geometric quantities at once.
3. On a floor reflection, a ~0.135 m normal displacement can materially move the projected reflected ray and its silhouette intersection.

Required correction: introduce an independent `Ray Origin Bias` control with a small default and stop deriving it from `Hit Thickness`.

## Finding 2 — binary search assumes continuity that a single-layer depth buffer does not have

The current marcher forms a candidate on:

```hlsl
previousDelta < 0 && delta >= 0
```

and then binary-refines `t` until it reaches the positive side. It finally accepts only if:

```hlsl
0 <= finalDelta <= SSRThickness
```

That works when the sampled screen-depth function is locally continuous. At a visible-object silhouette it is not continuous: adjacent UVs can jump from far background/floor depth directly to the avatar's much nearer front surface.

A binary search over that discontinuity can converge spatially to the edge while `finalDelta` remains large forever. v0.23 is strong runtime evidence for exactly this: 9 binary iterations still leave the target candidate oversized.

Therefore `more binary steps` and `larger global thickness` are not principled fixes for the target.

## Finding 3 — legitimate silhouette hits and disocclusion crossings currently share the same oversized-candidate class

Current flow after refinement:

```text
finalDelta <= Hit Thickness -> hit
finalDelta > Hit Thickness  -> oversized candidate
```

An oversized candidate then consumes `Disocclusion Skips` before any terminal silhouette recovery is considered.

This creates an ambiguity:

- some oversized candidates really are foreground occluders that should be skipped;
- some are legitimate reflected-object silhouette entries where the single-layer depth field jumps discontinuously.

The runtime fact that `Disocclusion Skips = 3` helps the separate disocclusion artifact should be preserved. However, that does not prove every oversized candidate should first spend the same skip budget. The current classification is doing two jobs with one signal.

## Finding 4 — current trace target is half resolution

Current storage:

```hlsl
texture SLSSRRawTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
```

The ray itself samples full-resolution Firestorm depth, but only one receiver ray is launched per half-resolution SSR pixel and the result is bilinearly upsampled.

This is a valid optimization, but it is not a neutral debugging baseline for thin avatar limbs/silhouettes. A full-resolution trace comparison should be performed before finalizing edge-specific recovery logic.

## Finding 5 — custom marcher differs materially from Firestorm native SSR

Pinned Firestorm source:

`FirestormViewer/phoenix-firestorm@f0d4a81c5ded331fb35d19e88544f0d22723bee5`

Relevant files:

- `class3/deferred/screenSpaceReflPostF.glsl`
- `class3/deferred/screenSpaceReflUtil.glsl`

Firestorm's native `traceScreenRay` does not use our strict `negative -> positive -> fixed-thickness` bracket as its only hit rule. It uses:

- an absolute depth-separation test (`abs(delta) < distanceBias`),
- adaptive step correction based on the sign of depth error,
- exponential step growth,
- then a second refinement loop.

This does not mean native Firestorm's method should simply be copied; it means our current failure mode is specific to a materially different marcher.

## Finding 6 — a screen-space pixel DDA is the stronger long-term trace core

Morgan McGuire and Michael Mara's 2014 JCGT method, *Efficient GPU Screen-Space Ray Tracing*, traces the projected ray through a contiguous sequence of screen pixels using perspective-correct DDA and tests the ray's camera-space Z interval against a finite-thickness depth slab.

Properties relevant to our current artifact:

- contiguous screen-pixel coverage rather than exponentially spaced 3D samples;
- no gaps caused purely by projected sampling stride;
- perspective-correct ray depth interval per pixel;
- thickness is explicitly a depth slab, not also an origin offset;
- silhouette/depth-discontinuity behavior is handled as a screen-space intersection problem instead of assuming a continuous depth function.

This is a better architectural target than accumulating increasingly permissive special cases around `finalDelta > Hit Thickness`.

## Recommended development order

Do not abandon v0.25: its gate diagnostic is still useful for identifying which v0.24 criterion rejects the terminal candidate. But treat it as diagnostic evidence, not the basis for endless threshold tuning.

After reading v0.25, use this order:

### A. Decouple origin bias from thickness

Add an independent `Ray Origin Bias` control. Keep `Hit Thickness` only for hit/depth-slab semantics.

Run the existing bad camera angle with a small origin bias versus the old effective 0.135 value.

### B. Full-resolution trace baseline

Add a full-resolution diagnostic trace target with otherwise identical ray logic. Compare the avatar silhouette directly against the existing half-resolution result.

If full resolution fixes a large fraction of the hole, the eventual optimization should use temporal/checkerboard/upscale strategies instead of compensating with permissive hit acceptance.

### C. Stop extending the current binary-discontinuity workaround if A/B do not solve it

At that point replace the trace core rather than adding v0.26/v0.27/v0.28 layers of edge exceptions.

Two reasonable prototypes:

1. Firestorm-native-style adaptive depth-error stepping, useful as a lower-risk comparison because it matches the host viewer's existing SSR family.
2. Perspective-correct screen-space DDA / depth-slab tracing, preferred long-term because it is designed around screen-pixel traversal and single-layer depth-buffer intersection.

### D. Preserve already-proven work

A trace-core rewrite must not regress:

- exact Firestorm matrix/depth/normal bridge;
- ReShade-owned G-buffer publication;
- legacy/PBR classification;
- legacy explicit specular response;
- legacy no-spec dielectric fallback;
- v0.16 energy-replacement composite;
- the working `Disocclusion Skips = 3` behavior until an equivalent or better rule is proven;
- all diagnostic displays needed to compare old/new trace cores.

## Immediate rule

Do **not** loosen v0.24 silhouette thresholds globally before the v0.25 diagnostic is read. The current source already contains enough evidence that the trace core itself deserves correction.
