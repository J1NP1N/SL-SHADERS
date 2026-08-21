// SL_SSR_Temporal_v0_2.fx
// Temporal accumulation/reprojection layer for SL SSR v0.49 AvatarThicknessTrace.
//
// IMPORTANT PIPELINE ORDER:
//   1. SL SSR Temporal v0.2 - Capture Before SSR
//   2. SL SSR v0.49 - Avatar Thickness Trace
//   3. SL SSR Temporal v0.2 - Resolve After SSR
//
// v0.49 tracing is not modified. This effect captures the exact presentation-space
// contribution produced by v0.49 and temporally filters only that contribution.
// It therefore remains separable from a future roughness-aware spatial resolve.

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

// Current v0.49 D0 and receiver normals. No native bridge changes are required.
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
    ui_tooltip = "Temporally reproject only the SSR contribution captured around v0.49.";
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
> = 0.20;

uniform float SSRTemporalRadianceRejectEnd
<
    ui_label = "Radiance Reject End";
    ui_tooltip = "Fully reject stale history by this normalized current/history difference.";
    ui_type = "drag";
    ui_min = 0.05; ui_max = 2.0; ui_step = 0.01;
> = 0.85;

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
    ui_label = "History Jitter (half-res px)";
    ui_tooltip = "Subpixel history sampling jitter. Keep small; neighborhood clamping remains authoritative.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.75; ui_step = 0.05;
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
        "Jitter phase\0"
        "Correction magnitude\0";
> = 0;

uniform float SSRTemporalDebugGain
<
    ui_label = "Temporal Debug Gain";
    ui_type = "drag";
    ui_min = 0.25; ui_max = 32.0; ui_step = 0.25;
> = 6.0;

// -----------------------------------------------------------------------------
// Half-resolution temporal storage. v0.49 already resolves SSR at half resolution.
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

texture SLSSRHistoryTex
{
    Width = BUFFER_WIDTH / 2;
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
    float invEnergy =
        dot(abs(SLGIInvProjC0), 1.0) + dot(abs(SLGIInvProjC1), 1.0) +
        dot(abs(SLGIInvProjC2), 1.0) + dot(abs(SLGIInvProjC3), 1.0);
    float projEnergy =
        dot(abs(SLGIProjC0), 1.0) + dot(abs(SLGIProjC1), 1.0) +
        dot(abs(SLGIProjC2), 1.0) + dot(abs(SLGIProjC3), 1.0);

    return HasBridgeRegistration() &&
           SLGIProjectionValid > 0.5 &&
           SLProbeNativeValid > 0.5 &&
           invEnergy > 0.01 && projEnergy > 0.01;
}

bool HasTemporalMotion()
{
    float e =
        dot(abs(SLGIInvModelviewDeltaC0), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC1), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC2), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC3), 1.0);

    return SLGIMotionValid > 0.5 && e > 0.01;
}

float2 FirestormUV(float2 screenUV)
{
    if (!HasBridgeRegistration())
        return float2(-2.0, -2.0);

    float2 windowPxGL =
        float2(screenUV.x * SLBridgeBufferInfo.x,
               (1.0 - screenUV.y) * SLBridgeBufferInfo.y);

    return (windowPxGL - SLBridgeViewport.xy) / SLBridgeViewport.zw;
}

float2 ScreenUVFromFirestormUV(float2 nativeUV)
{
    float2 windowPxGL = SLBridgeViewport.xy + nativeUV * SLBridgeViewport.zw;
    return float2(
        windowPxGL.x / SLBridgeBufferInfo.x,
        1.0 - windowPxGL.y / SLBridgeBufferInfo.y);
}

