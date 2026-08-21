// SL_SSR_AvatarReceiver_v0_2_QualificationDiagnostics.fx
// Diagnostic-only follow-up for avatar SSR receiver qualification.
//
// Run this alongside the proven receiver build:
//   CORE v0.49 -> AVATAR RECEIVER v0.1 -> ONE v0.2 diagnostic technique.
//
// This file does not trace SSR, composite SSR, modify native plumbing, or touch
// the CORE [D0,DavatarBack] avatar-as-hit/source interval.
//
// Stage definitions:
//   Geometry candidate = valid visible D0 + valid DavatarBack +
//                        backDepth > frontDepth + ARDiagAvatarMinThickness.
//                        NO material/specular/roughness/alpha gating.
//   Material candidate = geometry candidate + the same legacy/PBR reflectivity
//                        eligibility used by receiver v0.1. Alpha is excluded.
//   Rejection reason   = first failing gate, with alpha tested after material.
//
// Rejection colors:
//   red     = missing D0
//   magenta = missing DavatarBack
//   yellow  = invalid/thin [D0,DavatarBack]
//   cyan    = legacy reflectivity rejection
//   blue    = PBR roughness/reflectivity rejection
//   orange  = alpha-mask rejection
//   green   = fully eligible
//   black   = diagnostic inputs unavailable / outside registered viewport

#include "ReShade.fxh"

#define ARD_REJECT_NONE 0
#define ARD_REJECT_MISSING_D0 1
#define ARD_REJECT_MISSING_AVATAR_BACK 2
#define ARD_REJECT_THIN_INTERVAL 3
#define ARD_REJECT_LEGACY_REFLECTIVITY 4
#define ARD_REJECT_PBR_REFLECTIVITY 5
#define ARD_REJECT_ALPHA_MASK 6

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
uniform float SLGBufferSpecularValid = 0.0;

uniform float ARDiagAvatarMinThickness
<
    ui_label = "AVATAR RECEIVER — Diagnostic min thickness";
    ui_tooltip = "Match AVATAR RECEIVER v0.1 Avatar Min Thickness when testing. Default is identical.";
    ui_type = "drag";
    ui_min = 0.0001; ui_max = 0.25; ui_step = 0.001;
> = 0.002;

uniform float ARDiagLegacySpecularScale
<
    ui_label = "AVATAR RECEIVER — Diagnostic legacy specular scale";
    ui_tooltip = "Match v0.1 Legacy Specular Scale. Default is identical.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.05;
> = 1.0;

uniform float ARDiagLegacyEnvScale
<
    ui_label = "AVATAR RECEIVER — Diagnostic legacy environment scale";
    ui_tooltip = "Match v0.1 Legacy Environment Scale. Default is identical.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.05;
> = 1.0;

uniform float ARDiagLegacyFallbackThreshold
<
    ui_label = "AVATAR RECEIVER — Diagnostic legacy fallback threshold";
    ui_tooltip = "Match v0.1 Legacy Fallback Threshold. Default is identical.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.10; ui_step = 0.001;
> = 0.005;

uniform float ARDiagLegacyDielectricFallback
<
    ui_label = "AVATAR RECEIVER — Diagnostic legacy dielectric fallback";
    ui_tooltip = "Match v0.1 Legacy Dielectric Fallback. Default is identical.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.25; ui_step = 0.005;
> = 0.040;

uniform float ARDiagLegacyMinReflectivity
<
    ui_label = "AVATAR RECEIVER — Diagnostic legacy min reflectivity";
    ui_tooltip = "Match v0.1 Legacy Min Reflectivity. Default is identical.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.25; ui_step = 0.001;
> = 0.005;

uniform float ARDiagPBRStrength
<
    ui_label = "AVATAR RECEIVER — Diagnostic PBR strength";
    ui_tooltip = "Match v0.1 PBR Strength. Default is identical.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.65;

