# CHAT HANDOFF — READ THIS FIRST

Last updated: 2026-08-19

This is the live project checkpoint.

## Current focus

Opaque SSR plumbing/material response are proven. The remaining artifact is an upside-down avatar-shaped missing region inside an otherwise correct floor reflection.

Do **not** treat the current target as a generic hole to fill. The immediate question is now:

> Is the first oversized candidate that the marcher labels/discards as `disocclusion` actually the avatar reflection we intended to hit?

Installed native bridge may remain **SLProbeLighting v1.6.11 / v0.15 PBRAlphaProbe**.

Current FX test: **SSR v0.29 CandidateIdentity — PENDING RUNTIME**.

v0.27 FullResBaseline and v0.28 ScreenDDAPrototype are prepared but should not replace the isolation test unless v0.29 is read first.

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
- v0.26 OriginBiasAudit: PARTIAL/INFORMATIVE — corrected small origin bias makes the artifact **a little better / recede slightly**, but the avatar-shaped target remains. Origin bias contributes geometrically but is not the root cause.
- v0.29 CandidateIdentity: PENDING — identifies the first oversized candidate that is skipped on rays which later terminate no-hit.

## Current proven facts

- The artifact exists in ray-hit diagnostics before material weighting/composite.
- Global `Hit Thickness` is not the controlling fix; testing up to 0.30 did not remove the target.
- Total ray range is not the controlling fix.
- The target ray reaches real geometry on both sides of the depth relation.
- A real `previousDelta < 0 && delta >= 0` candidate is formed.
- More binary refinement does not make the positive sample satisfy fixed global thickness.
- v0.25 proves terminal-only silhouette recovery is too late for most target rays.
- Old ray-origin bias was incorrectly coupled to thickness. Correcting it helps slightly but does not solve the target.
- `Disocclusion Skips = 3` must remain enabled while isolating this target; setting it to 0 regresses a separate known issue.

## Most important current hypothesis

The current code treats every refined candidate with:

```text
finalDelta > Hit Thickness
```

as an oversized/disocclusion candidate. If skips remain, that candidate is discarded immediately.

The target may therefore be produced by this exact sequence:

```text
reflective floor receiver
 -> reflected ray reaches avatar silhouette
 -> avatar surface creates a discontinuous/large positive depth delta
 -> valid avatar candidate is called "disocclusion"
 -> candidate is skipped
 -> no later valid crossing exists
 -> ray terminates BLUE
 -> upside-down avatar-shaped region receives no SSR
```

If this is true, the target is **not absent information**. The shader is locating the correct reflected object and deliberately discarding it.

This is what v0.29 tests directly.

## v0.29 CandidateIdentity

FX-only diagnostic revision based on v0.26 geometry. It does not change hit acceptance, material response, or composite behavior.

Keep:

- `Disocclusion Skips = 3`
- `Hit Thickness = 0.18`
- `Ray Origin Bias = 0.010`
- same camera angle

Required diagnostic 1:

`Display Mode -> First oversized candidate color`

For failed rays that encountered an oversized candidate, this displays the **scene-linear color at the first candidate UV that the tracer discarded**.

Interpretation:

- If the avatar's visible colors/shape reconstruct inside the bad reflected region, the marcher is finding the avatar and throwing it away as a false disocclusion.
- If the image instead shows wall/floor/another foreground surface, then the discarded candidate is a real occluder and the target must be isolated after that event.

Required diagnostic 2:

`Display Mode -> Skip-then-no-hit mask`

- WHITE = ray skipped at least one oversized candidate and still terminated without a hit.
- BLACK = otherwise.

If this white mask matches the upside-down avatar-shaped target, the skip path is causally responsible for the missing reflection.

Optional diagnostic:

`Display Mode -> Oversized candidate count`

Grayscale is candidate count / 4. One candidate is 25% gray, two is 50%, three is 75%, four+ is white.

v0.26 runtime record: `7eb97e3ac69cc32530d3694668051021f8ef5459`.
v0.29 source delta: `d76fc13b4b418bf79e29b35f4b3b6087e56df01e`.

Local package:

- `SL_SSR_v0_29_CandidateIdentity.zip`
- SHA-256 `2bf94ec85e4ace0df68620df75a514f783113709643329d06de7999e1764a22d`

## Trace-core audit

`docs/SSR_TRACE_CORE_AUDIT_2026-08-19.md` records the broader architecture findings.

Important points:

1. Ray-origin bias was incorrectly tied to `Hit Thickness`; fixed in v0.26.
2. Strict sign-crossing/binary refinement assumes local depth continuity that silhouettes do not provide.
3. Current SSR receiver trace is half resolution, so v0.27 FullResBaseline remains available if resolution needs isolation.
4. Firestorm native SSR uses adaptive depth-error behavior materially different from this custom marcher.
5. v0.28 ScreenDDAPrototype is prepared as a trace-core replacement using contiguous screen-pixel traversal and perspective-correct depth-slab testing.

Do not jump to DDA solely to make the artifact disappear. Read v0.29 first so we know whether the legacy marcher is discarding the correct avatar hit. That fact will determine how the replacement should classify foreground candidates.

## Prepared prototypes

### v0.27 FullResBaseline

Same trace family, but one receiver ray per full-resolution pixel. Use only if a resolution ambiguity remains.

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
