// SL_SSR_AvatarReceiver_v0_1.fx
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

#include "ReShade.fxh"

#define SL_AR_MAX_STEPS 48
#define SL_AR_BINARY_STEPS 9

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
        "Final composite OFF / ON comparison\0";
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
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};
sampler SLAlphaMaskSampler
{
    Texture = SLAlphaMaskTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};
sampler SLSceneLinearSampler
{
    Texture = SLSceneLinearTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};
sampler SLGBufferSpecularSampler
{
    Texture = SLGBufferSpecularTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

texture SLAvatarReceiverHitTex
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA16F;
};
sampler SLAvatarReceiverHitSampler
{
    Texture = SLAvatarReceiverHitTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

bool ARHasBridgeRegistration()
{
    return SLBridgeRegistrationValid > 0.5 &&
           SLBridgeViewport.z > 1.0 && SLBridgeViewport.w > 1.0 &&
           SLBridgeBufferInfo.x > 1.0 && SLBridgeBufferInfo.y > 1.0;
}

bool ARHasExactMatrices()
{
    float invEnergy = dot(abs(SLGIInvProjC0), 1.0) + dot(abs(SLGIInvProjC1), 1.0) +
                      dot(abs(SLGIInvProjC2), 1.0) + dot(abs(SLGIInvProjC3), 1.0);
    float projEnergy = dot(abs(SLGIProjC0), 1.0) + dot(abs(SLGIProjC1), 1.0) +
                       dot(abs(SLGIProjC2), 1.0) + dot(abs(SLGIProjC3), 1.0);
    return ARHasBridgeRegistration() && SLGIProjectionValid > 0.5 && SLProbeNativeValid > 0.5 &&
           invEnergy > 0.01 && projEnergy > 0.01;
}

bool ARReceiverInputsReady()
{
    return ARHasExactMatrices() && SLGBufferSpecularValid > 0.5;
}

bool ARCompositeReady()
{
    return ARReceiverInputsReady() && SLSceneLinearValid > 0.5;
}

float2 ARFirestormUV(float2 screenUV)
{
    if (!ARHasBridgeRegistration()) return float2(-2.0, -2.0);
    float2 windowPxGL = float2(screenUV.x * SLBridgeBufferInfo.x,
                               (1.0 - screenUV.y) * SLBridgeBufferInfo.y);
    return (windowPxGL - SLBridgeViewport.xy) / SLBridgeViewport.zw;
}

float2 ARScreenUVFromFirestormUV(float2 nativeUV)
{
    float2 windowPxGL = SLBridgeViewport.xy + nativeUV * SLBridgeViewport.zw;
    return float2(windowPxGL.x / SLBridgeBufferInfo.x,
                  1.0 - windowPxGL.y / SLBridgeBufferInfo.y);
}

bool ARInsideFirestormWorld(float2 screenUV)
{
    float2 uv = ARFirestormUV(screenUV);
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

float4 ARMulInvProj(float4 v)
{
    return SLGIInvProjC0 * v.x + SLGIInvProjC1 * v.y + SLGIInvProjC2 * v.z + SLGIInvProjC3 * v.w;
}
float4 ARMulProj(float4 v)
{
    return SLGIProjC0 * v.x + SLGIProjC1 * v.y + SLGIProjC2 * v.z + SLGIProjC3 * v.w;
}

float3 ARReconstructViewPosition(float2 screenUV, float rawDepth)
{
    float2 nativeUV = ARFirestormUV(screenUV);
    float4 p = ARMulInvProj(float4(nativeUV * 2.0 - 1.0, rawDepth * 2.0 - 1.0, 1.0));
    float safeW = abs(p.w) > 1e-8 ? p.w : (p.w < 0.0 ? -1e-8 : 1e-8);
    return p.xyz / safeW;
}

bool ARProjectViewPosition(float3 viewPos, out float2 screenUV)
{
    float4 clip = ARMulProj(float4(viewPos, 1.0));
    if (abs(clip.w) <= 1e-8) { screenUV = 0.0; return false; }
    float3 ndc = clip.xyz / clip.w;
    float2 nativeUV = ndc.xy * 0.5 + 0.5;
    if (nativeUV.x <= 0.0 || nativeUV.x >= 1.0 || nativeUV.y <= 0.0 || nativeUV.y >= 1.0)
    { screenUV = 0.0; return false; }
    screenUV = ARScreenUVFromFirestormUV(nativeUV);
    return ARInsideFirestormWorld(screenUV);
}

bool ARIsBackgroundDepth(float d) { return d >= 0.999999; }
float ARGetRawDepth(float2 screenUV) { return tex2D(SLNativeDepthSampler, ARFirestormUV(screenUV)).r; }
float ARGetBackgroundRawDepth(float2 screenUV) { return tex2D(SLBackgroundDepthSampler, ARFirestormUV(screenUV)).r; }
float ARGetAvatarBackRawDepth(float2 screenUV) { return tex2D(SLAvatarBackDepthSampler, ARFirestormUV(screenUV)).r; }
float3 ARGetBackgroundColor(float2 screenUV) { return max(tex2D(SLBackgroundColorSampler, ARFirestormUV(screenUV)).rgb, 0.0); }
float4 ARGetRawNormalData(float2 screenUV) { return tex2D(SLNativeNormalsSampler, ARFirestormUV(screenUV)); }

float3 ARDecodeFirestormNormalRaw(float4 encodedNormal)
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

float4 ARGetSceneLinear(float2 screenUV)
{
    if (!ARInsideFirestormWorld(screenUV) || SLSceneLinearValid < 0.5) return 0.0;
    return tex2D(SLSceneLinearSampler, ARFirestormUV(screenUV));
}
float4 ARGetGBufferSpecular(float2 screenUV)
{
    if (!ARInsideFirestormWorld(screenUV) || SLGBufferSpecularValid < 0.5) return 0.0;
    return tex2D(SLGBufferSpecularSampler, ARFirestormUV(screenUV));
}
float ARGetAlphaCoverage(float2 screenUV)
{
    if (!ARInsideFirestormWorld(screenUV)) return 0.0;
    return saturate(tex2D(SLAlphaMaskSampler, ARFirestormUV(screenUV)).a);
}

bool ARIsPBR(float4 rawNormal) { return abs(rawNormal.a - 0.67) < 0.1; }
float ARLegacyAuthoredSignal(float4 rawNormal, float4 specInfo)
{
    return max(max(specInfo.r, max(specInfo.g, specInfo.b)), saturate(rawNormal.b));
}
bool ARLegacyUsesDielectricFallback(float4 rawNormal, float4 specInfo)
{
    return ARLegacyAuthoredSignal(rawNormal, specInfo) <= ARLegacyFallbackThreshold;
}
float3 ARLegacySpecularTint(float4 rawNormal, float4 specInfo)
{
    float3 materialSpec = saturate(specInfo.rgb * ARLegacySpecularScale);
    float classicEnv = saturate(rawNormal.b) * ARLegacyEnvScale;
    float3 authoredTint = max(materialSpec, classicEnv.xxx);
    if (ARLegacyUsesDielectricFallback(rawNormal, specInfo))
    {
        float d = saturate(ARLegacyDielectricFallback);
        return float3(d, d, d);
    }
    return authoredTint;
}
float ARLegacyReflectivity(float4 rawNormal, float4 specInfo)
{
    float3 tint = ARLegacySpecularTint(rawNormal, specInfo);
    return max(tint.r, max(tint.g, tint.b));
}
float ARPBRReflectivity(float4 specInfo)
{
    float roughness = saturate(specInfo.g);
    float metallic = saturate(specInfo.b);
    float smoothness = pow(saturate(1.0 - roughness), ARPBRRoughnessPower);
    float f0Weight = lerp(0.18, 1.0, metallic);
    return saturate(ARPBRStrength * smoothness * f0Weight);
}
float ARViewFresnel(float3 viewPos, float3 normal)
{
    float3 toCamera = normalize(-viewPos);
    float nv = saturate(dot(normal, toCamera));
    float grazing = pow(1.0 - nv, 5.0);
    return lerp(0.45, 1.0, grazing);
}

bool ARGetAvatarReceiver(float2 uv, out float3 viewPos, out float3 normal,
                         out bool pbr, out float reflectivity, out float3 legacyTint,
                         out float receiverAlpha)
{
    viewPos = 0.0; normal = float3(0.0, 0.0, 1.0); pbr = false;
    reflectivity = 0.0; legacyTint = 0.0; receiverAlpha = 0.0;
    if (!ARReceiverInputsReady() || !ARInsideFirestormWorld(uv)) return false;

    float frontRaw = ARGetRawDepth(uv);
    float backRaw = ARGetAvatarBackRawDepth(uv);
    if (ARIsBackgroundDepth(frontRaw) || ARIsBackgroundDepth(backRaw)) return false;

    viewPos = ARReconstructViewPosition(uv, frontRaw);
    float3 backPos = ARReconstructViewPosition(uv, backRaw);
    float frontDepth = -viewPos.z;
    float backDepth = -backPos.z;
    if (backDepth <= frontDepth + max(ARAvatarMinThickness, 1e-6)) return false;

    float4 rawNormal = ARGetRawNormalData(uv);
    float4 specInfo = ARGetGBufferSpecular(uv);
    normal = ARDecodeFirestormNormalRaw(rawNormal);
    pbr = ARIsPBR(rawNormal);
    legacyTint = pbr ? 1.0.xxx : ARLegacySpecularTint(rawNormal, specInfo);
    reflectivity = pbr ? ARPBRReflectivity(specInfo) : ARLegacyReflectivity(rawNormal, specInfo);
    receiverAlpha = 1.0 - saturate(ARGetAlphaCoverage(uv) * ARAlphaReceiverProtection);
    float minResponse = pbr ? 1e-5 : max(ARLegacyMinReflectivity, 0.0);
    return reflectivity > minResponse && receiverAlpha > 1e-5;
}

float AREdgeConfidence(float2 hitUV)
{
    float2 d = min(hitUV, 1.0 - hitUV);
    return saturate(min(d.x, d.y) / max(AREdgeFade, 1e-5));
}
float ARDistanceConfidence(float rayDistance)
{
    float start = min(ARDistanceFadeStart, ARMaxDistance - 1e-3);
    return 1.0 - smoothstep(start, max(ARMaxDistance, start + 1e-3), rayDistance);
}

bool AREvaluateStaticWorldDepth(float3 rayPos, out float2 uv, out float delta)
{
    uv = 0.0; delta = -1e6;
    if (!ARProjectViewPosition(rayPos, uv)) return false;
    float sceneDepthRaw = ARGetBackgroundRawDepth(uv);
    if (ARIsBackgroundDepth(sceneDepthRaw)) return true;
    float3 scenePos = ARReconstructViewPosition(uv, sceneDepthRaw);
    delta = (-rayPos.z) - (-scenePos.z);
    return true;
}

bool ARTraceStaticWorld(float3 originPos, float3 originNormal, float3 rayDir,
                        out float2 hitUV, out float hitDistance, out float confidence)
{
    hitUV = 0.0; hitDistance = 0.0; confidence = 0.0;
    if (rayDir.z >= -0.001) return false;

    float3 startPos = originPos + originNormal * max(ARRayOriginBias, 0.0);
    float previousT = 0.0, previousDelta = -1e6;
    bool previousValid = false, previousWasBackground = false;
    float t = max(ARInitialStep, 0.01);

    [loop]
    for (int i = 0; i < SL_AR_MAX_STEPS; ++i)
    {
        if (i >= ARTraceSteps || t > ARMaxDistance) break;
        float3 rayPos = startPos + rayDir * t;
        float2 uv; float delta;
        if (!AREvaluateStaticWorldDepth(rayPos, uv, delta)) break;

        if (delta < -9e5)
        {
            previousValid = true; previousWasBackground = true;
            previousDelta = -1e6; previousT = t; t *= ARStepGrowth; continue;
        }

        if (previousValid && previousDelta < 0.0 && delta >= 0.0)
        {
            bool backgroundEntry = previousWasBackground;
            float lo = previousT, hi = t;
            [unroll]
            for (int b = 0; b < SL_AR_BINARY_STEPS; ++b)
            {
                float mid = (lo + hi) * 0.5;
                float2 midUV; float midDelta;
                if (!AREvaluateStaticWorldDepth(startPos + rayDir * mid, midUV, midDelta)) break;
                if (midDelta < -9e5) { lo = mid; continue; }
                if (midDelta >= 0.0) hi = mid; else lo = mid;
            }

            float2 finalUV; float finalDelta;
            bool finalDepthValid = AREvaluateStaticWorldDepth(startPos + rayDir * hi, finalUV, finalDelta);
            bool standardHit = finalDepthValid && finalDelta >= 0.0 && finalDelta <= ARThickness;
            bool recoveredBackgroundEntry = finalDepthValid && backgroundEntry &&
                                            ARBackgroundEntryRecovery > 0 && finalDelta >= 0.0;
            if (standardHit || recoveredBackgroundEntry)
            {
                hitUV = finalUV; hitDistance = hi;
                confidence = AREdgeConfidence(finalUV) * ARDistanceConfidence(hi);
                if (backgroundEntry) confidence *= saturate(ARBackgroundEntryConfidence);
                return confidence > 0.0;
            }
        }

        previousValid = true; previousWasBackground = false;
        previousDelta = delta; previousT = t; t *= ARStepGrowth;
    }
    return false;
}

float4 ARTracePS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 viewPos, normal, legacyTint; bool pbr; float reflectivity, receiverAlpha;
    if (!ARGetAvatarReceiver(uv, viewPos, normal, pbr, reflectivity, legacyTint, receiverAlpha)) return 0.0;
    float3 rayDir = normalize(reflect(normalize(viewPos), normal));
    float2 hitUV; float hitDistance, confidence;
    if (!ARTraceStaticWorld(viewPos, normal, rayDir, hitUV, hitDistance, confidence)) return 0.0;
    return float4(ARGetBackgroundColor(hitUV), confidence);
}

float ARSceneToPresentationScale(float2 screenUV)
{
    const float3 luma = float3(0.2126, 0.7152, 0.0722);
    float3 sceneLinear = max(ARGetSceneLinear(screenUV).rgb, 0.0);
    float3 presentation = max(tex2D(ReShade::BackBuffer, screenUV).rgb, 0.0);
    float linearLum = dot(sceneLinear, luma);
    if (linearLum <= 1e-5) return 0.0;
    return clamp(dot(presentation, luma) / max(linearLum, 1e-5), 0.0, 8.0);
}
float3 ARLinearToSRGB(float3 cl)
{
    cl = saturate(cl);
    float3 lo = cl * 12.92, hi = 1.055 * pow(cl, 0.41666) - 0.055;
    float3 result;
    result.r = cl.r < 0.0031308 ? lo.r : hi.r;
    result.g = cl.g < 0.0031308 ? lo.g : hi.g;
    result.b = cl.b < 0.0031308 ? lo.b : hi.b;
    return result;
}
float3 ARPBRNeutralToneMap(float3 color)
{
    const float startCompression = 0.76, desaturation = 0.15;
    float x = min(color.r, min(color.g, color.b));
    color -= x < 0.08 ? x - 6.25 * x * x : 0.04;
    float peak = max(color.r, max(color.g, color.b));
    if (peak < startCompression) return color;
    const float d = 1.0 - startCompression;
    float newPeak = 1.0 - d * d / (peak + d - startCompression);
    color *= newPeak / max(peak, 1e-6);
    float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
    return lerp(color, newPeak.xxx, g);
}
float3 ARACESInput(float3 c)
{
    return float3(0.59719*c.r+0.35458*c.g+0.04823*c.b,
                  0.07600*c.r+0.90834*c.g+0.01566*c.b,
                  0.02840*c.r+0.13383*c.g+0.83777*c.b);
}
float3 ARACESOutput(float3 c)
{
    return float3(1.60475*c.r-0.53108*c.g-0.07367*c.b,
                 -0.10208*c.r+1.10813*c.g-0.00605*c.b,
                 -0.00327*c.r-0.07276*c.g+1.07602*c.b);
}
float3 ARRRTAndODTFit(float3 color)
{
    float3 a = color * (color + 0.0245786) - 0.000090537;
    float3 b = color * (0.983729 * color + 0.4329510) + 0.238081;
    return a / max(b, 1e-6);
}
float3 ARACESHillToneMap(float3 color)
{
    return saturate(ARACESOutput(ARRRTAndODTFit(ARACESInput(color))));
}
float3 ARFirestormToneMapLinear(float3 color)
{
    float3 exposed = max(color, 0.0) * max(SLGIFinalExposure, 0.0);
    float3 mapped = SLGITonemapType < 0.5 ? ARPBRNeutralToneMap(exposed) : ARACESHillToneMap(exposed);
    return saturate(lerp(exposed, mapped, saturate(SLGITonemapMix)));
}
float ARUseSRGBEncoding(float3 sceneLinear, float3 actualBackBuffer)
{
    float3 tm = ARFirestormToneMapLinear(sceneLinear), srgb = ARLinearToSRGB(tm);
    return dot(abs(srgb - actualBackBuffer), 1.0) < dot(abs(tm - actualBackBuffer), 1.0) ? 1.0 : 0.0;
}
float3 ARFirestormPresentation(float3 sceneLinear, float useSRGB)
{
    float3 tm = ARFirestormToneMapLinear(sceneLinear);
    return lerp(tm, ARLinearToSRGB(tm), useSRGB);
}
float3 ARDebugHDR(float3 c) { return 1.0 - exp(-max(c, 0.0) * ARDebugGain); }

float4 ARCompositePS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 currentColor = tex2D(ReShade::BackBuffer, uv);
    float3 viewPos, normal, legacyTint; bool pbr; float reflectivity, receiverAlpha;
    bool eligible = ARGetAvatarReceiver(uv, viewPos, normal, pbr, reflectivity, legacyTint, receiverAlpha);
    float4 hit = tex2D(SLAvatarReceiverHitSampler, uv);
    bool acceptedHit = eligible && hit.a > 1e-5;

    if (ARDisplayMode == 1)
    {
        float m = eligible ? 1.0 : 0.0;
        return float4(m.xxx, 1.0);
    }
    if (ARDisplayMode == 2)
    {
        if (!eligible) return float4(0.0, 0.0, 0.0, 1.0);
        float3 rayDir = normalize(reflect(normalize(viewPos), normal));
        return float4(uv.x < 0.5 ? normal * 0.5 + 0.5 : rayDir * 0.5 + 0.5, 1.0);
    }
    if (ARDisplayMode == 3)
    {
        float m = acceptedHit ? 1.0 : 0.0;
        return float4(m.xxx, 1.0);
    }
    if (!eligible || !acceptedHit)
    {
        if (ARDisplayMode == 4) return float4(0.0, 0.0, 0.0, 1.0);
        return currentColor;
    }

    float fresnel = ARViewFresnel(viewPos, normal);
    float materialWeight = pbr ? saturate(reflectivity) : 1.0;
    float weight = saturate(hit.a) * materialWeight * fresnel * max(ARStrength, 0.0) * receiverAlpha;
    float3 materialTint = pbr ? 1.0.xxx : legacyTint;
    float3 reflectionLinear = max(hit.rgb, 0.0) * weight * materialTint;
    float appliedWeight = pbr ? weight : weight * reflectivity;
    float baseRemoval = saturate(appliedWeight * saturate(ARBaseReplacement));

    if (ARDisplayMode == 4) return float4(ARDebugHDR(reflectionLinear), 1.0);
    if (!ARCompositeReady()) return currentColor;

    float3 sceneLinear = max(ARGetSceneLinear(uv).rgb, 0.0);
    float3 compositeLinear = sceneLinear * (1.0 - baseRemoval) + reflectionLinear;
    float3 delta;
    if (SLGITonemapValid < 0.5)
        delta = (compositeLinear - sceneLinear) * ARSceneToPresentationScale(uv);
    else
    {
        float useSRGB = ARUseSRGBEncoding(sceneLinear, currentColor.rgb);
        delta = ARFirestormPresentation(compositeLinear, useSRGB) - ARFirestormPresentation(sceneLinear, useSRGB);
    }

    float4 compositeColor = currentColor;
    if (AREnable > 0) compositeColor.rgb = max(currentColor.rgb + delta, 0.0);
    if (ARDisplayMode == 5)
    {
        float3 onColor = max(currentColor.rgb + delta, 0.0);
        return float4(uv.x < 0.5 ? currentColor.rgb : onColor, currentColor.a);
    }
    return compositeColor;
}

technique SL_SSR_AvatarReceiver_v0_1
<
    ui_label = "AVATAR RECEIVER — v0.1 Static-World Trace";
    ui_tooltip = "Avatar pixels are receivers. Rays hit Dstatic only and resolve Cstatic only. Keep CORE v0.49 before this technique; the CORE [D0,DavatarBack] avatar-hit path is unchanged.";
>
{
    pass AvatarReceiverTrace
    {
        VertexShader = PostProcessVS;
        PixelShader = ARTracePS;
        RenderTarget = SLAvatarReceiverHitTex;
    }
    pass AvatarReceiverCompositeAndDiagnostics
    {
        VertexShader = PostProcessVS;
        PixelShader = ARCompositePS;
    }
}
