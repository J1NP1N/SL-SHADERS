// SL_SSR_AvatarReceiver_v0_2.fx
// First runtime-testable milestone for SSR ON avatar materials as receivers.
//
// This effect is intentionally separate from SL_SSR_v0_49_AvatarThicknessTrace.fx.
// It does NOT implement or modify the v0.49 world->avatar hit/source path.
// The proven v0.49 AVATAR hit interval [D0, DavatarBack] remains owned by CORE.
//
// Receiver architecture in this file:
//   receiver identification = visible D0 with a valid native DavatarBack exit
//   receiver normal/material = SL_NORMALS + SL_GBUFFER_SPECULAR + SL_ALPHA_MASK
//   reflected-ray hit depth = Dstatic / SL_DEPTH_BACKGROUND only
//   reflected-ray hit color = Cstatic / SL_COLOR_BACKGROUND only
//   DDA = absent; this milestone uses the non-DDA view-space marcher only
//
// Required diagnostics are exposed through ARDisplayMode.
// v0.2 adds staged receiver-qualification views without changing SSR behavior in modes 0-5.

#include "ReShade.fxh"

#define SL_AR_MAX_STEPS 48
#define SL_AR_BINARY_STEPS 9

#define SL_AR_REJECT_NONE 0
#define SL_AR_REJECT_MISSING_D0 1
#define SL_AR_REJECT_MISSING_AVATAR_BACK 2
#define SL_AR_REJECT_THIN_INTERVAL 3
#define SL_AR_REJECT_LEGACY_REFLECTIVITY 4
#define SL_AR_REJECT_PBR_REFLECTIVITY 5
#define SL_AR_REJECT_ALPHA_MASK 6
#define SL_AR_REJECT_INPUT_UNAVAILABLE 7

uniform float4 SLBridgeViewport = float4(0.0, 0.0, 1.0, 1.0);
uniform float4 SLBridgeBufferInfo = float4(1.0, 1.0, 1.0, 1.0);
uniform float SLBridgeRegistrationValid = 0.0;

uniform float4 SLGIInvProjC0 = 0.0;
uniform float4 SLGIInvProjC1 = 0.0;
uniform float4 SLGIInvProjC2 = 0.0;
uniform float4 SLGIInvProjC3 = 0.0;
uniform float4 SLGIProjC0 = 0.0;
uniform float4 SLGIProjC1 = 0.0;
uniform float4 SLGIProjC2 = 0.0;
uniform float4 SLGIProjC3 = 0.0;
uniform float SLGIProjectionValid = 0.0;
uniform float SLProbeNativeValid = 0.0;
uniform float SLSceneLinearValid = 0.0;
uniform float SLGBufferSpecularValid = 0.0;
uniform float SLGITonemapValid = 0.0;
uniform float SLGIFinalExposure = 1.0;
uniform float SLGITonemapMix = 1.0;
uniform float SLGITonemapType = 0.0;

uniform int AREnable
<
    ui_label = "AVATAR RECEIVER — Enable";
    ui_tooltip = "Enable the avatar receiver composite. Diagnostic modes remain available.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 1;

uniform float ARStrength
<
    ui_label = "AVATAR RECEIVER — SSR Strength";
    ui_tooltip = "Reflection energy applied only to eligible avatar receiver pixels.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 1.00;

uniform float ARBaseReplacement
<
    ui_label = "AVATAR RECEIVER — Base Replacement";
    ui_tooltip = "Attenuate the avatar's existing scene-linear color under valid SSR instead of purely adding reflection.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.00;

uniform int ARTraceSteps
<
    ui_label = "AVATAR RECEIVER — Trace Steps";
    ui_tooltip = "Maximum non-DDA view-space ray-march steps against Dstatic.";
    ui_type = "slider";
    ui_min = 6; ui_max = SL_AR_MAX_STEPS;
> = 40;

uniform float ARInitialStep
<
    ui_label = "AVATAR RECEIVER — Initial Ray Step";
    ui_tooltip = "Initial reflected-ray step in Firestorm view-space units.";
    ui_type = "drag";
    ui_min = 0.02; ui_max = 1.0; ui_step = 0.01;
> = 0.12;

uniform float ARStepGrowth
<
    ui_label = "AVATAR RECEIVER — Ray Step Growth";
    ui_tooltip = "Exponential growth for later reflected-ray steps.";
    ui_type = "drag";
    ui_min = 1.0; ui_max = 1.6; ui_step = 0.01;
> = 1.18;

uniform float ARThickness
<
    ui_label = "AVATAR RECEIVER — Static Hit Thickness";
    ui_tooltip = "Maximum accepted Dstatic depth-crossing thickness after binary refinement.";
    ui_type = "drag";
    ui_min = 0.01; ui_max = 1.0; ui_step = 0.01;
> = 0.18;

uniform float ARRayOriginBias
<
    ui_label = "AVATAR RECEIVER — Ray Origin Bias";
    ui_tooltip = "Normal offset for avatar receiver rays; independent of hit thickness.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.25; ui_step = 0.005;
> = 0.010;

uniform float ARAvatarMinThickness
<
    ui_label = "AVATAR RECEIVER — Avatar Min Thickness";
    ui_tooltip = "Minimum positive native [D0,DavatarBack] interval required to classify a visible pixel as an avatar receiver.";
    ui_type = "drag";
    ui_min = 0.0001; ui_max = 0.25; ui_step = 0.001;
> = 0.002;

uniform int ARBackgroundEntryRecovery
<
    ui_label = "AVATAR RECEIVER — Background Entry Recovery";
    ui_tooltip = "Allow Dstatic background-to-geometry silhouette entries, matching the established static-world trace behavior.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 1;