bool InsideFirestormWorld(float2 screenUV)
{
    float2 uv = FirestormUV(screenUV);
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

bool InsideTemporalEdge(float2 uv)
{
    float2 margin = float2(
        SSRTemporalEdgeMarginPx / max((float)BUFFER_WIDTH, 1.0),
        SSRTemporalEdgeMarginPx / max((float)BUFFER_HEIGHT, 1.0));

    return uv.x > margin.x && uv.x < 1.0 - margin.x &&
           uv.y > margin.y && uv.y < 1.0 - margin.y &&
           InsideFirestormWorld(uv);
}

float4 MulInvProj(float4 v)
{
    return SLGIInvProjC0 * v.x +
           SLGIInvProjC1 * v.y +
           SLGIInvProjC2 * v.z +
           SLGIInvProjC3 * v.w;
}

float4 MulProj(float4 v)
{
    return SLGIProjC0 * v.x +
           SLGIProjC1 * v.y +
           SLGIProjC2 * v.z +
           SLGIProjC3 * v.w;
}

float4 MulInvModelviewDelta(float4 v)
{
    return SLGIInvModelviewDeltaC0 * v.x +
           SLGIInvModelviewDeltaC1 * v.y +
           SLGIInvModelviewDeltaC2 * v.z +
           SLGIInvModelviewDeltaC3 * v.w;
}

float GetRawDepth(float2 screenUV)
{
    return tex2D(SLPrimaryDepthSampler, FirestormUV(screenUV)).r;
}

float4 GetRawNormalData(float2 screenUV)
{
    return tex2D(SLNativeNormalsSampler, FirestormUV(screenUV));
}

bool IsBackgroundDepth(float d)
{
    return d >= 0.999999;
}

float3 DecodeFirestormNormalRaw(float4 encodedNormal)
{
    float2 fenc = encodedNormal.xy * 4.0 - 2.0;
    float f = dot(fenc, fenc);
    float g = sqrt(saturate(1.0 - f * 0.25));

    float3 n;
    n.xy = fenc * g;
    n.z = 1.0 - f * 0.5;

    float len2 = dot(n, n);
    return len2 > 1e-8 ? n * rsqrt(len2) : float3(0.0, 0.0, 1.0);
}

float3 GetTransportNormal(float2 uv)
{
    return DecodeFirestormNormalRaw(GetRawNormalData(uv));
}

float3 ReconstructViewPosition(float2 screenUV, float rawDepth)
{
    float2 nativeUV = FirestormUV(screenUV);
    float4 p = MulInvProj(float4(
        nativeUV * 2.0 - 1.0,
        rawDepth * 2.0 - 1.0,
        1.0));

    float safeW = abs(p.w) > 1e-8 ? p.w : (p.w < 0.0 ? -1e-8 : 1e-8);
    return p.xyz / safeW;
}

bool ProjectViewPosition(float3 viewPos, out float2 screenUV)
{
    float4 clip = MulProj(float4(viewPos, 1.0));
    if (abs(clip.w) <= 1e-8)
    {
        screenUV = 0.0;
        return false;
    }

    float2 nativeUV = (clip.xy / clip.w) * 0.5 + 0.5;
    if (nativeUV.x <= 0.0 || nativeUV.x >= 1.0 ||
        nativeUV.y <= 0.0 || nativeUV.y >= 1.0)
    {
        screenUV = 0.0;
        return false;
    }

    screenUV = ScreenUVFromFirestormUV(nativeUV);
    return InsideFirestormWorld(screenUV);
}

float CameraDeltaMetric()
{
    float4 e0 = abs(SLGIInvModelviewDeltaC0 - float4(1.0, 0.0, 0.0, 0.0));
    float4 e1 = abs(SLGIInvModelviewDeltaC1 - float4(0.0, 1.0, 0.0, 0.0));
    float4 e2 = abs(SLGIInvModelviewDeltaC2 - float4(0.0, 0.0, 1.0, 0.0));
    float4 e3 = abs(SLGIInvModelviewDeltaC3 - float4(0.0, 0.0, 0.0, 1.0));

    float m0 = max(max(e0.x, e0.y), max(e0.z, e0.w));
    float m1 = max(max(e1.x, e1.y), max(e1.z, e1.w));
    float m2 = max(max(e2.x, e2.y), max(e2.z, e2.w));
    float m3 = max(max(e3.x, e3.y), max(e3.z, e3.w));

    return max(max(m0, m1), max(m2, m3));
}

float2 TemporalJitter(int frameIndex)
{
    int p = frameIndex % 8;
    if (p == 0) return float2(-0.375, -0.125);
    if (p == 1) return float2( 0.125,  0.375);
    if (p == 2) return float2( 0.375, -0.375);
    if (p == 3) return float2(-0.125,  0.125);
    if (p == 4) return float2(-0.250,  0.250);
    if (p == 5) return float2( 0.250, -0.250);
    if (p == 6) return float2( 0.000,  0.000);
    return float2(0.375, 0.375);
}

// -----------------------------------------------------------------------------
// Current SSR contribution capture.
// -----------------------------------------------------------------------------
float ContributionEnergy(float3 delta)
{
    float3 a = abs(delta);
    return max(a.r, max(a.g, a.b));
}

float4 CaptureBeforeSSRPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return float4(tex2D(ReShade::BackBuffer, uv).rgb, 1.0);
}

