SL Hi-Z Trace v0.1 - Depth-Slab Compare

PURPOSE
This is the first real hierarchy-guided SSR tracer. It is deliberately diagnostic-only: it does not replace v0.35, blur, temporal, or the final composite yet.

It consumes the validated `SL Hi-Z v0.1b - Min/Max Infrastructure` pyramid through `SLHiZTraceLink.addon` and traces reflected rays with coarse min/max tile rejection plus a full-resolution finite depth-slab test.

INSTALL
1. CLOSE FIRESTORM because this package installs/builds an .addon.
2. Install with the normal SL_InstallLatest.ps1 path.
3. Start Firestorm.
4. ReShade Performance Mode must remain OFF (the link mirrors v0.35 uniforms by name).

TECHNIQUE ORDER
- SL Hi-Z v0.1b - Min/Max Infrastructure
- SL SSR v0.35 - Legacy Resolve
- SL SSR Temporal v0.1 - Reprojected History
- SL Hi-Z Trace v0.1 - Depth-Slab Compare   <-- LAST

Both the Hi-Z infrastructure producer and the tracer default to Passthrough, so the normal v0.35 + Temporal image remains untouched until a diagnostic mode is selected.

FIRST TEST
1. `Hi-Z Trace Display -> Link status`
   - Healthy: Hi-Z link present + v0.35 raw link present + exact matrices valid. Expected cyan/green-ish, not red.
2. Keep v0.35 `Display Mode` on its normal final composite, then at the known grazing-ghost camera angle choose `v0.35 vs Hi-Z hit mask` in the comparison tracer.
   - WHITE = both tracers hit.
   - GREEN = Hi-Z only.
   - RED = old v0.35 only.
   - BLACK = neither.
3. The key question: what color is the long faint ghost region behind the valid avatar reflection?
   - RED there is promising: hierarchy/depth-slab traversal rejects the old bad hit.
   - WHITE there means the new geometry core reproduces the same hit, so Hi-Z alone is not the fix.
   - GREEN there means Hi-Z introduces a new hit and we inspect it before integration.
4. Also inspect `Hi-Z hit mask`, `Traversal iterations`, and `Reject reason` if needed.

DEFAULTS
- Start Mip: 6 (64x64 full-resolution tiles)
- Traversal Iterations: 128
- Initial Ray Travel: 0.06
- Tile Boundary Epsilon: 0.03 px
- Hi-Z Thickness Scale: 1.0

Do not tune these on the first run. The first goal is geometry classification versus v0.35.
