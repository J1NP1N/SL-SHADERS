# SL SSR background depth v0.2 — Test A2 success

## Result

After fixing the invocation site so `renderSSRBackgroundDepth()` runs in the actual main world deferred render instead of `display_cube_face()`, the native clear-only diagnostic succeeded.

Firestorm log:

```text
SLSSR_BGDEPTH_A2 EXECUTED tex=2031 size=3840x2027 fbo=12 fbo_status=36053 center=1 corner=1 gl_error=0
```

ReShade result:

```text
Link / native pair: CYAN
Background NATIVE RAW: solid white
```

## Conclusion

The following path is now proven for a constant far-depth value:

Firestorm auxiliary depth FBO -> depth texture export -> ReShade v0.2.2 backup copy -> `SL_DEPTH_BACKGROUND` -> FX sampling.

The repeated black result before this fix was primarily caused by the auxiliary pass being invoked from `display_cube_face()` instead of the normal main world render. The `mRT != &mMainRT` guard therefore caused the pass to return with `wrong_render_target`.

Do not revisit the earlier matrix/clear hypotheses unless new evidence requires it.

## Next

Run a controlled raw depth 0.5 test. Expected:

- native readback center/corner = 0.5
- `Background NATIVE RAW` = uniform 50% gray

If that succeeds, restore actual static geometry and debug only the geometry population/class filtering stage.
