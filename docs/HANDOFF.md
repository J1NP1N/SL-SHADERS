# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. The remaining artifact is an upside-down avatar-shaped missing region inside an otherwise correct floor reflection.

The target has now been isolated beyond a generic "hole": **v0.29 shows that the tracer reaches recognizable avatar/leg content as an oversized candidate, skips it as disocclusion, and many of those rays then terminate with no later hit.**

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.30 DeferredCandidate — PENDING RUNTIME**.

v0.27 FullResBaseline and v0.28 ScreenDDAPrototype remain prepared, but v0.30 should be read first because it directly tests the proven skip/misclassification chain.

## Runtime status

- v0.10 MainPassGate: PASS — full-resolution main-pass `specularRect` acquisition proven.
- v0.11 MainPassConsume: FAIL/informative — borrowed private GL texture sampled black in FX.
- v0.12 ReShadePublish: PASS — ReShade-owned material publication fixed sampling.
- v0.13 LegacyRGBResponse: PASS — legacy `specularRect.rgb` drives SSR even when alpha/glossiness is zero.
- v0.14 LegacyDielectricFallback: CONCEPT PASS — diffuse-only legacy surfaces can receive conservative SSR without authored spec maps.
- v0.15 PBRAlphaProbe: INCONCLUSIVE — known PBR alpha-blend glass fixture did not light up; glass work parked.
- v0.16 EnergyComposite: PARTIAL PASS — dark additive receiver/shadow bleed removed/reduced.
- v0.17 DisocclusionSkip: separate ORANGE class established. **Keep `Disocclusion Skips = 3`**; user reports this handles the known disocclusion issue.
- v0.18 RayRejectReasons: target missing reflection classified BLUE/no accepted crossing.
- v0.19 TraceBudget: FAIL/informative — enlarged trace range did not solve target.
- v0.20 BackgroundEntry: FAIL/informative — background-entry recovery did not identify target.
- v0.21 NoHitHistory: PASS diagnostic — target rays sample both negative and non-negative depth deltas.
- v0.22 CrossingPath: PASS diagnostic — target rays form a real negative-to-positive candidate that refines oversized.
- v0.23 DeepRefine: FAIL/informative — 5 -> 9 binary steps did not solve target.
- v0.24 SilhouetteEdge: FAIL/informative — terminal silhouette recovery fired on only sparse pixels.
- v0.25 SilhouetteGate: PASS diagnostic / architecture fail — target mostly remained ordinary BLUE; most rays never reached the terminal silhouette gate after normal skips.
- v0.26 OriginBiasAudit: PARTIAL/INFORMATIVE — corrected small origin bias makes the artifact recede slightly, but does not remove it.
- v0.29 CandidateIdentity: **PASS diagnostic / causal isolation** — `Skip-then-no-hit mask` matches the missing reflected-avatar region, `First oversized candidate color` reconstructs recognizable avatar/leg content, and candidate count is low. The intended reflected object is being found and then discarded by the skip path.
- v0.30 DeferredCandidate: PENDING — preserves all normal disocclusion skipping and uses the first actually-skipped candidate only if no later valid hit is found.

## Current proven facts

- The artifact exists in ray-hit diagnostics before material weighting/composite.
- Global `Hit Thickness` is not the controlling fix; testing up to 0.30 did not remove the target.
- Total ray range is not the fix.
- The target ray reaches real geometry on both sides of the depth relation.
- A real `previousDelta < 0 && delta >= 0` candidate is formed.
- More binary refinement does not make the positive sample satisfy fixed global thickness.
- v0.25 proves terminal-only silhouette recovery is too late for most target rays.
- Old ray-origin bias was incorrectly coupled to thickness. Correcting it helps slightly but does not solve the target.
- `Disocclusion Skips = 3` must remain enabled; setting it to 0 regresses a separate known issue.
- **v0.29 proves the current skip policy can discard the intended reflected avatar and then return no hit.**

## v0.29 CandidateIdentity runtime result

Returned diagnostics:

### `Skip-then-no-hit mask`

The white region follows the same reflected lower-body/avatar area that is missing from the final reflection.

### `First oversized candidate color`

The first discarded candidate reconstructs recognizable reflected avatar/leg content in the target. This is not merely wall/floor/background color.

### `Oversized candidate count`

The target contains only a small number of oversized candidates, consistent with the ray encountering the avatar candidate, skipping it, and then failing to find a better hit.

Conclusion:

