// SL_SSR_Temporal_v0_3_AvatarReactive.fx
// Temporal accumulation/reprojection wrapper with animated-reflection reactive rejection.
//
// IMPORTANT PIPELINE ORDER:
//   1. TEMPORAL PRE — v0.3 Capture
//   2. CORE — accepted CORE+SPATIAL production core
//   3. TEMPORAL POST — v0.3 Avatar-Reactive Resolve
//
// This effect remains presentation-delta based: it does not modify or depend on
// CORE trace internals. It is intentionally separable so it can wrap the accepted
// CORE+SPATIAL artifact after that workstream is frozen.

#include "ReShade.fxh"

// -----------------------------------------------------------------------------
// Existing Firestorm / SLProbeLighting bridge state.
// -----------------------------------------------------------------------------
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

uniform float4 SLGIInvModelviewDeltaC0 = 0.0;
uniform float4 SLGIInvModelviewDeltaC1 = 0.0;
uniform float4 SLGIInvModelviewDeltaC2 = 0.0;
uniform float4 SLGIInvModelviewDeltaC3 = 0.0;
uniform float SLGIMotionValid = 0.0;

uniform int SLSSRTemporalFrameIndex < source = "framecount"; >;

// Current D0 and receiver normals from the existing native bridge. No object-motion vectors are invented.
texture SLPrimaryDepthTex : SL_DEPTH_PRIMARY_NATIVE;
texture SLNativeNormalsTex : SL_NORMALS;

sampler SLPrimaryDepthSampler
{
    Texture = SLPrimaryDepthTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = POINT;
};

sampler SLNativeNormalsSampler
{
    Texture = SLNativeNormalsTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = POINT;
};

// -----------------------------------------------------------------------------
// Temporal controls.
// -----------------------------------------------------------------------------
uniform int SSRTemporalEnable
<
    ui_label = "Temporal Accumulation";
    ui_tooltip = "Temporally reproject only the SSR contribution captured around the accepted CORE.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 1;

uniform float SSRTemporalHistoryWeight
<
    ui_label = "Temporal History Weight";
    ui_tooltip = "Maximum previous-frame contribution after all rejection tests.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.97; ui_step = 0.01;
> = 0.88;

uniform float SSRTemporalDepthTolerance
<
    ui_label = "Depth Rejection";
    ui_tooltip = "Minimum previous-frame view-depth tolerance. A relative depth term is added automatically.";
    ui_type = "drag";
    ui_min = 0.002; ui_max = 0.25; ui_step = 0.002;
> = 0.015;

uniform float SSRTemporalNormalThreshold
<
    ui_label = "Normal Agreement";
    ui_tooltip = "Minimum reprojected receiver-normal agreement.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.99; ui_step = 0.01;
> = 0.90;

uniform float SSRTemporalEdgeMarginPx
<
    ui_label = "Screen Edge Reject (px)";
    ui_tooltip = "Reject history when current or reprojected coordinates are too close to the screen edge.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 32.0; ui_step = 0.5;
> = 3.0;

uniform float SSRTemporalCameraCutThreshold
<
    ui_label = "Camera Cut Threshold";
    ui_tooltip = "Maximum allowed element delta from identity in the current-to-previous view transform. Lower values reset on faster camera changes.";
    ui_type = "drag";
    ui_min = 0.02; ui_max = 2.0; ui_step = 0.01;
> = 0.35;

uniform float SSRTemporalContributionEpsilon
<
    ui_label = "Hit Transition Epsilon";
    ui_tooltip = "Presentation-space SSR contribution below this is treated as no current hit for temporal transition rejection.";
    ui_type = "drag";
    ui_min = 0.0001; ui_max = 0.05; ui_step = 0.0001;
> = 0.0015;

uniform float SSRTemporalClampExpansion
<
    ui_label = "Neighborhood Clamp";
    ui_tooltip = "Expands the current 3x3 SSR-contribution envelope before clamping history.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 0.20;

uniform float SSRTemporalRadianceRejectStart
<
    ui_label = "Radiance Reject Start";
    ui_tooltip = "Begin reducing stale history when it differs strongly from the current SSR contribution.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.12;