uniform float ARBackgroundEntryConfidence
<
    ui_label = "AVATAR RECEIVER — Background Entry Confidence";
    ui_tooltip = "Confidence multiplier for Dstatic hits recovered from background-to-geometry entry.";
    ui_type = "drag";
    ui_min = 0.10; ui_max = 1.00; ui_step = 0.05;
> = 0.75;

uniform float ARMaxDistance
<
    ui_label = "AVATAR RECEIVER — Max Ray Distance";
    ui_tooltip = "Maximum view-space distance for avatar-to-static-world rays.";
    ui_type = "drag";
    ui_min = 1.0; ui_max = 96.0; ui_step = 0.5;
> = 32.0;

uniform float AREdgeFade
<
    ui_label = "AVATAR RECEIVER — Screen Edge Fade";
    ui_tooltip = "Fade accepted static-world hits near the screen boundary.";
    ui_type = "drag";
    ui_min = 0.001; ui_max = 0.25; ui_step = 0.005;
> = 0.08;

uniform float ARDistanceFadeStart
<
    ui_label = "AVATAR RECEIVER — Distance Fade Start";
    ui_tooltip = "View-space ray distance at which accepted-hit confidence begins fading.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 95.0; ui_step = 0.5;
> = 12.0;

uniform float ARLegacySpecularScale
<
    ui_label = "AVATAR RECEIVER — Legacy Specular Scale";
    ui_tooltip = "Scale Firestorm legacy specularRect.rgb before applying Cstatic reflection color.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.05;
> = 1.0;

uniform float ARLegacyEnvScale
<
    ui_label = "AVATAR RECEIVER — Legacy Environment Scale";
    ui_tooltip = "Scale classic-shiny/environment intensity from the native normal payload.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.05;
> = 1.0;

uniform float ARLegacyFallbackThreshold
<
    ui_label = "AVATAR RECEIVER — Legacy Fallback Threshold";
    ui_tooltip = "Below this authored legacy reflection signal, use the neutral dielectric fallback.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.10; ui_step = 0.001;
> = 0.005;

uniform float ARLegacyDielectricFallback
<
    ui_label = "AVATAR RECEIVER — Legacy Dielectric Fallback";
    ui_tooltip = "Neutral legacy reflectance used only when no specular RGB or classic-shiny intent is authored.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.25; ui_step = 0.005;
> = 0.040;

uniform float ARLegacyMinReflectivity
<
    ui_label = "AVATAR RECEIVER — Legacy Min Reflectivity";
    ui_tooltip = "Minimum legacy material reflectivity required for receiver eligibility.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.25; ui_step = 0.001;
> = 0.005;

uniform float ARPBRStrength
<
    ui_label = "AVATAR RECEIVER — PBR Strength";
    ui_tooltip = "PBR receiver response multiplier. Native roughness and metallic remain authoritative inputs.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.65;

uniform float ARPBRRoughnessPower
<
    ui_label = "AVATAR RECEIVER — PBR Roughness Power";
    ui_tooltip = "Controls how native PBR roughness suppresses avatar SSR response.";
    ui_type = "drag";
    ui_min = 0.25; ui_max = 4.0; ui_step = 0.05;
> = 1.25;

uniform float ARAlphaReceiverProtection
<
    ui_label = "AVATAR RECEIVER — Alpha Receiver Protection";
    ui_tooltip = "Suppress SSR where Firestorm marks alpha-covered receiver pixels.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

uniform int ARDisplayMode
<
    ui_label = "AVATAR RECEIVER — Diagnostic View";
    ui_tooltip = "Required milestone diagnostics plus normal final composite.";
    ui_type = "combo";
    ui_items =
        "Final composite\0"
        "Avatar receiver eligibility mask\0"
        "Avatar receiver normal / reflection direction\0"
        "Avatar -> static-world accepted-hit mask\0"
        "Avatar SSR contribution only\0"
        "Final composite OFF / ON comparison\0"
        "AVATAR RECEIVER — Geometry candidate\0"
        "AVATAR RECEIVER — Material candidate\0"
        "AVATAR RECEIVER — Rejection reason\0";
> = 0;

uniform float ARDebugGain
<
    ui_label = "AVATAR RECEIVER — Contribution Debug Gain";
    ui_tooltip = "Exposure-like gain used only by the avatar SSR contribution diagnostic.";
    ui_type = "drag";
    ui_min = 0.1; ui_max = 16.0; ui_step = 0.1;
> = 2.0;

texture SLNativeNormalsTex : SL_NORMALS;
texture SLNativeDepthTex : SL_DEPTH_PRIMARY_NATIVE;
texture SLBackgroundDepthTex : SL_DEPTH_BACKGROUND;
texture SLBackgroundColorTex : SL_COLOR_BACKGROUND;
texture SLAvatarBackDepthTex : SL_DEPTH_AVATAR_BACK;
texture SLAlphaMaskTex : SL_ALPHA_MASK;
texture SLSceneLinearTex : SL_SCENE_LINEAR;
texture SLGBufferSpecularTex : SL_GBUFFER_SPECULAR;

sampler SLNativeNormalsSampler
{
    Texture = SLNativeNormalsTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};
sampler SLNativeDepthSampler
{
    Texture = SLNativeDepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};
sampler SLBackgroundDepthSampler
{
    Texture = SLBackgroundDepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};
sampler SLBackgroundColorSampler
{
    Texture = SLBackgroundColorTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};
sampler SLAvatarBackDepthSampler
{
    Texture = SLAvatarBackDepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
