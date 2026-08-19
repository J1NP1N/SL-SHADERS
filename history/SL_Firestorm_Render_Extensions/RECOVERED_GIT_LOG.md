# Recovered prior Git history

A real `.git` repository was recovered from the prior `SL_Firestorm_Render_Extensions_git(10).zip` archive. The original commit graph is preserved in the recovered local artifact and should be imported intact rather than recreated as fake commits.

Recovered commits, newest first:

```text
5239a82 Normalize Firestorm depth for standard ReShade effects
6c09d5b Route Firestorm depth into ReShade DEPTH semantic
1123624 Balance close-range GI and instrument tonemap capture
9773c22 Default v0.13 to final composite
216ca4b Correct close-range GI projected area and history trust
bccb60e Make v0.12 close-safe shader version unambiguous
981ab35 Stabilize close-range and dynamic temporal GI
65b3662 Calibrate screen-surfel GI transport energy
4510362 Use Firestorm tonemap delta for GI composite
630e3cd Fix ReShade FX frame sequence compile error
437efc8 Add first temporal HybridGI accumulation build
cf12c7c Initialize Firestorm render extensions project state
```

This history covers the HybridGI/Firestorm-depth line through the v0.14 and standard-ReShade-depth work. The live `SL-SHADERS` repo documents the recovered state and retains the newest installable checkpoints while the original historical graph remains a separate recovered repository artifact.
