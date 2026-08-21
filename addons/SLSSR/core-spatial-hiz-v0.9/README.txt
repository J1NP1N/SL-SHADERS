CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.9

Root cause corrected
--------------------
The spatial registration defect predates Hi-Z. The full-resolution CORE+SPATIAL conversion changed Raw/Meta/BlurH/Resolved to BUFFER_WIDTH x BUFFER_HEIGHT but continued to use the interpolated fullscreen TEXCOORD as the authoritative receiver address in Trace, both Spatial passes, and Composite. v0.3 only snapped that same interpolated coordinate and therefore could not repair a bad producer raster-domain interpolation.

v0.9 makes the full-resolution mapping explicit from the actual raster pixel:
- SSRFullResPixelCoord(pos) derives integer (x,y) from SV_Position.
- SSRFullResScreenUV(pos) derives the canonical screen UV from that same pixel center.
- Trace, ResolveHorizontal, ResolveVertical, and Composite use that canonical coordinate for receiver/depth/material access.
- direct same-pixel Raw/Meta/BlurH/Resolved center reads use tex2Dfetch at the exact integer pixel.
- fractional bilateral neighbor taps remain normalized/linear because Spatial radius can be fractional.

The v0.8 disposable Hi-Z viewport-reset pass is removed; that diagnosis was incorrect.

Preserved byte-for-byte from v0.8
---------------------------------
- EvaluateRayDepth and AVATAR [D0,DavatarBack]
- old WORLD TraceSSR implementation
- validated SLH53TraceWorld Hi-Z v0.53 implementation
- Dstatic/Cstatic WORLD contract
- nearest WORLD/AVATAR arbitration
- SurfaceReflectivity/material classification
- SSRReceiverRoughness / SSRResolveRadiusPx
- receiver depth/normal bilateral weighting and premultiplied coverage resolve
- DDA and obsolete recovery paths remain absent
- no Temporal integration

Runtime
-------
Technique: CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v0.9
FX: SL_SSR_CORE_SPATIAL_HIZ_v0_9.fx
SHA-256: 70d33f4dbc62bb35f65b8d2a9420afa96fdd4bb14aca6e70b974d09469bc6e52

Test with ordinary CORE/v0.49 OFF, TEMPORAL OFF, standalone HIZ DEBUG OFF, AVATAR RECEIVER OFF.
1. Mode 38 must register to the scene pixel-for-pixel with no top-left crop/zoom.
2. A/B old WORLD and Hi-Z WORLD must have identical screen placement.
3. Mode 32 avatar-only mask must remain unchanged.
4. Mode 33 arbitration must remain correct.
5. Final SSR placement must match the receiver geometry; only WORLD coverage should differ between A/B modes.
