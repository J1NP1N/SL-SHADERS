// SL_BackgroundDepth_v0_1.fx
// Diagnostic for Firestorm-native camera-aligned static background depth.
// This effect does not modify SSR. It proves the second/background payload.

#include "ReShade.fxh"

uniform float4 SLBridgeViewport = float4(0.0, 0.0, 1.0, 1.0);
uniform float4 SLBridgeBufferInfo = float4(1.0, 1.0, 1.0, 1.0);
uniform float SLBridgeRegistrationValid = 0.0;

uniform float4 SLGIInvProjC0 = 0.0;
uniform float4 SLGIInvProjC1 = 0.0;
uniform float4 SLGIInvProjC2 = 0.0;
uniform float4 SLGIInvProjC3 = 0.0;
uniform float SLGIProjectionValid = 0.0;
uniform float SLProbeNativeValid = 0.0;

uniform float SLBackgroundDepthValid = 0.0;
uniform float2 SLBackgroundDepthSize = float2(0.0, 0.0);

uniform int SLBackgroundDepthDisplay
<
    ui_label = "Background Depth Display";
    ui_type = "combo";
    ui_items =
        "Passthrough\0"
        "Link / native payload\0"
        "Recovered-behind-primary overlay\0"
        "Recovered-behind-primary mask\0"
        "Primary linear depth\0"
        "Background linear depth\0"
        "Background minus primary\0";
> = 1;

uniform float SLBackgroundDepthGap
<
    ui_label = "Recovered Depth Gap";
    ui_tooltip = "Minimum view-space separation required before background depth counts as genuinely behind primary geometry.";
    ui_type = "drag";
    ui_min = 0.001; ui_max = 1.0; ui_step = 0.005;
> = 0.03;

uniform float SLBackgroundDepthDisplayRange
<
    ui_label = "Depth Display Range";
    ui_type = "drag";
    ui_min = 2.0; ui_max = 256.0; ui_step = 2.0;
> = 64.0;

texture SLPrimaryDepthTex : SL_DEPTH;
texture SLBackgroundDepthTex : SL_DEPTH_BACKGROUND;