uniform float SSRTemporalRadianceRejectEnd
<
    ui_label = "Radiance Reject End";
    ui_tooltip = "Fully reject stale history by this normalized current/history difference.";
    ui_type = "drag";
    ui_min = 0.05; ui_max = 2.0; ui_step = 0.01;
> = 0.55;

uniform float SSRTemporalMotionStartPx
<
    ui_label = "Motion Trust Start (px)";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 16.0; ui_step = 0.25;
> = 1.5;

uniform float SSRTemporalMotionEndPx
<
    ui_label = "Motion Trust End (px)";
    ui_tooltip = "History reaches zero at this camera-reprojected motion magnitude.";
    ui_type = "drag";
    ui_min = 1.0; ui_max = 64.0; ui_step = 0.5;
> = 24.0;

uniform float SSRTemporalJitterPixels
<
    ui_label = "History Jitter (hard disabled)";
    ui_tooltip = "Compatibility control only. v0.3 never applies history jitter; the runtime requirement is hard-off.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.0; ui_step = 0.01;
> = 0.00;

uniform float SSRTemporalReactiveRejectStart
<
    ui_label = "Animated Content Reject Start";
    ui_tooltip = "Begin reducing history when its reflected content has no close RGB match in the current 3x3 contribution neighborhood.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.10;

uniform float SSRTemporalReactiveRejectEnd
<
    ui_label = "Animated Content Reject End";
    ui_tooltip = "Fully reject history when unsupported reflected-content divergence reaches this normalized distance.";
    ui_type = "drag";
    ui_min = 0.02; ui_max = 1.0; ui_step = 0.01;
> = 0.30;

uniform int SSRTemporalResetHistory
<
    ui_label = "Reset History";
    ui_tooltip = "Set to 1 for one frame to discard temporal history, then return to 0.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 0;

uniform int SSRTemporalDisplayMode
<
    ui_label = "Temporal Display";
    ui_type = "combo";
    ui_items =
        "Final temporal SSR\0"
        "Current SSR contribution\0"
        "Temporal SSR contribution\0"
        "History weight\0"
        "History rejection reason\0"
        "Reprojected motion\0"
        "Depth agreement\0"
        "Normal agreement\0"
        "Neighborhood clamp amount\0"
        "Camera cut status\0"
        "History jitter status (hard off)\0"
        "Correction magnitude\0"
        "Reactive gate audit (R=transition G=radiance B=unsupported)\0"
        "Reactive history trust\0";
> = 0;

uniform float SSRTemporalDebugGain
<
    ui_label = "Temporal Debug Gain";
    ui_type = "drag";
    ui_min = 0.25; ui_max = 32.0; ui_step = 0.25;
> = 6.0;

// -----------------------------------------------------------------------------
// Half-resolution temporal storage retained from the validated v0.2 wrapper architecture.
// -----------------------------------------------------------------------------
texture SLSSRPreCaptureTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRPreCaptureSampler
{
    Texture = SLSSRPreCaptureTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRCurrentContributionTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRCurrentContributionSampler
{
    Texture = SLSSRCurrentContributionTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};
sampler SLSSRCurrentContributionPointSampler
{
    Texture = SLSSRCurrentContributionTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

texture SLSSRTemporalTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRTemporalSampler
{
    Texture = SLSSRTemporalTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRTemporalDebugTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRTemporalDebugSampler
{
    Texture = SLSSRTemporalDebugTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRTemporalReactiveDebugTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRTemporalReactiveDebugSampler
{
    Texture = SLSSRTemporalReactiveDebugTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRHistoryTex
{
    Width = BUFFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRHistorySampler
{
    Texture = SLSSRHistoryTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRHistoryGeomTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRHistoryGeomSampler
{
    Texture = SLSSRHistoryGeomTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

// -----------------------------------------------------------------------------
// Firestorm bridge helpers. These match the proven HybridGI temporal contract.
// -----------------------------------------------------------------------------
bool HasBridgeRegistration()
{
    return SLBridgeRegistrationValid > 0.5 &&
           SLBridgeViewport.z > 1.0 && SLBridgeViewport.w > 1.0 &&
           SLBridgeBufferInfo.x > 1.0 && SLBridgeBufferInfo.y > 1.0;
}

bool HasExactMatrices()
{
    float invSECB1