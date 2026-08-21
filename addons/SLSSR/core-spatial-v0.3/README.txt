CORE+SPATIAL — Full-Res Pixel Mapping v0.3

Branch: agent/ssr-spatial
Parent runtime milestone: be463f2c2319936dee452b89afd3fc7a11abac49
FX after restore: SL_SSR_CORE_SPATIAL_v0_3.fx
Restore: python restore_core_spatial_v0.3.py
FX SHA-256: 0da5556600465b14972b0f7494f4f2f6c5bc3683f8dc747022a7f4933371a5ce

Purpose
-------
Correct the broken v0.2 half-resolution -> full-resolution RT conversion without
changing trace acceptance, material response, avatar thickness, or Spatial roughness.
This remains a full-file CORE+SPATIAL runtime and replaces ordinary CORE v0.49.

Exact v0.2 mapping defects found
--------------------------------
1. No literal BUFFER_WIDTH/2, BUFFER_HEIGHT/2, doubled UV, or /2 raw/meta lookup
   survived in v0.2. The stale assumption was the access contract: the four RTs
   were promoted to full size, but direct center/composite/diagnostic reads still
   used LINEAR samplers inherited from the half-resolution upsample path.
2. Trace, ResolveHorizontal, ResolveVertical, and Composite still trusted their
   interpolated TEXCOORD directly rather than canonicalizing it to the center of
   the corresponding full-resolution backbuffer pixel. The intended x,y identity
   therefore remained implicit instead of being enforced end-to-end.
3. Resolve-radius diagnostic did not mask excluded/invalid receivers before reading
   material roughness, so avatar/foreground material could appear in a diagnostic
   intended to describe the static receiver.
4. Separate cleanup bug: TracePS tested Display Mode 22 twice, leaving Mode 23
   (No-hit depth history) unreachable.

Exact code correction
---------------------
- Added SSRFullResPixelCenterUV(): all four passes canonicalize raster UV to
  (floor(uv * BUFFER_SIZE) + 0.5) / BUFFER_SIZE.
- Raw/Meta/BlurH-center/Resolved direct reads are POINT sampled at that canonical
  full-resolution pixel center.
- Only the deliberate bilateral neighbor taps retain LINEAR filtering:
  RawLinear in horizontal resolve and BlurHLinear in vertical resolve.
- Filter offsets use BUFFER_RCP_WIDTH / BUFFER_RCP_HEIGHT as full-screen pixel size.
- Trace producer, both resolve passes, modes 31-36, and final composite use the
  same canonical screenUV contract.
- Mode 34 now masks through SSRResolveReceiverGeometry before showing radius.
- Mode 23 condition fixed.
- Added Display Mode 37: Full-res RT pixel mapping error. Trace writes a deterministic
  per-pixel pattern to Raw; Composite point-samples Raw and compares against the
  pattern expected for the same screen pixel. Correct producer/consumer mapping is
  black across the full backbuffer.

Preserved
---------
- D0 = SL_DEPTH_PRIMARY_NATIVE
- Dstatic = SL_DEPTH_BACKGROUND
- Cstatic = SL_COLOR_BACKGROUND
- DavatarBack = SL_DEPTH_AVATAR_BACK
- AVATAR hit volume remains exactly [D0,DavatarBack]
- WORLD continues to hit Dstatic and sample Cstatic
- TraceSSR and EvaluateRayDepth are unchanged from v0.2
- Spatial roughness/radius, bilateral acceptance, and contribution math unchanged
- full-resolution Raw/Meta/BlurH/Resolved textures remain enabled
- obsolete alternate/recovery paths remain absent
- no Hi-Z, Temporal, or Avatar Receiver integration

Runtime test state
------------------
CORE+SPATIAL — Full-Res Pixel Mapping v0.3: ON
CORE v0.49: OFF
TEMPORAL PRE/POST: OFF
HIZ DEBUG: OFF
AVATAR RECEIVER: OFF for isolated CORE testing
Never enable CORE+SPATIAL and ordinary CORE v0.49 together.

Runtime order
-------------
1. Mode 37 Full-res RT pixel mapping error: expected BLACK over the entire screen.
   Any colored pattern means Raw producer -> Composite consumer mapping is still wrong.
2. Mode 31 Static-world accepted-hit mask: must align pixel-for-pixel with scene.
3. Mode 32 Avatar-only accepted-hit mask: confirm validated avatar coverage unchanged.
4. Mode 33 Dual-trace selected layer: verify selected layer placement.
5. Mode 34 Resolve radius: must sit on the same eligible receivers, no avatar-shaped
   displaced/zoomed roughness image.
6. Mode 35 resolved confidence and Mode 36 rejection: verify same receiver alignment.
7. SSR contribution and Final composite: verify reflection returns to correct screen
   placement while retaining full-resolution edge coverage.
8. Recheck GOOD avatar reflection and confirm the pale/white secondary ghost remains absent.
