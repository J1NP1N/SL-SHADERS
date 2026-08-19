# SSR v0.21 NoHitHistory — runtime result

Date: 2026-08-19

Result: **PASS as diagnostic; target classified YELLOW / mixed-sign no-hit**.

The user intentionally kept `Disocclusion Skips = 3` rather than setting it to zero. This is correct for the current investigation: ORANGE is already established as the separate disocclusion/oversized-crossing class, and a skip count of 3 is the known working treatment for that separate issue. Do not disable it in future BLUE/YELLOW investigations unless specifically testing the ORANGE path.

Runtime result:

- `No-hit depth history` shows the bad upside-down avatar-reflection region as **YELLOW**.
- YELLOW means the failed ray sampled both negative (`delta < 0`) and non-negative (`delta >= 0`) geometry depths but still did not produce an accepted reflection hit.
- Therefore the target is not background-only, not insufficient trace range, and not the v0.20 background-entry case.
- The ray is reaching real geometry on both sides of the depth relation. The remaining fault is in transition ordering / candidate bracketing / binary refinement / oversized-candidate handling.

The v0.21 closest-depth view was also supplied; the key decisive result for the next revision is the YELLOW mixed-sign classification.

Next revision should instrument the actual crossing candidates rather than altering search range or disabling the known-good disocclusion skips. Specifically distinguish:

1. positive-to-negative depth transitions with no negative-to-positive candidate (entry overshoot / silhouette tunneling);
2. negative-to-positive candidates that reach refinement but are rejected as oversized and skipped;
3. refinement failures for another reason;
4. accepted hits.

Preserve `Disocclusion Skips = 3` for this test so the already-solved ORANGE path remains solved while the mixed-sign target is diagnosed independently.
