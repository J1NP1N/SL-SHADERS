SSR Environment Occlusion / Sky Leakage — diagnostic milestone v0.1

Status
------
Diagnostic only. This milestone does not change final sky/cloud/environment composition and must not be treated as a leak fix until the runtime classification has been tested.

Branch and baseline
-------------------
Branch: agent/ssr-environment-occlusion
Starting SHA (exact agent/ssr-spatial HEAD): 7067519e973d464818ba54c3128108ab4cbba67f
Production baseline technique: CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v1.0
Production baseline generated FX SHA-256: 715deb015938b879ae9a23cd24f1cc26adac2ffe3d731f9edaf70a911e0bb755
Diagnostic implementation commit SHA: PENDING_IMPLEMENTATION_COMMIT

Runtime artifact
----------------
Runtime FX (restored/generated): SL_SSR_CORE_SPATIAL_HIZ_ENV_OCCLUSION_DIAG_v0_1.fx
Committed self-contained FX source package: SL_SSR_CORE_SPATIAL_HIZ_ENV_OCCLUSION_DIAG_v0_1.fx.gz.b64.part01 through part06 + restore_runtime_fx.py
FX SHA-256: b17afe7222e22cc7c4011d47910d81ca126256f82e2c6627c299eebb8f97c9ba
ReShade technique label: CORE+SPATIAL — Hi-Z v0.53 ENV OCCLUSION DIAG v0.1
Internal technique symbol: SL_SSR_CORE_SPATIAL_HIZ_ENV_OCCLUSION_DIAG_v0_1
Diagnostic display mode: 39 — Environment visibility: blocked red / escape blue / WORLD hit green

Classification
--------------
GREEN = the existing Hi-Z WORLD path produced a normal accepted static-world SSR hit under the existing acceptance and confidence policy.
BLUE = the separate visibility query found no blocking Dstatic geometry and the reflected ray escaped the valid static-world screen domain, or reached its existing Hi-Z range endpoint on background Dstatic. Environment/sky/cloud fallback is therefore eligible for the later composition milestone.
RED = static Dstatic geometry blocks the reflected ray even though no normal accepted WORLD contribution is available. This includes an existing geometry hit rejected by the unchanged confidence policy and an occluder confirmed by the separate visibility query. Environment fallback must be forbidden in the later composition milestone.
BLACK = invalid receiver/setup, traversal budget exhaustion, unresolved non-background range endpoint, or otherwise unclassified/no contribution.

Implementation contract
-----------------------
SLH53TraceWorld is unchanged byte-for-byte from the exact v1.0 production FX. Its Hi-Z traversal, refinement, thickness, front tolerance, discontinuity handling, and fresh full-resolution Dstatic final acceptance are not modified.

TraceSSR is unchanged byte-for-byte, so the AVATAR tracer and [D0,DavatarBack] interval are unchanged. Normal WORLD/AVATAR nearest-hit arbitration, material/roughness logic, accepted WORLD Cstatic sampling, Raw/Meta registration, Spatial filtering, and normalized-TEXCOORD full-resolution raster mapping remain unchanged outside diagnostic mode 39.

The new SLH53ClassifyEnvironmentVisibility query is diagnostic state only. It reuses the existing static Hi-Z min/max pyramid, descends possible blocker intervals to mip 0, and uses fresh full-resolution Dstatic as authority before classifying RED. It does not produce or substitute a WORLD hit and does not feed final composition.

The diagnostic uses a private SLEOD01* namespace for its Raw/Meta/Spatial and Hi-Z intermediates so the production v1.0 FX may remain present without same-name ReShade texture aliasing.

No DDA, Temporal SSR, Background Entry Recovery, Silhouette Edge Recovery, Deferred Candidate Fallback, or Disocclusion Skips are introduced.

Build / reproduction
--------------------
The current production artifact workflow uses deterministic patch/generator scripts, so this milestone includes build_environment_occlusion_diag_v0.1.py.

Two reproducible paths are provided. To restore the exact committed runtime artifact without any external baseline:

  python restore_runtime_fx.py

To rebuild from production source, run the patch generator against the exact generated production v1.0 FX whose SHA-256 is 715deb015938b879ae9a23cd24f1cc26adac2ffe3d731f9edaf70a911e0bb755:

  python build_environment_occlusion_diag_v0.1.py --base <path-to>/SL_SSR_CORE_SPATIAL_HIZ_v1_0.fx

The builder rejects any other baseline, asserts the production WORLD and AVATAR trace functions are byte-for-byte unchanged, asserts the corrected normalized-TEXCOORD/full-resolution contract, and verifies the generated diagnostic FX SHA-256. The restore path independently verifies the same runtime FX SHA-256.

Runtime test
------------
1. Run `python restore_runtime_fx.py`, then copy SL_SSR_CORE_SPATIAL_HIZ_ENV_OCCLUSION_DIAG_v0_1.fx into C:\Program Files\FirestormOS-SLSSRBGDepth\reshade-shaders\Shaders.
2. Enable only "CORE+SPATIAL — Hi-Z v0.53 ENV OCCLUSION DIAG v0.1" for this test. Keep ordinary CORE/v0.49 OFF, Temporal OFF, standalone HIZ DEBUG OFF, and Avatar Receiver OFF.
3. Select Display Mode 39: "Environment visibility: blocked red / escape blue / WORLD hit green".
4. In an enclosed room/building with reflective surfaces, aim a reflected ray toward a visible ceiling/roof. The receiver should classify RED before any later environment fallback exists.
5. Aim a reflected ray toward a visible wall. It should classify RED.
6. Aim a reflected ray through a genuine opening/open sky. It should classify BLUE.
7. Normal valid static-world SSR intersections should remain GREEN.
8. Return to normal display modes and compare against production v1.0: WORLD reflection placement must not move. Spatial resolve OFF/ON must remain full-screen and pixel-registered.
9. Check existing avatar diagnostics/behavior (including modes 32 and 33). Avatar reflection behavior and nearest-layer arbitration must remain unchanged.

Do not proceed to environment composition changes until this diagnostic has passed the runtime checks above.