float4 CurrentSSRContributionPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 before = tex2D(SLSSRPreCaptureSampler, uv).rgb;
    float3 after = tex2D(ReShade::BackBuffer, uv).rgb;
    float3 delta = after - before;
    return float4(delta, ContributionEnergy(delta));
}

// -----------------------------------------------------------------------------
// History geometry and reprojection.
// Rejection codes:
//   0 accepted/no history needed
//   1 reset/disabled/first frames
//   2 bridge or motion unavailable
//   3 camera cut / excessive camera delta
//   4 screen edge / reprojection / invalid receiver
//   5 depth mismatch / disocclusion
//   6 normal mismatch
//   7 invalid hit transition
//   8 radiance/clamp reactive rejection
// -----------------------------------------------------------------------------
float3 EncodeHistoryNormal(float3 n)
{
    return saturate(n * 0.5 + 0.5);
}

float3 DecodeHistoryNormal(float3 e)
{
    float3 n = e * 2.0 - 1.0;
    float l = dot(n, n);
    return l > 1e-8 ? n * rsqrt(l) : float3(0.0, 0.0, 1.0);
}

float4 CurrentHistoryGeometry(float2 uv)
{
    if (!HasBridgeRegistration() || !HasExactMatrices() || !InsideFirestormWorld(uv))
        return 0.0;

    float rawDepth = GetRawDepth(uv);
    if (IsBackgroundDepth(rawDepth))
        return 0.0;

    float3 p = ReconstructViewPosition(uv, rawDepth);
    float linearDepth = max(-p.z, 0.0);
    if (linearDepth <= 1e-5)
        return 0.0;

    return float4(EncodeHistoryNormal(GetTransportNormal(uv)), linearDepth);
}

float EvaluateHistoryGeometry(
    float2 uv,
    out float2 previousUV,
    out float depthAgreement,
    out float normalAgreement,
    out float motionPixels,
    out float rejectCode)
{
    previousUV = uv;
    depthAgreement = 0.0;
    normalAgreement = 0.0;
    motionPixels = 0.0;
    rejectCode = 0.0;

    if (!HasBridgeRegistration() || !HasExactMatrices() || !HasTemporalMotion())
    {
        rejectCode = 2.0;
        return 0.0;
    }

    if (!InsideTemporalEdge(uv))
    {
        rejectCode = 4.0;
        return 0.0;
    }

    float rawDepth = GetRawDepth(uv);
    if (IsBackgroundDepth(rawDepth))
    {
        rejectCode = 4.0;
        return 0.0;
    }

    float3 currentPos = ReconstructViewPosition(uv, rawDepth);
    float4 pp4 = MulInvModelviewDelta(float4(currentPos, 1.0));
    float sw = abs(pp4.w) > 1e-8 ? pp4.w : 1.0;
    float3 previousPos = pp4.xyz / sw;

    if (!ProjectViewPosition(previousPos, previousUV) || !InsideTemporalEdge(previousUV))
    {
        rejectCode = 4.0;
        return 0.0;
    }

    motionPixels = length(
        (previousUV - uv) *
        float2((float)BUFFER_WIDTH, (float)BUFFER_HEIGHT));

    float4 hg = tex2D(SLSSRHistoryGeomSampler, previousUV);
    float historyDepth = hg.a;
    if (historyDepth <= 1e-5)
    {
        rejectCode = 5.0;
        return 0.0;
    }

    float predictedDepth = max(-previousPos.z, 0.0);
    float depthError = abs(historyDepth - predictedDepth);
    float depthTolerance = max(
        SSRTemporalDepthTolerance,
        predictedDepth * 0.0035);

    depthAgreement =
        1.0 - smoothstep(depthTolerance, depthTolerance * 2.0, depthError);

    if (depthAgreement <= 0.02)
    {
        rejectCode = 5.0;
        return 0.0;
    }

    float3 previousNormal =
        MulInvModelviewDelta(float4(GetTransportNormal(uv), 0.0)).xyz;
    float nl = dot(previousNormal, previousNormal);
    if (nl <= 1e-8)
    {
        rejectCode = 6.0;
        return 0.0;
    }
    previousNormal *= rsqrt(nl);

    float nd = saturate(dot(previousNormal, DecodeHistoryNormal(hg.rgb)));
    float n1 = min(SSRTemporalNormalThreshold + 0.15, 0.999);
    normalAgreement = smoothstep(SSRTemporalNormalThreshold, n1, nd);

    if (normalAgreement <= 0.02)
    {
        rejectCode = 6.0;
        return 0.0;
    }

    return saturate(depthAgreement * normalAgreement);
}

