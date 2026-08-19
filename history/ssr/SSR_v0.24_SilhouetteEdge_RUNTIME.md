# SSR v0.24 SilhouetteEdge — runtime result

Date: 2026-08-19

Result: **FAIL for the target artifact, informative**.

Runtime screenshot of `Silhouette-edge recovered hit mask` shows only sparse isolated recovered pixels. The persistent upside-down avatar-shaped missing reflection is not substantially represented by the new recovery mask.

Runtime settings visible/retained:

- `Silhouette Edge Recovery = 1`
- `Silhouette Edge Confidence = 0.60`
- `Silhouette Min Depth Jump = 0.25`
- `Silhouette Max Pixel Span = 2.0`
- `Disocclusion Skips = 3`
- `Hit Thickness = 0.18`

Interpretation:

- v0.24's recovery path is technically reachable, but it only accepts a very small number of pixels.
- The target is therefore still being rejected by one or more of the conservative silhouette-edge gates.
- Do **not** loosen the gates blindly. The next revision should preserve behavior and color-code which exact gate rejects each terminal oversized candidate: refined positive validity, negative-side bracket validity, minimum foreground depth jump, maximum refined pixel span, or combinations thereof.
- Keep `Disocclusion Skips = 3`; that remains the known working setting for the separate disocclusion path.

Next revision: **SSR v0.25 SilhouetteGate**, diagnostic-only.