sampler SLPrimaryDepthSampler
{
    Texture = SLPrimaryDepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLBackgroundDepthSampler
{
    Texture = SLBackgroundDepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

bool HasBridgeRegistration()
{
    return SLBridgeRegistrationValid > 0.5 &&
           SLBridgeViewport.z > 1.0 && SLBridgeViewport.w > 1.0 &&
           SLBridgeBufferInfo.x > 1.0 && SLBridgeBufferInfo.y > 1.0;
}

bool HasExactMatrices()
{
    float e =
        dot(abs(SLGIInvProjC0), 1.0) +
        dot(abs(SLGIInvProjC1), 1.0) +
        dot(abs(SLGIInvProjC2), 1.0) +
        dot(abs(SLGIInvProjC3), 1.0);

    return HasBridgeRegistration() &&
           SLGIProjectionValid > 0.5 &&
           SLProbeNativeValid > 0.5 &&
           e > 0.01;
}

float2 FirestormUV(float2 screenUV)
{
    if (!HasBridgeRegistration())
        return float2(-2.0, -2.0);

    float2 windowPxGL = float2(
        screenUV.x * SLBridgeBufferInfo.x,
        (1.0 - screenUV.y) * SLBridgeBufferInfo.y);

    return (windowPxGL - SLBridgeViewport.xy) / SLBridgeViewport.zw;
}

bool InsideFirestormWorld(float2 screenUV)
{
    float2 uv = FirestormUV(screenUV);
    return uv.x >= 0.0 && uv.x <= 1.0 &&
           uv.y >= 0.0 && uv.y <= 1.0;
}

float4 MulInvProj(float4 v)
{
    return SLGIInvProjC0 * v.x +
           SLGIInvProjC1 * v.y +
           SLGIInvProjC2 * v.z +
           SLGIInvProjC3 * v.w;
}

float LinearViewDepth(float2 screenUV, float rawDepth)
{
    float2 nativeUV = FirestormUV(screenUV);
    float4 p = MulInvProj(float4(
        nativeUV * 2.0 - 1.0,
        rawDepth * 2.0 - 1.0,
        1.0));

    float safeW = abs(p.w) > 1e-8 ? p.w : (p.w < 0.0 ? -1e-8 : 1e-8);
    float3 viewPos = p.xyz / safeW;
    return max(-viewPos.z, 0.0);
}

bool IsBackground(float rawDepth)
{
    return rawDepth >= 0.999999;
}

float DepthViz(float d)
{
    float range = max(SLBackgroundDepthDisplayRange, 1.0);
    return saturate(log2(1.0 + max(d, 0.0)) / log2(1.0 + range));
}

float4 BackgroundDepthDebugPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 scene = tex2D(ReShade::BackBuffer, uv);

    if (SLBackgroundDepthDisplay == 0)
        return scene;

    bool linkOK =
        SLBackgroundDepthValid > 0.5 &&
        HasExactMatrices() &&
        SLBackgroundDepthSize.x > 1.0 &&
        SLBackgroundDepthSize.y > 1.0;

    if (SLBackgroundDepthDisplay == 1)
    {
        return linkOK ? float4(0.0, 1.0, 1.0, 1.0)
                      : float4(1.0, 0.0, 0.0, 1.0);
    }

    if (!linkOK || !InsideFirestormWorld(uv))
        return float4(0.0, 0.0, 0.0, 1.0);

    float2 nativeUV = FirestormUV(uv);
    float primaryRaw = tex2D(SLPrimaryDepthSampler, nativeUV).r;
    float backgroundRaw = tex2D(SLBackgroundDepthSampler, nativeUV).r;

    bool primaryGeom = !IsBackground(primaryRaw);
    bool backgroundGeom = !IsBackground(backgroundRaw);

    float primaryDepth = primaryGeom ? LinearViewDepth(uv, primaryRaw) : 0.0;
    float backgroundDepth = backgroundGeom ? LinearViewDepth(uv, backgroundRaw) : 0.0;

    float delta = 0.0;
    if (primaryGeom && backgroundGeom)
        delta = max(backgroundDepth - primaryDepth, 0.0);

    float recovered = (primaryGeom && backgroundGeom)
        ? smoothstep(SLBackgroundDepthGap,
                     max(SLBackgroundDepthGap * 2.0, SLBackgroundDepthGap + 0.001),
                     delta)
        : 0.0;

    if (SLBackgroundDepthDisplay == 2)
        return float4(lerp(scene.rgb, float3(0.0, 1.0, 0.0), recovered * 0.85), 1.0);

    if (SLBackgroundDepthDisplay == 3)
        return float4(0.0, recovered, 0.0, 1.0);

    if (SLBackgroundDepthDisplay == 4)
        return float4(DepthViz(primaryDepth).xxx, 1.0);

    if (SLBackgroundDepthDisplay == 5)
        return float4(DepthViz(backgroundDepth).xxx, 1.0);

    float signedDelta = backgroundDepth - primaryDepth;
    float deltaViz = DepthViz(abs(signedDelta) * 8.0);

    if (signedDelta > 0.0)
        return float4(0.0, deltaViz, 0.0, 1.0);   // green = background farther

    return float4(deltaViz, 0.0, deltaViz, 1.0); // magenta = background nearer
}

technique SL_BackgroundDepth_v0_1
<
    ui_label = "SL Background Depth v0.1 - Native Static Layer";
    ui_tooltip = "Validates Firestorm's camera-aligned static background depth. This is infrastructure/debug only; it does not modify SSR yet.";
>
{
    pass Debug
    {
        VertexShader = PostProcessVS;
        PixelShader = BackgroundDepthDebugPS;
    }
}