void ExpandEnvelope(float3 s, inout float3 lo, inout float3 hi)
{
    lo = min(lo, s);
    hi = max(hi, s);
}

void CurrentNeighborhoodEnvelope(float2 uv, out float3 lo, out float3 hi)
{
    float2 px = float2(
        2.0 / (float)BUFFER_WIDTH,
        2.0 / (float)BUFFER_HEIGHT);

    float3 c = tex2D(SLSSRCurrentContributionSampler, uv).rgb;
    lo = c;
    hi = c;

    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2( px.x, 0.0)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(-px.x, 0.0)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(0.0,  px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(0.0, -px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2( px.x,  px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(-px.x,  px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2( px.x, -px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(-px.x, -px.y)).rgb, lo, hi);

    float3 span = hi - lo;
    float peak = max(
        max(max(abs(lo.r), abs(lo.g)), abs(lo.b)),
        max(max(abs(hi.r), abs(hi.g)), abs(hi.b)));

    float floorPad = max(0.0010, peak * 0.05);
    float3 pad = max(span * SSRTemporalClampExpansion, floorPad.xxx);

    lo -= pad;
    hi += pad;
}

struct TemporalMRT
{
    float4 color : SV_Target0;
    float4 debug : SV_Target1;
};

TemporalMRT TemporalResolvePS(float4 pos : SV_Position, float2 uv : TEXCOORD)
{
    TemporalMRT o;

    float4 current = tex2D(SLSSRCurrentContributionSampler, uv);
    float3 resolved = current.rgb;

    float historyWeight = 0.0;
    float rejectCode = 0.0;
    float clampAmount = 0.0;
    float motionPixels = 0.0;
    float depthAgreement = 0.0;
    float normalAgreement = 0.0;

    bool forceReset =
        SSRTemporalEnable <= 0 ||
        SSRTemporalResetHistory > 0 ||
        SLSSRTemporalFrameIndex < 2;

    if (forceReset)
    {
        rejectCode = 1.0;
    }
    else if (!HasBridgeRegistration() || !HasExactMatrices() || !HasTemporalMotion())
    {
        rejectCode = 2.0;
    }
    else if (CameraDeltaMetric() > SSRTemporalCameraCutThreshold)
    {
        rejectCode = 3.0;
    }
    else
    {
        float2 previousUV;
        float geometryValidity = EvaluateHistoryGeometry(
            uv,
            previousUV,
            depthAgreement,
            normalAgreement,
            motionPixels,
            rejectCode);

        if (geometryValidity > 1e-4)
        {
            float4 historyCenter = tex2D(SLSSRHistorySampler, previousUV);

            bool currentValid =
                current.a > max(SSRTemporalContributionEpsilon, 1e-6);
            bool historyValid =
                historyCenter.a > max(SSRTemporalContributionEpsilon, 1e-6);

            // Do not resurrect a prior reflected hit after it disappears, and do
            // not import a no-hit history into a newly valid reflection.
            if (currentValid != historyValid)
            {
                rejectCode = 7.0;
            }
            else if (currentValid)
            {
                float2 halfResPx = float2(
                    2.0 / (float)BUFFER_WIDTH,
                    2.0 / (float)BUFFER_HEIGHT);

                float2 historyUV =
                    previousUV +
                    TemporalJitter(SLSSRTemporalFrameIndex) *
                    halfResPx *
                    SSRTemporalJitterPixels;

                if (!InsideTemporalEdge(historyUV))
                {
                    rejectCode = 4.0;
                }
                else
                {
                    float4 history = tex2D(SLSSRHistorySampler, historyUV);
                    float3 historyBefore = history.rgb;

                    float3 lo, hi;
                    CurrentNeighborhoodEnvelope(uv, lo, hi);
                    history.rgb = clamp(history.rgb, lo, hi);

                    clampAmount =
                        length(historyBefore - history.rgb) /
                        max(length(historyBefore), 0.01);

                    float radianceDifference =
                        length(historyBefore - current.rgb) /
                        max(length(historyBefore) + length(current.rgb), 0.02);

                    float rr0 = min(
                        SSRTemporalRadianceRejectStart,
                        SSRTemporalRadianceRejectEnd - 1e-3);
                    float rr1 = max(
                        SSRTemporalRadianceRejectEnd,
                        rr0 + 1e-3);

                    float radianceTrust =
                        1.0 - smoothstep(rr0, rr1, radianceDifference);

                    float clampTrust =
                        1.0 - smoothstep(0.08, 0.75, clampAmount);

                    float motionTrust =
                        1.0 - smoothstep(
                            SSRTemporalMotionStartPx,
                            max(SSRTemporalMotionEndPx,
                                SSRTemporalMotionStartPx + 0.01),
                            motionPixels);

                    if (radianceTrust <= 0.02 || clampTrust <= 0.02)
                    {
                        rejectCode = 8.0;
                    }
                    else
                    {
                        historyWeight = saturate(
                            SSRTemporalHistoryWeight *
                            geometryValidity *
                            radianceTrust *
                            clampTrust *
                            motionTrust);

                        resolved = lerp(current.rgb, history.rgb, historyWeight);
                    }
                }
            }
        }
    }

    o.color = float4(resolved, current.a);
    o.debug = float4(
        historyWeight,
        saturate(rejectCode / 8.0),
        saturate(clampAmount),
        saturate(motionPixels / 32.0));

    return o;
}

float4 CopyTemporalHistoryPS(
    float4 pos : SV_Position,
    float2 uv : TEXCOORD) : SV_Target
{
    float4 temporal = tex2D(SLSSRTemporalSampler, uv);
    float4 current = tex2D(SLSSRCurrentContributionSampler, uv);
    return float4(temporal.rgb, current.a);
}

float4 StoreHistoryGeometryPS(
    float4 pos : SV_Position,
    float2 uv : TEXCOORD) : SV_Target
{
    return CurrentHistoryGeometry(uv);
}

float3 RejectionColor(float code)
{
    if (code < 0.5) return float3(0.0, 0.65, 0.0);
    if (code < 1.5) return float3(0.25, 0.25, 0.25);
    if (code < 2.5) return float3(1.0, 0.0, 1.0);
    if (code < 3.5) return float3(1.0, 0.5, 0.0);
    if (code < 4.5) return float3(0.0, 0.5, 1.0);
    if (code < 5.5) return float3(1.0, 0.0, 0.0);
    if (code < 6.5) return float3(0.9, 0.9, 0.0);
    if (code < 7.5) return float3(0.0, 1.0, 1.0);
    return float3(1.0, 0.25, 0.25);
}

float4 TemporalCompositeCorrectionPS(
    float4 pos : SV_Position,
    float2 uv : TEXCOORD) : SV_Target
{
    float4 color = tex2D(ReShade::BackBuffer, uv);

    float4 current = tex2D(SLSSRCurrentContributionSampler, uv);
    float4 temporal = tex2D(SLSSRTemporalSampler, uv);
    float4 debug = tex2D(SLSSRTemporalDebugSampler, uv);

    if (SSRTemporalDisplayMode == 1)
        return float4(saturate(abs(current.rgb) * SSRTemporalDebugGain), 1.0);

    if (SSRTemporalDisplayMode == 2)
        return float4(saturate(abs(temporal.rgb) * SSRTemporalDebugGain), 1.0);

    if (SSRTemporalDisplayMode == 3)
        return float4(debug.r.xxx, 1.0);

    if (SSRTemporalDisplayMode == 4)
    {
        float code = floor(debug.g * 8.0 + 0.5);
        return float4(RejectionColor(code), 1.0);
    }

    if (SSRTemporalDisplayMode == 5)
        return float4(debug.a.xxx, 1.0);

    if (SSRTemporalDisplayMode == 6 ||
        SSRTemporalDisplayMode == 7)
    {
        float2 previousUV;
        float depthAgreement;
        float normalAgreement;
        float motionPixels;
        float rejectCode;

        EvaluateHistoryGeometry(
            uv,
            previousUV,
            depthAgreement,
            normalAgreement,
            motionPixels,
            rejectCode);

        float v =
            SSRTemporalDisplayMode == 6 ?
            depthAgreement : normalAgreement;

        return float4(v.xxx, 1.0);
    }

    if (SSRTemporalDisplayMode == 8)
        return float4(debug.b.xxx, 1.0);

    if (SSRTemporalDisplayMode == 9)
    {
        float cut =
            HasTemporalMotion() &&
            CameraDeltaMetric() <= SSRTemporalCameraCutThreshold ?
            0.0 : 1.0;

        return float4(cut, 1.0 - cut, 0.0, 1.0);
    }

    if (SSRTemporalDisplayMode == 10)
    {
        float2 j = TemporalJitter(SLSSRTemporalFrameIndex) + 0.5;
        return float4(j, 0.0, 1.0);
    }

    float3 correction = temporal.rgb - current.rgb;

    if (SSRTemporalDisplayMode == 11)
        return float4(saturate(abs(correction) * SSRTemporalDebugGain), 1.0);

    if (SSRTemporalEnable <= 0)
        return color;

    color.rgb = max(color.rgb + correction, 0.0);
    return color;
}

// -----------------------------------------------------------------------------
// Technique order is part of the contract. Keep only v0.49 between these two.
// -----------------------------------------------------------------------------
technique SL_SSR_Temporal_v0_2_Capture
<
    ui_label = "SL SSR Temporal v0.2 - Capture Before SSR";
    ui_tooltip = "Place immediately BEFORE SL SSR v0.49. Captures the pre-SSR backbuffer at half resolution.";
>
{
    pass CaptureBeforeSSR
    {
        VertexShader = PostProcessVS;
        PixelShader = CaptureBeforeSSRPS;
        RenderTarget = SLSSRPreCaptureTex;
    }
}

technique SL_SSR_Temporal_v0_2_Resolve
<
    ui_label = "SL SSR Temporal v0.2 - Resolve After SSR";
    ui_tooltip = "Place immediately AFTER SL SSR v0.49. Reprojects and accumulates only v0.49's captured presentation-space SSR contribution.";
>
{
    pass CaptureCurrentContribution
    {
        VertexShader = PostProcessVS;
        PixelShader = CurrentSSRContributionPS;
        RenderTarget = SLSSRCurrentContributionTex;
    }

    pass TemporalResolve
    {
        VertexShader = PostProcessVS;
        PixelShader = TemporalResolvePS;
        RenderTarget0 = SLSSRTemporalTex;
        RenderTarget1 = SLSSRTemporalDebugTex;
    }

    pass CopyTemporalHistory
    {
        VertexShader = PostProcessVS;
        PixelShader = CopyTemporalHistoryPS;
        RenderTarget = SLSSRHistoryTex;
    }

    pass StoreHistoryGeometry
    {
        VertexShader = PostProcessVS;
        PixelShader = StoreHistoryGeometryPS;
        RenderTarget = SLSSRHistoryGeomTex;
    }

    pass CompositeCorrection
    {
        VertexShader = PostProcessVS;
        PixelShader = TemporalCompositeCorrectionPS;
    }
}