uniform float ARDiagPBRRoughnessPower
<
    ui_label = "AVATAR RECEIVER — Diagnostic PBR roughness power";
    ui_tooltip = "Match v0.1 PBR Roughness Power. Default is identical.";
    ui_type = "drag";
    ui_min = 0.25; ui_max = 4.0; ui_step = 0.05;
> = 1.25;

uniform float ARDiagAlphaReceiverProtection
<
    ui_label = "AVATAR RECEIVER — Diagnostic alpha protection";
    ui_tooltip = "Match v0.1 Alpha Receiver Protection. Default is identical.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

texture SLNativeNormalsTex : SL_NORMALS;
texture SLNativeDepthTex : SL_DEPTH_PRIMARY_NATIVE;
texture SLAvatarBackDepthTex : SL_DEPTH_AVATAR_BACK;
texture SLAlphaMaskTex : SL_ALPHA_MASK;
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
sampler SLAvatarBackDepthSampler
{
    Texture = SLAvatarBackDepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};
sampler SLAlphaMaskSampler
{
    Texture = SLAlphaMaskTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};
sampler SLGBufferSpecularSampler
{
    Texture = SLGBufferSpecularTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

bool ARDHasBridgeRegistration()
{
    return SLBridgeRegistrationValid > 0.5 &&
           SLBridgeViewport.z > 1.0 && SLBridgeViewport.w > 1.0 &&
           SLBridgeBufferInfo.x > 1.0 && SLBridgeBufferInfo.y > 1.0;
}

bool ARDHasExactMatrices()
{
    float invEnergy = dot(abs(SLGIInvProjC0), 1.0) + dot(abs(SLGIInvProjC1), 1.0) +
                      dot(abs(SLGIInvProjC2), 1.0) + dot(abs(SLGIInvProjC3), 1.0);
    float projEnergy = dot(abs(SLGIProjC0), 1.0) + dot(abs(SLGIProjC1), 1.0) +
                       dot(abs(SLGIProjC2), 1.0) + dot(abs(SLGIProjC3), 1.0);
    return ARDHasBridgeRegistration() && SLGIProjectionValid > 0.5 && SLProbeNativeValid > 0.5 &&
           invEnergy > 0.01 && projEnergy > 0.01;
}

float2 ARDFirestormUV(float2 screenUV)
{
    if (!ARDHasBridgeRegistration()) return float2(-2.0, -2.0);
    float2 windowPxGL = float2(screenUV.x * SLBridgeBufferInfo.x,
                               (1.0 - screenUV.y) * SLBridgeBufferInfo.y);
    return (windowPxGL - SLBridgeViewport.xy) / SLBridgeViewport.zw;
}

bool ARDInsideFirestormWorld(float2 screenUV)
{
    float2 uv = ARDFirestormUV(screenUV);
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

float4 ARDMulInvProj(float4 v)
{
    return SLGIInvProjC0 * v.x + SLGIInvProjC1 * v.y + SLGIInvProjC2 * v.z + SLGIInvProjC3 * v.w;
}

float3 ARDReconstructViewPosition(float2 screenUV, float rawDepth)
{
    float2 nativeUV = ARDFirestormUV(screenUV);
    float4 p = ARDMulInvProj(float4(nativeUV * 2.0 - 1.0, rawDepth * 2.0 - 1.0, 1.0));
    float safeW = abs(p.w) > 1e-8 ? p.w : (p.w < 0.0 ? -1e-8 : 1e-8);
    return p.xyz / safeW;
}

bool ARDIsBackgroundDepth(float d) { return d >= 0.999999; }

float ARDGetRawDepth(float2 screenUV)
{
    return tex2D(SLNativeDepthSampler, ARDFirestormUV(screenUV)).r;
}

float ARDGetAvatarBackRawDepth(float2 screenUV)
{
    return tex2D(SLAvatarBackDepthSampler, ARDFirestormUV(screenUV)).r;
}

float4 ARDGetRawNormalData(float2 screenUV)
{
    return tex2D(SLNativeNormalsSampler, ARDFirestormUV(screenUV));
}

float4 ARDGetGBufferSpecular(float2 screenUV)
{
    if (!ARDInsideFirestormWorld(screenUV) || SLGBufferSpecularValid < 0.5) return 0.0;
    return tex2D(SLGBufferSpecularSampler, ARDFirestormUV(screenUV));
}

float ARDGetAlphaCoverage(float2 screenUV)
{
    if (!ARDInsideFirestormWorld(screenUV)) return 0.0;
    return saturate(tex2D(SLAlphaMaskSampler, ARDFirestormUV(screenUV)).a);
}

bool ARDIsPBR(float4 rawNormal)
{
    return abs(rawNormal.a - 0.67) < 0.1;
}

float ARDLegacyAuthoredSignal(float4 rawNormal, float4 specInfo)
{
    return max(max(specInfo.r, max(specInfo.g, specInfo.b)), saturate(rawNormal.b));
}

bool ARDLegacyUsesDielectricFallback(float4 rawNormal, float4 specInfo)
{
    return ARDLegacyAuthoredSignal(rawNormal, specInfo) <= ARDiagLegacyFallbackThreshold;
}

float3 ARDLegacySpecularTint(float4 rawNormal, float4 specInfo)
{
    float3 materialSpec = saturate(specInfo.rgb * ARDiagLegacySpecularScale);
    float classicEnv = saturate(rawNormal.b) * ARDiagLegacyEnvScale;
    float3 authoredTint = max(materialSpec, classicEnv.xxx);
    if (ARDLegacyUsesDielectricFallback(rawNormal, specInfo))
    {
        float d = saturate(ARDiagLegacyDielectricFallback);
        return float3(d, d, d);
    }
    return authoredTint;
}

float ARDLegacyReflectivity(float4 rawNormal, float4 specInfo)
{
    float3 tint = ARDLegacySpecularTint(rawNormal, specInfo);
    return max(tint.r, max(tint.g, tint.b));
}

float ARDPBRReflectivity(float4 specInfo)
{
    float roughness = saturate(specInfo.g);
    float metallic = saturate(specInfo.b);
    float smoothness = pow(saturate(1.0 - roughness), ARDiagPBRRoughnessPower);
    float f0Weight = lerp(0.18, 1.0, metallic);
    return saturate(ARDiagPBRStrength * smoothness * f0Weight);
}

bool ARDGeometryCandidate(float2 uv, out int rejectionReason)
{
    rejectionReason = ARD_REJECT_NONE;
    if (!ARDHasExactMatrices() || !ARDInsideFirestormWorld(uv)) return false;

    float frontRaw = ARDGetRawDepth(uv);
    if (ARDIsBackgroundDepth(frontRaw))
    {
        rejectionReason = ARD_REJECT_MISSING_D0;
        return false;
    }

    float backRaw = ARDGetAvatarBackRawDepth(uv);
    if (ARDIsBackgroundDepth(backRaw))
    {
        rejectionReason = ARD_REJECT_MISSING_AVATAR_BACK;
        return false;
    }

    float3 frontPos = ARDReconstructViewPosition(uv, frontRaw);
    float3 backPos = ARDReconstructViewPosition(uv, backRaw);
    float frontDepth = -frontPos.z;
    float backDepth = -backPos.z;
    if (backDepth <= frontDepth + max(ARDiagAvatarMinThickness, 1e-6))
    {
        rejectionReason = ARD_REJECT_THIN_INTERVAL;
        return false;
    }

    return true;
}

bool ARDMaterialCandidate(float2 uv, out int rejectionReason)
{
    if (!ARDGeometryCandidate(uv, rejectionReason)) return false;

    // Material candidate excludes alpha by design.
    if (SLGBufferSpecularValid <= 0.5) return false;

    float4 rawNormal = ARDGetRawNormalData(uv);
    float4 specInfo = ARDGetGBufferSpecular(uv);
    bool pbr = ARDIsPBR(rawNormal);
    float reflectivity = pbr ? ARDPBRReflectivity(specInfo) : ARDLegacyReflectivity(rawNormal, specInfo);
    float minResponse = pbr ? 1e-5 : max(ARDiagLegacyMinReflectivity, 0.0);

    if (reflectivity <= minResponse)
    {
        rejectionReason = pbr ? ARD_REJECT_PBR_REFLECTIVITY : ARD_REJECT_LEGACY_REFLECTIVITY;
        return false;
    }

    return true;
}

bool ARDFullyEligible(float2 uv, out int rejectionReason)
{
    if (!ARDMaterialCandidate(uv, rejectionReason)) return false;

    float receiverAlpha = 1.0 - saturate(ARDGetAlphaCoverage(uv) * ARDiagAlphaReceiverProtection);
    if (receiverAlpha <= 1e-5)
    {
        rejectionReason = ARD_REJECT_ALPHA_MASK;
        return false;
    }

    rejectionReason = ARD_REJECT_NONE;
    return true;
}

float3 ARDRejectionColor(int reason, bool accepted)
{
    if (reason == ARD_REJECT_MISSING_D0)             return float3(1.00, 0.00, 0.00);
    if (reason == ARD_REJECT_MISSING_AVATAR_BACK)    return float3(1.00, 0.00, 1.00);
    if (reason == ARD_REJECT_THIN_INTERVAL)          return float3(1.00, 1.00, 0.00);
    if (reason == ARD_REJECT_LEGACY_REFLECTIVITY)    return float3(0.00, 1.00, 1.00);
    if (reason == ARD_REJECT_PBR_REFLECTIVITY)       return float3(0.10, 0.25, 1.00);
    if (reason == ARD_REJECT_ALPHA_MASK)             return float3(1.00, 0.35, 0.00);
    return accepted ? float3(0.00, 1.00, 0.00) : 0.0.xxx;
}

float4 ARDGeometryPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    int rejectionReason;
    float m = ARDGeometryCandidate(uv, rejectionReason) ? 1.0 : 0.0;
    return float4(m.xxx, 1.0);
}

float4 ARDMaterialPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    int rejectionReason;
    float m = ARDMaterialCandidate(uv, rejectionReason) ? 1.0 : 0.0;
    return float4(m.xxx, 1.0);
}

