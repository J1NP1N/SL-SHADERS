# SSR v0.19 TraceBudget — runtime result

Date: 2026-08-19

Result: **FAIL for the target artifact, informative**.

Runtime screenshot confirms the persistent avatar-adjacent bad strip is still BLUE in `Ray termination reason` on v0.19.

Important runtime settings visible in the screenshot were actually more aggressive than the requested baseline:

- Trace Steps = 48
- Initial Ray Step = 0.12
- Ray Step Growth = 1.18
- Maximum Ray Distance = 128
- Hit Thickness = 0.18
- Disocclusion Skips = 4
- Skipped-Hit Confidence = 1.00

Interpretation:

- The v0.19 hard-loop extension removed the old 32-iteration ceiling, but the target strip still produces no accepted depth crossing.
- Because 48 exponential samples at 0.12 / 1.18 can reach beyond the visible 128-unit max-distance setting, this is no longer explained by insufficient total trace range.
- Follow-up runtime images separate two failure classes: ORANGE is the explicit oversized/disocclusion-crossing rejection path, while the target missing reflection remains BLUE/no accepted crossing.
- The user observed that the BLUE missing region has the shape of the avatar reflection, upside down. This is a critical geometric clue: the reflected ray projection is plausibly reaching the correct screen-space silhouette, but the depth-crossing detector is failing to register entry into that silhouette.

## Stronger source-level hypothesis: background -> geometry entry miss

The current marcher only starts binary refinement when:

`previousValid && previousDelta < 0.0 && delta >= 0.0`

However, when a sample lands on background, the code does:

`previousValid = false`

and continues.

Therefore this sequence is possible:

1. ray sample is background -> `previousValid = false`;
2. next ray sample lands directly on the avatar and already has `delta >= 0`;
3. no crossing is detected because `previousValid` is false;
4. that positive delta becomes the new previous sample;
5. the ray may leave the thin avatar silhouette without ever seeing the required negative-to-positive transition.

That failure naturally produces a BLUE no-crossing hole shaped like the reflected avatar even though the screen-space projection itself is correct.

This is more specific than generic exponential-step tunneling. Denser stepping may reduce the symptom, but the structural bug is that **background-to-geometry entry cannot currently bracket a hit when the first geometry sample is already non-negative**.

Next revision should test/fix background-entry hit bracketing directly before replacing the entire marcher. Preserve the existing ORANGE disocclusion diagnostic as a separate failure class.

Do not regress the proven v0.16 energy composite or material-response paths.