```text
reflective floor ray
 -> reaches avatar candidate
 -> candidate refines oversized
 -> candidate is classified/discarded as disocclusion
 -> normal skip search continues
 -> no later valid hit exists for many target rays
 -> trace returns no reflection
```

This target is therefore a candidate-classification/retention problem, not a generic missing-information hole.

Runtime record commit: `50fad3d002d753b47d511dbc4deb01a868d7edc8`.

## v0.30 DeferredCandidate

FX-only isolated correction based on v0.29.

The existing disocclusion behavior is preserved exactly while tracing:

1. On the first oversized candidate that is **actually skipped**, save its UV and distance.
2. Continue the normal trace with `Disocclusion Skips = 3`.
3. If a later valid hit is found, that later hit wins; behavior is unchanged.
4. Only if the ray later terminates ordinary BLUE/no-crossing does v0.30 use the saved candidate as a reduced-confidence fallback.
5. Off-screen, ray-direction, zero-confidence, and terminal-oversized failures do not use this fallback.

New controls:

- `Deferred Candidate Fallback = 1`
- `Deferred Candidate Confidence = 0.55`

Keep:

- `Disocclusion Skips = 3`
- `Hit Thickness = 0.18`
- `Ray Origin Bias = 0.010`

New diagnostic:

`Display Mode -> Deferred-candidate fallback mask`

WHITE means the final hit came specifically from the saved skipped candidate after the normal trace otherwise ended no-hit.

Runtime test:

1. Hot-install `SL_SSR_v0_30_DeferredCandidate.zip`; Firestorm may remain open.
2. Verify technique `SL SSR v0.30 - Deferred Candidate`.
3. Keep the settings above.
4. Return:
   - `Deferred-candidate fallback mask`
   - `Final composite`
5. Without moving camera, toggle `Deferred Candidate Fallback = 0` and compare `Final composite`.

Interpretation:

- Fallback mask matches the former avatar hole and ON fills it while OFF restores it: causal PASS. The intended avatar candidate was being discarded by the skip path.
- Fallback produces unrelated/incorrect foreground reflections: classification needs an additional geometric filter before production.
- Fallback mask does not cover target: v0.29 correlation was insufficient; do not retain fallback.

Source delta commit: `283f5cf72c11d0817c69699656fc1dacf50ecddb`.

Local package:

- `SL_SSR_v0_30_DeferredCandidate.zip`
- SHA-256 `62069ed18c41d3ccbb9a2aa669af6a55746cc1db2c12655964e6d4b4840e5a26`

## Trace-core audit / prepared prototypes

`docs/SSR_TRACE_CORE_AUDIT_2026-08-19.md` records the broader architecture findings.

Important points:

1. Ray-origin bias was incorrectly tied to `Hit Thickness`; fixed in v0.26.
2. Strict sign-crossing/binary refinement assumes local depth continuity that silhouettes do not provide.
3. Current SSR receiver trace is half resolution; v0.27 FullResBaseline remains available if resolution needs isolation.
4. Firestorm native SSR uses adaptive depth-error behavior materially different from this custom marcher.
5. v0.28 ScreenDDAPrototype is prepared as a trace-core replacement using contiguous screen-pixel traversal and perspective-correct depth-slab testing.

### v0.27 FullResBaseline

Same trace family, one receiver ray per full-resolution pixel.

Source delta: `d0945f9a894ff04259e6a1240f60698a7ff4ce0c`.

### v0.28 ScreenDDAPrototype

Experimental alternate trace core with contiguous native screen-pixel traversal and finite depth-slab testing. Material response/composite remain unchanged.

Source delta: `b59bc237430a81c885ac719830785b2231d25336`.

## Glass checkpoint

Known test material:

- PBR, Alpha Mode Blend, base alpha 0.500
- metallic factor 1.000, roughness factor 1.000
- magenta ORM ≈ AO=1 / roughness=0 / metallic=1
- Base color UUID `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- ORM UUID `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal UUID `4ed76883-9057-3be5-c18e-1b878bf9dd88`

v0.15 first-segment PBR-alpha probe was black. Resume after current ray classification is settled.

## Runtime-development rules

1. Every installable ZIP starts with `SL_`.
2. FX-only package = hot install; Firestorm may remain open.
3. Native add-on/build package = close Firestorm before install.
4. Debug screens/readouts are mandatory.
5. Loop: build -> commit source delta/checkpoint -> user runs real Firestorm -> report result -> update handoff -> next revision.
6. Semantic-bound alone is not proof of shader-visible payload.
7. New versions require visible version identifiers.
8. Never call a binary package remotely backed up until byte count/checksum is independently verified.