float4 ARDRejectionPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    int rejectionReason;
    bool accepted = ARDFullyEligible(uv, rejectionReason);

    if (!ARDHasExactMatrices() || !ARDInsideFirestormWorld(uv))
        return float4(0.0, 0.0, 0.0, 1.0);

    float3 reasonColor = ARDRejectionColor(rejectionReason, accepted);
    float3 scene = tex2D(ReShade::BackBuffer, uv).rgb;

    // Keep enough scene context to locate a remote avatar while retaining
    // saturated diagnostic colors.
    return float4(saturate(reasonColor * 0.85 + scene * 0.15), 1.0);
}

technique SL_AR_v0_2_GeometryCandidate
<
    ui_label = "AVATAR RECEIVER — Geometry candidate";
    ui_tooltip = "White = valid D0 + valid DavatarBack + positive interval above min thickness. No material/specular/roughness/alpha gating.";
>
{
    pass GeometryCandidate
    {
        VertexShader = PostProcessVS;
        PixelShader = ARDGeometryPS;
    }
}

technique SL_AR_v0_2_MaterialCandidate
<
    ui_label = "AVATAR RECEIVER — Material candidate";
    ui_tooltip = "White = geometry candidate plus v0.1 legacy/PBR reflectivity eligibility. Alpha gating is intentionally excluded.";
>
{
    pass MaterialCandidate
    {
        VertexShader = PostProcessVS;
        PixelShader = ARDMaterialPS;
    }
}

technique SL_AR_v0_2_RejectionReason
<
    ui_label = "AVATAR RECEIVER — Rejection reason";
    ui_tooltip = "Red missing D0; magenta missing DavatarBack; yellow thin interval; cyan legacy reflectivity; blue PBR roughness/reflectivity; orange alpha; green fully eligible.";
>
{
    pass RejectionReason
    {
        VertexShader = PostProcessVS;
        PixelShader = ARDRejectionPS;
    }
}
