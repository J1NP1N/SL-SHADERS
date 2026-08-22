// SL_NativeAlphaProof_v0_1.fx
// Raw proof only. Validate Firestorm -> bridge -> ReShade before enabling GTAO.

#include "ReShade.fxh"

uniform float4 SLBridgeViewport = float4(0.0, 0.0, 1.0, 1.0);
uniform float4 SLBridgeBufferInfo = float4(1.0, 1.0, 1.0, 1.0);
uniform float SLBridgeRegistrationValid = 0.0;

uniform float SLAlphaMaterialValid = 0.0;
uniform float SLAlphaDepthNativeValid = 0.0;
uniform float SLAlphaCoverageValid = 0.0;
uniform float2 SLAlphaMaterialSize = 0.0;
uniform float2 SLAlphaDepthNativeSize = 0.0;
uniform float2 SLAlphaCoverageSize = 0.0;

uniform int SLAlphaProofMode
<
    ui_label = "NATIVE ALPHA — Diagnostic";
    ui_type = "combo";
    ui_items =
        "Material classification\0"
        "Native alpha depth (raw)\0"
        "Coverage\0"
        "Material / Depth / Coverage triptych\0"
        "Registration/status\0";
> = 3;

texture SLAlphaMaterialTex : SL_ALPHA_MATERIAL;
texture SLAlphaDepthTex : SL_DEPTH_ALPHA_NATIVE;
texture SLAlphaCoverageTex : SL_ALPHA_COVERAGE;

sampler SLAlphaMaterialSampler
{
    Texture = SLAlphaMaterialTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLAlphaDepthSampler
{
    Texture = SLAlphaDepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLAlphaCoverageSampler
{
    Texture = SLAlphaCoverageTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

float2 SLAlphaNativeUV(float2 screenUV)
{
    if (SLBridgeRegistrationValid <= 0.5)
        return screenUV;

    float2 windowPxGL = float2(
        screenUV.x * SLBridgeBufferInfo.x,
        (1.0 - screenUV.y) * SLBridgeBufferInfo.y);
    return (windowPxGL - SLBridgeViewport.xy) / max(SLBridgeViewport.zw, 1.0.xx);
}

bool SLAlphaInside(float2 uv)
{
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

float3 SLAlphaStatus()
{
    return float3(
        SLAlphaMaterialValid > 0.5 ? 1.0 : 0.0,
        SLAlphaDepthNativeValid > 0.5 ? 1.0 : 0.0,
        SLAlphaCoverageValid > 0.5 ? 1.0 : 0.0);
}

float4 SLAlphaProofPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    if (SLAlphaProofMode == 4)
        return float4(SLAlphaStatus(), 1.0);

    float2 nuv = SLAlphaNativeUV(uv);
    if (!SLAlphaInside(nuv))
        return float4(0.05, 0.0, 0.05, 1.0);

    float material = saturate(tex2D(SLAlphaMaterialSampler, nuv).r);
    float rawDepth = saturate(tex2D(SLAlphaDepthSampler, nuv).r);
    float coverage = saturate(tex2D(SLAlphaCoverageSampler, nuv).r);

    if (SLAlphaProofMode == 0)
        return float4(material.xxx, 1.0);
    if (SLAlphaProofMode == 1)
        return float4(rawDepth.xxx, 1.0);
    if (SLAlphaProofMode == 2)
        return float4(coverage.xxx, 1.0);

    float panelX = uv.x * 3.0;
    float localX = frac(panelX);
    float2 panelScreenUV = float2(localX, uv.y);
    float2 panelNUV = SLAlphaNativeUV(panelScreenUV);
    if (!SLAlphaInside(panelNUV))
        return float4(0.05, 0.0, 0.05, 1.0);

    if (panelX < 1.0)
        return float4(tex2D(SLAlphaMaterialSampler, panelNUV).rrr, 1.0);
    if (panelX < 2.0)
        return float4(tex2D(SLAlphaDepthSampler, panelNUV).rrr, 1.0);
    return float4(tex2D(SLAlphaCoverageSampler, panelNUV).rrr, 1.0);
}

technique SLNativeAlphaProofV01
<
    ui_label = "NATIVE ALPHA — v0.1 Proof";
    ui_tooltip = "Raw SL_ALPHA_MATERIAL / SL_DEPTH_ALPHA_NATIVE / SL_ALPHA_COVERAGE proof. Disable GTAO while validating.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = SLAlphaProofPS;
    }
}
