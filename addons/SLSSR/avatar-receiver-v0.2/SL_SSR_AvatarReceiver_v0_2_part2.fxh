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


// Diagnostic-only staged qualification. These helpers intentionally do not feed the
// SSR trace/composite path; modes 0-5 continue to use ARGetAvatarReceiver unchanged.
bool ARGeometryCandidate(float2 uv, out int rejectionReason)
{
    rejectionReason = SL_AR_REJECT_NONE;
    if (!ARHasExactMatrices() || !ARInsideFirestormWorld(uv))
    {
        rejectionReason = SL_AR_REJECT_INPUT_UNAVAILABLE;
        return false;
    }

    float frontRaw = ARGetRawDepth(uv);
    if (ARIsBackgroundDepth(frontRaw))
    {
        rejectionReason = SL_AR_REJECT_MISSING_D0;
        return false;
    }

    float backRaw = ARGetAvatarBackRawDepth(uv);
    if (ARIsBackgroundDepth(backRaw))
    {
        rejectionReason = SL_AR_REJECT_MISSING_AVATAR_BACK;
        return false;
    }

    float3 frontPos = ARReconstructViewPosition(uv, frontRaw);
    float3 backPos = ARReconstructViewPosition(uv, backRaw);
    float frontDepth = -frontPos.z;
    float backDepth = -backPos.z;
    if (backDepth <= frontDepth + max(ARAvatarMinThickness, 1e-6))
    {
        rejectionReason = SL_AR_REJECT_THIN_INTERVAL;
        return false;
    }

    return true;
}

bool ARMaterialCandidate(float2 uv, out int rejectionReason)
{
    if (!ARGeometryCandidate(uv, rejectionReason)) return false;

    // Material candidate deliberately excludes alpha. It mirrors only the
    // legacy/PBR reflectivity eligibility used by ARGetAvatarReceiver.
    if (SLGBufferSpecularValid <= 0.5)
    {
        rejectionReason = SL_AR_REJECT_INPUT_UNAVAILABLE;
        return false;
    }

    float4 rawNormal = ARGetRawNormalData(uv);
    float4 specInfo = ARGetGBufferSpecular(uv);
    bool pbr = ARIsPBR(rawNormal);
    float reflectivity = pbr ? ARPBRReflectivity(specInfo) : ARLegacyReflectivity(rawNormal, specInfo);
    float minResponse = pbr ? 1e-5 : max(ARLegacyMinReflectivity, 0.0);

    if (reflectivity <= minResponse)
    {
        rejectionReason = pbr ? SL_AR_REJECT_PBR_REFLECTIVITY : SL_AR_REJECT_LEGACY_REFLECTIVITY;
        return false;
    }

    rejectionReason = SL_AR_REJECT_NONE;
    return true;
}

bool ARFullyEligibleDiagnostic(float2 uv, out int rejectionReason)
{
    if (!ARMaterialCandidate(uv, rejectionReason)) return false;

    float receiverAlpha = 1.0 - saturate(ARGetAlphaCoverage(uv) * ARAlphaReceiverProtection);
    if (receiverAlpha <= 1e-5)
