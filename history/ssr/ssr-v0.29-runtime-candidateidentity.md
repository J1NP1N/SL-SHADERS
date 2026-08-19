# SSR v0.29 CandidateIdentity runtime result

Date: 2026-08-19

Runtime settings retained:

- Disocclusion Skips = 3
- Hit Thickness = 0.18
- Ray Origin Bias = 0.010
- same known bad avatar-reflection camera angle

Returned diagnostics:

1. `Skip-then-no-hit mask`
2. `Oversized candidate count`
3. `First oversized candidate color`

## Observation

The `Skip-then-no-hit mask` lights the same lower-body / reflected-avatar region that is missing in the final reflection.

The `First oversized candidate color` reconstructs recognizable reflected-avatar/leg content at the first oversized candidate that the marcher discards.

The `Oversized candidate count` is low in the target region (roughly one/few candidates rather than a long chain), consistent with the ray encountering the avatar candidate, skipping it, and then failing to find a better hit.

## Conclusion

The target is not best described as unavailable screen-space information or a generic hole.

The evidence supports this causal chain:

```text
reflective floor ray
 -> reaches avatar candidate
 -> candidate refines with finalDelta > Hit Thickness
 -> candidate is classified oversized/disocclusion
 -> candidate is skipped
 -> no later valid hit is found
 -> ray returns no reflection
```

Therefore the current skip policy is capable of discarding the intended reflected avatar itself.

## Next isolated correction

Preserve the existing `Disocclusion Skips = 3` search behavior, but defer the first candidate that is actually skipped. If a later valid hit is found, that later hit still wins. Only when the ray later terminates ordinary BLUE/no-crossing should the saved candidate be considered as a reduced-confidence fallback.

This directly tests the classification error without globally disabling disocclusion skips or adding generic hole filling.
