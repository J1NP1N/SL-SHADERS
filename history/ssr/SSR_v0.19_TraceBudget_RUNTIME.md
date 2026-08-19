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
- The remaining likely class is **sampling/tunneling**: the exponentially spaced march may step over thin/steep reflected geometry without ever observing the required negative-to-positive depth sign change.
- Hit thickness cannot fix a crossing that was never sampled; the prior 0.30 thickness test already showed this.

Next test should reduce step growth / increase local sampling density, or add a diagnostic that records minimum absolute depth delta along BLUE rays to prove a near-miss before redesigning the marcher.

Do not regress the proven v0.16 energy composite or material-response paths.
