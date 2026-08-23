# SL Background Depth v0.2 — Test C3 Result

Date: 2026-08-20
Branch: `agent/ssr-background-depth`

## Result

Test C3 proved that the auxiliary depth FBO and GL rasterizer state are valid at the current invocation point, but the `LLCullResult` render maps are empty by then.

Observed log:

```text
SLSSR_BGDEPTH_C3 STATE sCull=1 program=186 viewport=0,0,3840,2027 scissor_enabled=0 ... cull_enabled=1 cull_mode=1029 front_face=2305 rasterizer_discard=0 depth_func=513 depth_write=1
```

For every requested static pass type:

```text
has=0 drawinfos=0 indices=0 null_vbs=0 avatar_entries=0
```

Final native depth readback:

```text
SLSSR_BGDEPTH_C3 RESULT min=1 max=1 changed_pixels=0 total_pixels=7783680 gl_error=0
```

## Interpretation

The failure is not the auxiliary FBO, viewport, shader bind, depth-test state, depth write mask, culling state, scissor state, rasterizer discard, or ReShade bridge.

The pass currently runs too late to reuse the main-world render maps. `sCull` still exists, but its render-map sizes are zero.

Relevant pinned Firestorm behavior:

- `LLPipeline::renderObjects()` ultimately iterates `beginRenderMap(type)` / `endRenderMap(type)`.
- `LLCullResult::clear()` resets all `mRenderMapSize[]` entries to zero.
- `LLCullResult::increment_iterator()` only advances the iterator; it does not consume entries.
- Firestorm's own optional `RenderDepthPrePass` is executed immediately **before** `renderGeomDeferred(..., true)` and uses `gPipeline.renderObjects(...)` while the world render maps are still populated.

## Next diagnostic

Move `renderSSRBackgroundDepth()` from after the main deferred geometry pass to immediately before `renderGeomDeferred(*LLViewerCamera::getInstance(), true)`, keeping C3 instrumentation active.

Expected success criteria:

- one or more `SLSSR_BGDEPTH_C3 MAP` entries report `drawinfos > 0`,
- `RESULT changed_pixels > 0`,
- `RESULT min < 1`,
- `Background NATIVE RAW` shows actual world geometry.
