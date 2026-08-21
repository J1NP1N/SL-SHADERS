    {
        rejectionReason = SL_AR_REJECT_ALPHA_MASK;
        return false;
    }

    rejectionReason = SL_AR_REJECT_NONE;
    return true;
}

float3 ARRejectionColor(int reason, bool accepted)
{
    if (accepted)                                      return float3(0.00, 1.00, 0.00); // green
    if (reason == SL_AR_REJECT_MISSING_D0)             return float3(1.00, 0.00, 0.00); // red
    if (reason == SL_AR_REJECT_MISSING_AVATAR_BACK)    return float3(1.00, 0.00, 1.00); // magenta
    if (reason == SL_AR_REJECT_THIN_INTERVAL)          return float3(1.00, 1.00, 0.00); // yellow
    if (reason == SL_AR_REJECT_LEGACY_REFLECTIVITY)    return float3(0.00, 1.00, 1.00); // cyan
    if (reason == SL_AR_REJECT_PBR_REFLECTIVITY)       return float3(0.10, 0.25, 1.00); // blue
    if (reason == SL_AR_REJECT_ALPHA_MASK)             return float3(1.00, 0.45, 0.00); // orange
    return float3(0.0, 0.0, 0.0); // unavailable / outside viewport
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
    return saturate(ARACESoutput(ARRRTAndODTFit(ARACESInput(color))));
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

    if (ARDisplayMode == 6)
    {
        int rejectionReason;
        float m = ARGeometryCandidate(uv, rejectionReason) ? 1.0 : 0.0;
        return float4(m.xxx, 1.0);
    }
    if (ARDisplayMode == 7)
    {
        int rejectionReason;
        float m = ARMaterialCandidate(uv, rejectionReason) ? 1.0 : 0.0;
        return float4(m.xxx, 1.0);
    }
    if (ARDisplayMode == 8)
    {
        int rejectionReason;
        bool accepted = ARFullyEligibleDiagnostic(uv, rejectionReason);
        return float4(ARRejectionColor(rejectionReason, accepted), 1.0);
    }

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

technique SL_SSR_AvatarReceiver_v0_2
<
    ui_label = "AVATAR RECEIVER — v0.2 Static-World Trace + Qualification Views";
    ui_tooltip = "Avatar pixels are receivers. Rays hit Dstatic only and resolve Cstatic only. Modes 6-8 split geometry/material/alpha qualification for diagnostics. CORE [D0,DavatarBack] avatar-hit path is unchanged.";
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
