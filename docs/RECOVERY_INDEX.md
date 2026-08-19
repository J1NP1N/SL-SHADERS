# Recovery index

Recovered on 2026-08-19 from ChatGPT Library artifacts and the prior `SL_Firestorm_Render_Extensions` Git archive.

## Native add-ons

- `SLNativeBridge` — v0.9a AlphaReplayMask.
- `SLProbeBridge` — v0.3b FBOAtlas.
- `SLProbeLighting` — current recovered source is v1.6.6 from SSR v0.8 SourceProof.
- `SLVolumetricBridge` — v0.1d PrivateShadowCopies.
- `SLSceneLayer` — v0.1 UISeparation.

`SLProbeLighting` has multiple historical checkpoints because it became the broader Firestorm/ReShade bridge. The v1.6.1 DEPTH-override source is historical and superseded by the current bridge.

## FX / integrations

- HybridGI v0.14 BalancedAreaTemporal.
- HBAO v0.5 SmoothAO.
- SSGI v0.3 RayMarch.
- SSR v0.8 SourceProof (its FX filename remains `SL_SSR_v0_1_LegacyFirst.fx`; package version is authoritative).
- iMMERSE Firestorm Native v0.6 RawAOAlphaReceiver.
- UI separation v0.1 boundary test.
- Black Dragon volumetric study v0.1d with private Firestorm shadow copies.

## Version interpretation

Built `.fx` and `.addon` files found independently in the Library may be older than the newest package. The versioned package/source checkpoint is authoritative unless runtime notes explicitly identify a later build. Observed binaries are recovery evidence, not automatically the active release.

## Preserved previous Git history

A previous `SL_Firestorm_Render_Extensions` Git archive was recovered with 12 commits covering HybridGI and Firestorm depth infrastructure through v0.14 / depth normalization. Preserve that history rather than flattening it into chat notes.
