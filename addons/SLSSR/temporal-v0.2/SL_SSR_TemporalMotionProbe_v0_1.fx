// SL_SSR_TemporalMotionProbe_v0_1.fx
// Diagnostic only. Does not provide, synthesize, or fall back to motion data.
// It reports the exact uniforms consumed by SL_SSR_Temporal_v0_2.fx.

#include "ReShade.fxh"

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

uniform int SLSSRTemporalMotionProbeMode
<
    ui_label = "Motion Probe Display";
    ui_tooltip = "Raw mode: black=0, white=1. Packed mode: R=SLGIMotionValid, G=modelview-delta present, B=projection/bridge contract present. Status: green=motion ready, magenta=SLGIMotionValid is 0, orange=valid flag is set but delta matrix is missing.";
    ui_type = "combo";
    ui_items =
        "Raw SLGIMotionValid\0"
        "Modelview-delta present\0"
        "Packed motion contract\0"
        "Motion contract status\0";
> = 0;

float ModelviewDeltaEnergy()
{
    return
        dot(abs(SLGIInvModelviewDeltaC0), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC1), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC2), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC3), 1.0);
}

float ProjectionEnergy()
{
    return
        dot(abs(SLGIInvProjC0), 1.0) +
        dot(abs(SLGIInvProjC1), 1.0) +
        dot(abs(SLGIInvProjC2), 1.0) +
        dot(abs(SLGIInvProjC3), 1.0) +
        dot(abs(SLGIProjC0), 1.0) +
        dot(abs(SLGIProjC1), 1.0) +
        dot(abs(SLGIProjC2), 1.0) +
        dot(abs(SLGIProjC3), 1.0);
}

bool BridgeContractPresent()
{
    return
        SLBridgeRegistrationValid > 0.5 &&
        SLBridgeViewport.z > 1.0 &&
        SLBridgeViewport.w > 1.0 &&
        SLBridgeBufferInfo.x > 1.0 &&
        SLBridgeBufferInfo.y > 1.0 &&
        SLGIProjectionValid > 0.5 &&
        SLProbeNativeValid > 0.5 &&
        ProjectionEnergy() > 0.01;
}

float4 MotionProbePS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float rawMotionValid = saturate(SLGIMotionValid);
    float deltaPresent = ModelviewDeltaEnergy() > 0.01 ? 1.0 : 0.0;
    float bridgePresent = BridgeContractPresent() ? 1.0 : 0.0;

    if (SLSSRTemporalMotionProbeMode == 0)
        return float4(rawMotionValid.xxx, 1.0);

    if (SLSSRTemporalMotionProbeMode == 1)
        return float4(deltaPresent.xxx, 1.0);

    if (SLSSRTemporalMotionProbeMode == 2)
        return float4(rawMotionValid, deltaPresent, bridgePresent, 1.0);

    if (rawMotionValid <= 0.5)
        return float4(1.0, 0.0, 1.0, 1.0); // magenta: motion valid flag is zero

    if (deltaPresent <= 0.5)
        return float4(1.0, 0.5, 0.0, 1.0); // orange: flag set, delta missing

    if (bridgePresent <= 0.5)
        return float4(0.0, 0.5, 1.0, 1.0); // blue: motion exists, bridge/projection incomplete

    return float4(0.0, 0.8, 0.0, 1.0); // green: temporal motion contract present
}

technique SL_SSR_TemporalMotionProbe_v0_1
<
    ui_label = "TEMPORAL POST — Motion Bridge Probe";
    ui_tooltip = "Diagnostic only. Displays raw SLGIMotionValid and required camera-delta state. It never supplies fallback motion.";
>
{
    pass Probe
    {
        VertexShader = PostProcessVS;
        PixelShader = MotionProbePS;
    }
}
