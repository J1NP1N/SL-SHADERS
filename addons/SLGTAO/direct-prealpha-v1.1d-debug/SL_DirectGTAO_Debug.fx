// SL_DirectGTAO_Debug.fx
// Validation-only viewer for the direct pre-alpha GTAO add-on outputs.
// It never computes or applies GTAO. Mode 0 is a pure backbuffer passthrough.

#include "ReShade.fxh"

uniform float4 SLBridgeViewport = float4(0.0, 0.0, 1.0, 1.0);
uniform float4 SLBridgeBufferInfo = float4(1.0, 1.0, 1.0, 1.0);
uniform float SLBridgeRegistrationValid = 0.0;

uniform int SLDirectGTAODebugView
<
    ui_label = "DIRECT GTAO - Debug View";
    ui_type = "combo";
    ui_items =
        "Final frame (passthrough)\0"
        "Raw AO\0"
        "Denoised AO\0"
        "D0 depth\0"
        "N0 normals\0";
> = 1;

uniform float SLDirectGTAODepthContrast
<
    ui_label = "DIRECT GTAO - Depth Contrast";
    ui_type = "drag";
    ui_min = 1.0; ui_max = 512.0; ui_step = 1.0;
> = 64.0;

texture SLGTAORawTex : SL_GTAO_RAW;
texture SLGTAODenoisedTex : SL_GTAO_DENOISED;
texture SLGTAOD0Tex : SL_GTAO_D0;
texture SLGTAON0Tex : SL_GTAO_N0;

sampler SLGTAORawSampler
{
    Texture = SLGTAORawTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLGTAODenoisedSampler
{
    Texture = SLGTAODenoisedTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLGTAOD0Sampler
{
    Texture = SLGTAOD0Tex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLGTAON0Sampler
{
    Texture = SLGTAON0Tex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

float2 SLDirectGTAONativeUV(float2 screenUV)
{
    float2 windowPxGL = float2(
        screenUV.x * SLBridgeBufferInfo.x,
        (1.0 - screenUV.y) * SLBridgeBufferInfo.y);
    return (windowPxGL - SLBridgeViewport.xy) / SLBridgeViewport.zw;
}

bool SLDirectGTAOInside(float2 uv)
{
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

float3 SLDirectGTAODecodeN0(float4 encodedNormal)
{
    float2 fenc = encodedNormal.xy * 4.0 - 2.0;
    float f = dot(fenc, fenc);
    float g = sqrt(max(1.0 - f * 0.25, 0.0));
    float3 n;
    n.xy = fenc * g;
    n.z = 1.0 - f * 0.5;
    return normalize(n);
}

float4 SLDirectGTAODebugPS(float4 pos : SV_Position, float2 screenUV : TEXCOORD) : SV_Target
{
    float4 current = tex2D(ReShade::BackBuffer, screenUV);
    if (SLDirectGTAODebugView == 0 || SLBridgeRegistrationValid < 0.5)
        return current;

    float2 uv = SLDirectGTAONativeUV(screenUV);
    if (!SLDirectGTAOInside(uv))
        return current;

    if (SLDirectGTAODebugView == 1)
    {
        float ao = saturate(tex2D(SLGTAORawSampler, uv).r);
        return float4(ao.xxx, 1.0);
    }

    if (SLDirectGTAODebugView == 2)
    {
        float ao = saturate(tex2D(SLGTAODenoisedSampler, uv).r);
        return float4(ao.xxx, 1.0);
    }

    if (SLDirectGTAODebugView == 3)
    {
        float rawDepth = saturate(tex2D(SLGTAOD0Sampler, uv).r);
        float depthView = saturate((1.0 - rawDepth) * SLDirectGTAODepthContrast);
        return float4(depthView.xxx, 1.0);
    }

    float3 n = SLDirectGTAODecodeN0(tex2D(SLGTAON0Sampler, uv));
    return float4(n * 0.5 + 0.5, 1.0);
}

technique SL_DirectGTAO_Debug
<
    ui_label = "DIRECT GTAO - Buffer Debug";
    ui_tooltip = "Validation only. Displays addon-published D0/N0/raw/denoised buffers; mode 0 is passthrough.";
>
{
    pass Debug
    {
        VertexShader = PostProcessVS;
        PixelShader = SLDirectGTAODebugPS;
    }
}
