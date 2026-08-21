// SL_GTAO_v0_1_Reference.fx
// Correctness-first full-resolution GTAO for Firestorm + ReShade.
//
// Primary geometry depth: SL_DEPTH_PRIMARY_NATIVE (D0) only.
// Native normals:         SL_NORMALS (Firestorm stereographic XY encoding).
// Final application:      current ReShade backbuffer.
//
// No Dstatic, no SSR dependency, no temporal accumulation.
// Denoise is spatial bilateral only and defaults OFF so raw GTAO can be proven first.

#include "ReShade.fxh"

#define SL_GTAO_PI 3.14159265358979323846
#define SL_GTAO_HALF_PI 1.57079632679489661923
#define SL_GTAO_MAX_SLICES 8
#define SL_GTAO_MAX_STEPS 8
#define SL_GTAO_MAX_FILTER_RADIUS 4

uniform float4 SLBridgeViewport = float4(0.0, 0.0, 1.0, 1.0);
uniform float4 SLBridgeBufferInfo = float4(1.0, 1.0, 1.0, 1.0);
uniform float SLBridgeRegistrationValid = 0.0;

uniform float4 SLGIInvProjC0 = 0.0;
uniform float4 SLGIInvProjC1 = 0.0;
uniform float4 SLGIInvProjC2 = 0.0;
uniform float4 SLGIInvProjC3 = 0.0;
uniform float SLGIProjectionValid = 0.0;
uniform float SLProbeNativeValid = 0.0;

uniform float SLPrimaryDepthNativeValid = 0.0;
uniform float2 SLPrimaryDepthNativeSize = float2(0.0, 0.0);

uniform int GTAOEnable
<
    ui_label = "GTAO - Enable Composite";
    ui_tooltip = "Applies the selected raw/filtered AO to the current backbuffer. Diagnostics remain available while disabled.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 1;

uniform float GTAORadius
<
    ui_label = "GTAO - Radius";
    ui_tooltip = "View-space AO radius. D0 samples outside this physical radius cannot occlude.";
    ui_type = "drag";
    ui_min = 0.05; ui_max = 6.0; ui_step = 0.05;
> = 1.25;

uniform float GTAOStrength
<
    ui_label = "GTAO - Strength";
    ui_tooltip = "Scales occlusion after the raw horizon integral. 1.0 is the reference response.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 3.0; ui_step = 0.05;
> = 1.0;

uniform float GTAOFalloffStart
<
    ui_label = "GTAO - Falloff Start";
    ui_tooltip = "Fraction of Radius at which distance attenuation begins. 1.0 means no falloff before the hard radius.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.65;

uniform int GTAOSliceCount
<
    ui_label = "GTAO - Slice Count";
    ui_tooltip = "Number of azimuthal GTAO slices. Each slice searches both directions.";
    ui_type = "slider";
    ui_min = 1; ui_max = SL_GTAO_MAX_SLICES;
> = 8;

uniform int GTAOStepsPerSide
<
    ui_label = "GTAO - Steps Per Side";
    ui_tooltip = "Horizon samples per direction, per slice.";
    ui_type = "slider";
    ui_min = 1; ui_max = SL_GTAO_MAX_STEPS;
> = 8;

uniform float GTAOMaxRadiusPixels
<
    ui_label = "GTAO - Max Radius Pixels";
    ui_tooltip = "Safety cap for projected search radius. Raise only when validating large-radius near-camera AO.";
    ui_type = "drag";
    ui_min = 16.0; ui_max = 384.0; ui_step = 8.0;
> = 256.0;

uniform float GTAOSurfaceBias
<
    ui_label = "GTAO - Surface Bias";
    ui_tooltip = "Small view-space normal offset used only for horizon vectors to suppress self-occlusion.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.05; ui_step = 0.001;
> = 0.005;

uniform float GTAOSilhouetteDepthRelative
<
    ui_label = "GTAO - Silhouette Relative Depth";
    ui_tooltip = "Immediate-neighbor relative depth jump that begins blocking a horizon direction.";
    ui_type = "drag";
    ui_min = 0.001; ui_max = 0.25; ui_step = 0.001;
> = 0.025;

uniform float GTAOSilhouetteDepthAbsolute
<
    ui_label = "GTAO - Silhouette Absolute Depth";
    ui_tooltip = "Minimum view-space depth jump used by silhouette rejection.";
    ui_type = "drag";
    ui_min = 0.001; ui_max = 1.0; ui_step = 0.005;
> = 0.04;

uniform float GTAOSilhouetteNormalDot
<
    ui_label = "GTAO - Silhouette Normal Dot";
    ui_tooltip = "Normal disagreement strengthens depth-edge rejection; it never rejects a continuous-depth corner by itself.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.65;

uniform int GTAOEnableDenoise
<
    ui_label = "GTAO - Enable Bilateral Denoise";
    ui_tooltip = "OFF by default. Prove Raw GTAO first; then enable the full-resolution depth/normal bilateral filter.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 0;

uniform int GTAODenoiseRadius
<
    ui_label = "GTAO - Denoise Radius";
    ui_tooltip = "Separable bilateral radius in full-resolution pixels.";
    ui_type = "slider";
    ui_min = 1; ui_max = SL_GTAO_MAX_FILTER_RADIUS;
> = 2;

uniform float GTAODenoiseDepthSigma
<
    ui_label = "GTAO - Denoise Depth Sigma";
    ui_tooltip = "Relative view-depth scale for bilateral weights.";
    ui_type = "drag";
    ui_min = 0.001; ui_max = 0.20; ui_step = 0.001;
> = 0.025;

uniform float GTAODenoiseNormalPower
<
    ui_label = "GTAO - Denoise Normal Power";
    ui_tooltip = "Higher values reduce filtering across normal changes.";
    ui_type = "drag";
    ui_min = 1.0; ui_max = 64.0; ui_step = 1.0;
> = 24.0;

uniform float GTAODenoiseEdgeStop
<
    ui_label = "GTAO - Denoise Edge Stop";
    ui_tooltip = "Strength of the precomputed depth-discontinuity stop mask in the bilateral pass.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 1.0;

uniform float GTAODepthDisplayRange
<
    ui_label = "GTAO - Linear D0 Display Range";
    ui_tooltip = "Maximum view depth used by the logarithmic Linear D0 diagnostic.";
    ui_type = "drag";
    ui_min = 2.0; ui_max = 512.0; ui_step = 2.0;
> = 64.0;

uniform int GTAODisplayMode
<
    ui_label = "GTAO - Diagnostic View";
    ui_type = "combo";
    ui_items =
        "Final AO composite\0"
        "Linear D0\0"
        "Decoded normals\0"
        "Raw GTAO\0"
        "Filtered GTAO\0"
        "Depth-discontinuity rejection\0"
        "Final AO contribution\0"
        "Passthrough\0";
> = 0;

texture SLGTAODepthTex : SL_DEPTH_PRIMARY_NATIVE;
texture SLGTAONormalsTex : SL_NORMALS;

sampler SLGTAODepthSampler
{
    Texture = SLGTAODepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLGTAONormalsSampler
{
    Texture = SLGTAONormalsTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

texture SLGTAOEdgeTex
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R16F;
};
sampler SLGTAOEdgeSampler
{
    Texture = SLGTAOEdgeTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

texture SLGTAORawTex
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R16F;
};
sampler SLGTAORawSampler
{
    Texture = SLGTAORawTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

texture SLGTAOFilterHTex
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R16F;
};
sampler SLGTAOFilterHSampler
{
    Texture = SLGTAOFilterHTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

texture SLGTAOFilteredTex
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R16F;
};
sampler SLGTAOFilteredSampler
{
    Texture = SLGTAOFilteredTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

bool GTAOHasBridgeRegistration()
{
    return SLBridgeRegistrationValid > 0.5 &&
           SLBridgeViewport.z > 1.0 && SLBridgeViewport.w > 1.0 &&
           SLBridgeBufferInfo.x > 1.0 && SLBridgeBufferInfo.y > 1.0;
}

bool GTAOHasExactMatrices()
{
    float e =
        dot(abs(SLGIInvProjC0), 1.0) +
        dot(abs(SLGIInvProjC1), 1.0) +
        dot(abs(SLGIInvProjC2), 1.0) +
        dot(abs(SLGIInvProjC3), 1.0);

    return GTAOHasBridgeRegistration() &&
           SLGIProjectionValid > 0.5 &&
           SLProbeNativeValid > 0.5 &&
           e > 0.01;
}

bool GTAOInputsReady()
{
    return GTAOHasExactMatrices() &&
           SLPrimaryDepthNativeValid > 0.5 &&
           SLPrimaryDepthNativeSize.x > 1.0 &&
           SLPrimaryDepthNativeSize.y > 1.0;
}

float2 GTAOFirestormUV(float2 screenUV)
{
    if (!GTAOHasBridgeRegistration())
        return float2(-2.0, -2.0);

    float2 windowPxGL = float2(
        screenUV.x * SLBridgeBufferInfo.x,
        (1.0 - screenUV.y) * SLBridgeBufferInfo.y);

    return (windowPxGL - SLBridgeViewport.xy) / SLBridgeViewport.zw;
}

float2 GTAOScreenUVFromFirestormUV(float2 nativeUV)
{
    float2 windowPxGL = SLBridgeViewport.xy + nativeUV * SLBridgeViewport.zw;
    return float2(
        windowPxGL.x / SLBridgeBufferInfo.x,
        1.0 - windowPxGL.y / SLBridgeBufferInfo.y);
}

bool GTAOInsideNativeUV(float2 uv)
{
    return uv.x > 0.0 && uv.x < 1.0 &&
           uv.y > 0.0 && uv.y < 1.0;
}

bool GTAOInsideFirestormWorld(float2 screenUV)
{
    return GTAOInsideNativeUV(GTAOFirestormUV(screenUV));
}

float4 GTAOMulInvProj(float4 v)
{
    return SLGIInvProjC0 * v.x +
           SLGIInvProjC1 * v.y +
           SLGIInvProjC2 * v.z +
           SLGIInvProjC3 * v.w;
}

float3 GTAOReconstructViewPositionNative(float2 nativeUV, float rawDepth)
{
    float4 p = GTAOMulInvProj(float4(
        nativeUV * 2.0 - 1.0,
        rawDepth * 2.0 - 1.0,
        1.0));

    float safeW = abs(p.w) > 1e-8 ? p.w : (p.w < 0.0 ? -1e-8 : 1e-8);
    return p.xyz / safeW;
}

bool GTAOIsBackgroundDepth(float rawDepth)
{
    return rawDepth >= 0.999999;
}

float GTAORawDepthNative(float2 nativeUV)
{
    return tex2D(SLGTAODepthSampler, nativeUV).r;
}

// Firestorm native normal encoding used by the current receiver path.
// XY is stereographic; B/A may contain material metadata and is not part of decode.
float3 GTAODecodeFirestormNormal(float4 encodedNormal)
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

float3 GTAONormalNative(float2 nativeUV)
{
    return GTAODecodeFirestormNormal(tex2D(SLGTAONormalsSampler, nativeUV));
}

float GTAOViewDepthNative(float2 nativeUV, float rawDepth)
{
    if (GTAOIsBackgroundDepth(rawDepth))
        return 0.0;
    return max(-GTAOReconstructViewPositionNative(nativeUV, rawDepth).z, 0.0);
}

float GTAODepthViz(float d)
{
    float range = max(GTAODepthDisplayRange, 1.0);
    return saturate(log2(1.0 + max(d, 0.0)) / log2(1.0 + range));
}

float GTAOPairDiscontinuity(
    float centerDepth,
    float3 centerNormal,
    float sampleDepth,
    float3 sampleNormal)
{
    float threshold = max(
        GTAOSilhouetteDepthAbsolute,
        max(centerDepth, 0.25) * GTAOSilhouetteDepthRelative);

    float depthReject = smoothstep(threshold, threshold * 2.0, abs(sampleDepth - centerDepth));
    float nd = saturate(dot(centerNormal, sampleNormal));
    float normalReject = saturate(
        (GTAOSilhouetteNormalDot - nd) /
        max(GTAOSilhouetteNormalDot, 1e-4));

    // A normal break can strengthen a real depth edge, but cannot create a
    // rejection by itself. This keeps concave same-depth corners available to AO.
    return saturate(depthReject * lerp(0.75, 1.0, normalReject));
}

float GTAOImmediateDirectionalReject(
    float2 nativeUV,
    float2 direction,
    float centerDepth,
    float3 centerNormal)
{
    float2 texel = 1.0 / max(SLPrimaryDepthNativeSize, float2(1.0, 1.0));
    float2 probeUV = nativeUV + direction * texel * 1.5;

    if (!GTAOInsideNativeUV(probeUV))
        return 1.0;

    float raw = GTAORawDepthNative(probeUV);
    if (GTAOIsBackgroundDepth(raw))
        return 1.0;

    float depth = GTAOViewDepthNative(probeUV, raw);
    float3 normal = GTAONormalNative(probeUV);
    return GTAOPairDiscontinuity(centerDepth, centerNormal, depth, normal);
}

float GTAODistanceWeight(float distanceVS)
{
    float radius = max(GTAORadius, 1e-4);
    if (distanceVS >= radius)
        return 0.0;

    float start = saturate(GTAOFalloffStart) * radius;
    float width = max(radius - start, 1e-4);
    float x = saturate((distanceVS - start) / width);
    return 1.0 - x * x * (3.0 - 2.0 * x);
}

float GTAOProjectedMetersPerPixel(float2 nativeUV, float centerRaw, float3 centerPos)
{
    float2 texel = 1.0 / max(SLPrimaryDepthNativeSize, float2(1.0, 1.0));
    float2 uvX = clamp(nativeUV + float2(texel.x, 0.0), texel, 1.0 - texel);
    float2 uvY = clamp(nativeUV + float2(0.0, texel.y), texel, 1.0 - texel);

    float3 pX = GTAOReconstructViewPositionNative(uvX, centerRaw);
    float3 pY = GTAOReconstructViewPositionNative(uvY, centerRaw);

    float mpp = 0.5 * (length(pX - centerPos) + length(pY - centerPos));
    return max(mpp, 1e-5);
}

float GTAOArcIntegral(float h, float n, float cosN, float sinN)
{
    return 0.25 * (-cos(2.0 * h - n) + cosN + 2.0 * h * sinN);
}

float GTAOComputeVisibility(float2 screenUV)
{
    if (!GTAOInputsReady() || !GTAOInsideFirestormWorld(screenUV))
        return 1.0;

    float2 nativeUV = GTAOFirestormUV(screenUV);
    float centerRaw = GTAORawDepthNative(nativeUV);

    if (GTAOIsBackgroundDepth(centerRaw))
        return 1.0;

    float3 centerPos = GTAOReconstructViewPositionNative(nativeUV, centerRaw);
    float centerDepth = max(-centerPos.z, 1e-4);
    float3 centerNormal = GTAONormalNative(nativeUV);
    float3 viewVec = normalize(-centerPos);

    float metersPerPixel = GTAOProjectedMetersPerPixel(nativeUV, centerRaw, centerPos);
    float radiusPixels = min(
        max(GTAORadius, 1e-4) / metersPerPixel,
        max(GTAOMaxRadiusPixels, 1.0));

    if (radiusPixels < 1.0)
        return 1.0;

    float2 nativeTexel = 1.0 / max(SLPrimaryDepthNativeSize, float2(1.0, 1.0));
    float visibilitySum = 0.0;
    int activeSlices = max(GTAOSliceCount, 1);
    int activeSteps = max(GTAOStepsPerSide, 1);

    [loop]
    for (int slice = 0; slice < SL_GTAO_MAX_SLICES; ++slice)
    {
        if (slice >= activeSlices)
            break;

        // [0, PI): each slice searches +dir and -dir, covering the full azimuth.
        float phi = ((float(slice) + 0.5) / float(activeSlices)) * SL_GTAO_PI;
        float2 dir2 = float2(cos(phi), sin(phi));

        // Derive the view-space tangent for this screen-space slice using the
        // exact inverse projection at the center depth.
        float2 tangentUV = clamp(
            nativeUV + dir2 * nativeTexel,
            nativeTexel,
            1.0 - nativeTexel);
        float3 tangentPoint = GTAOReconstructViewPositionNative(tangentUV, centerRaw);
        float3 tangentVS = tangentPoint - centerPos;
        tangentVS -= viewVec * dot(tangentVS, viewVec);
        float tangentLen2 = dot(tangentVS, tangentVS);

        if (tangentLen2 <= 1e-10)
        {
            visibilitySum += 1.0;
            continue;
        }

        tangentVS *= rsqrt(tangentLen2);
        float3 slicePlaneNormal = normalize(cross(tangentVS, viewVec));

        float3 projectedNormal = centerNormal -
            slicePlaneNormal * dot(centerNormal, slicePlaneNormal);
        float projectedLength = length(projectedNormal);

        if (projectedLength <= 1e-5)
        {
            // This slice carries effectively zero cosine weight.
            continue;
        }

        projectedNormal /= projectedLength;
        float cosN = saturate(dot(projectedNormal, viewVec));
        float signN = dot(projectedNormal, tangentVS) >= 0.0 ? 1.0 : -1.0;
        float n = signN * acos(cosN);
        float sinN = sin(n);

        // GTAO's unoccluded horizons are the projected normal's tangent
        // directions, not a fixed screen-space 90 degrees. This is essential
        // for tilted surfaces to integrate to unit visibility in empty space.
        float lowHorizonCosPos = cos(n + SL_GTAO_HALF_PI);
        float lowHorizonCosNeg = cos(n - SL_GTAO_HALF_PI);
        float horizonCosPos = lowHorizonCosPos;
        float horizonCosNeg = lowHorizonCosNeg;

        float rejectPos = GTAOImmediateDirectionalReject(
            nativeUV, dir2, centerDepth, centerNormal);
        float rejectNeg = GTAOImmediateDirectionalReject(
            nativeUV, -dir2, centerDepth, centerNormal);

        float3 biasedOrigin = centerPos + centerNormal * GTAOSurfaceBias;

        [loop]
        for (int step = 0; step < SL_GTAO_MAX_STEPS; ++step)
        {
            if (step >= activeSteps)
                break;

            float u = (float(step) + 1.0) / (float(activeSteps) + 1.0);
            // Quadratic distribution spends more samples in the near field.
            float sampleRadiusPixels = max(1.0, radiusPixels * u * u);

            [unroll]
            for (int side = 0; side < 2; ++side)
            {
                float sideSign = side == 0 ? 1.0 : -1.0;
                float directionalReject = side == 0 ? rejectPos : rejectNeg;

                // Hard silhouette stop is deliberately early. A large immediate
                // D0 discontinuity means the subsequent screen samples belong to
                // a different visible surface and must not create an AO halo.
                if (directionalReject >= 0.95)
                    continue;

                float2 sampleUV =
                    nativeUV + dir2 * sideSign * sampleRadiusPixels * nativeTexel;

                if (!GTAOInsideNativeUV(sampleUV))
                    continue;

                float sampleRaw = GTAORawDepthNative(sampleUV);
                if (GTAOIsBackgroundDepth(sampleRaw))
                    continue;

                float3 samplePos =
                    GTAOReconstructViewPositionNative(sampleUV, sampleRaw);
                float3 horizonVec = samplePos - biasedOrigin;
                float distanceVS = length(horizonVec);

                if (distanceVS <= max(GTAOSurfaceBias, 1e-5))
                    continue;

                float weight = GTAODistanceWeight(distanceVS);
                if (weight <= 0.0)
                    continue;

                // Soften only the transition into a detected silhouette. Values
                // below the hard stop can still contribute close to the center.
                weight *= 1.0 - saturate(directionalReject);

                float horizonCos = dot(horizonVec / distanceVS, viewVec);
                float lowHorizonCos = side == 0
                    ? lowHorizonCosPos
                    : lowHorizonCosNeg;
                float weightedHorizonCos = lerp(
                    lowHorizonCos, horizonCos, weight);

                if (side == 0)
                    horizonCosPos = max(horizonCosPos, weightedHorizonCos);
                else
                    horizonCosNeg = max(horizonCosNeg, weightedHorizonCos);
            }
        }

        // Signed horizon angles around the view vector.
        float h0 = -acos(clamp(horizonCosNeg, -1.0, 1.0));
        float h1 =  acos(clamp(horizonCosPos, -1.0, 1.0));

        // Clip to the projected normal's visible hemisphere.
        h0 = n + max(h0 - n, -SL_GTAO_HALF_PI);
        h1 = n + min(h1 - n,  SL_GTAO_HALF_PI);

        float sliceVisibility =
            projectedLength *
            (GTAOArcIntegral(h0, n, cosN, sinN) +
             GTAOArcIntegral(h1, n, cosN, sinN));

        visibilitySum += saturate(sliceVisibility);
    }

    return saturate(visibilitySum / float(activeSlices));
}

float4 GTAOEdgePS(float4 pos : SV_Position, float2 screenUV : TEXCOORD) : SV_Target
{
    if (!GTAOInputsReady() || !GTAOInsideFirestormWorld(screenUV))
        return float4(0.0, 0.0, 0.0, 1.0);

    float2 nativeUV = GTAOFirestormUV(screenUV);
    float centerRaw = GTAORawDepthNative(nativeUV);

    if (GTAOIsBackgroundDepth(centerRaw))
        return float4(0.0, 0.0, 0.0, 1.0);

    float3 centerPos = GTAOReconstructViewPositionNative(nativeUV, centerRaw);
    float centerDepth = max(-centerPos.z, 1e-4);
    float3 centerNormal = GTAONormalNative(nativeUV);
    float2 texel = 1.0 / max(SLPrimaryDepthNativeSize, float2(1.0, 1.0));

    float edge = 0.0;

    [unroll]
    for (int axis = 0; axis < 2; ++axis)
    {
        [unroll]
        for (int side = 0; side < 2; ++side)
        {
            float2 d = axis == 0 ? float2(texel.x, 0.0) : float2(0.0, texel.y);
            if (side != 0)
                d = -d;

            float2 sampleUV = nativeUV + d;

            if (!GTAOInsideNativeUV(sampleUV))
            {
                edge = 1.0;
                continue;
            }

            float raw = GTAORawDepthNative(sampleUV);
            if (GTAOIsBackgroundDepth(raw))
            {
                edge = 1.0;
                continue;
            }

            float depth = GTAOViewDepthNative(sampleUV, raw);
            float3 normal = GTAONormalNative(sampleUV);
            edge = max(edge, GTAOPairDiscontinuity(
                centerDepth, centerNormal, depth, normal));
        }
    }

    return float4(edge, 0.0, 0.0, 1.0);
}

float4 GTAORawPS(float4 pos : SV_Position, float2 screenUV : TEXCOORD) : SV_Target
{
    float visibility = GTAOComputeVisibility(screenUV);
    return float4(visibility, 0.0, 0.0, 1.0);
}

float GTAOBilateralWeight(
    float centerDepth,
    float3 centerNormal,
    float sampleDepth,
    float3 sampleNormal,
    float spatialDistance,
    float centerEdge,
    float sampleEdge)
{
    float sigmaSpatial = max(float(GTAODenoiseRadius) * 0.75, 0.75);
    float spatialW = exp(
        -0.5 * spatialDistance * spatialDistance /
        (sigmaSpatial * sigmaSpatial));

    float depthScale = max(
        GTAODenoiseDepthSigma * max(centerDepth, 0.25),
        1e-4);
    float depthW = exp(-abs(sampleDepth - centerDepth) / depthScale);

    float normalW = pow(
        saturate(dot(centerNormal, sampleNormal)),
        max(GTAODenoiseNormalPower, 1.0));

    float edgeW = saturate(
        1.0 - max(centerEdge, sampleEdge) * saturate(GTAODenoiseEdgeStop));

    return spatialW * depthW * normalW * edgeW;
}

float4 GTAOFilterHPS(float4 pos : SV_Position, float2 screenUV : TEXCOORD) : SV_Target
{
    float centerAO = tex2D(SLGTAORawSampler, screenUV).r;

    if (GTAOEnableDenoise == 0 ||
        !GTAOInputsReady() ||
        !GTAOInsideFirestormWorld(screenUV))
        return float4(centerAO, 0.0, 0.0, 1.0);

    float2 nativeUV = GTAOFirestormUV(screenUV);
    float centerRaw = GTAORawDepthNative(nativeUV);

    if (GTAOIsBackgroundDepth(centerRaw))
        return float4(1.0, 0.0, 0.0, 1.0);

    float centerDepth = GTAOViewDepthNative(nativeUV, centerRaw);
    float3 centerNormal = GTAONormalNative(nativeUV);
    float centerEdge = tex2D(SLGTAOEdgeSampler, screenUV).r;

    float sum = centerAO;
    float weightSum = 1.0;
    float2 screenTexel = 1.0 / float2(BUFFER_WIDTH, BUFFER_HEIGHT);

    [loop]
    for (int i = -SL_GTAO_MAX_FILTER_RADIUS; i <= SL_GTAO_MAX_FILTER_RADIUS; ++i)
    {
        if (i == 0 || i < -GTAODenoiseRadius || i > GTAODenoiseRadius)
            continue;

        float2 suv = screenUV + float2(float(i) * screenTexel.x, 0.0);
        if (!GTAOInsideFirestormWorld(suv))
            continue;

        float2 snuv = GTAOFirestormUV(suv);
        float sraw = GTAORawDepthNative(snuv);
        if (GTAOIsBackgroundDepth(sraw))
            continue;

        float sdepth = GTAOViewDepthNative(snuv, sraw);
        float3 snormal = GTAONormalNative(snuv);
        float sedge = tex2D(SLGTAOEdgeSampler, suv).r;
        float w = GTAOBilateralWeight(
            centerDepth, centerNormal, sdepth, snormal,
            abs(float(i)), centerEdge, sedge);

        sum += tex2D(SLGTAORawSampler, suv).r * w;
        weightSum += w;
    }

    return float4(sum / max(weightSum, 1e-5), 0.0, 0.0, 1.0);
}

float4 GTAOFilterVPS(float4 pos : SV_Position, float2 screenUV : TEXCOORD) : SV_Target
{
    float centerAO = tex2D(SLGTAOFilterHSampler, screenUV).r;

    if (GTAOEnableDenoise == 0 ||
        !GTAOInputsReady() ||
        !GTAOInsideFirestormWorld(screenUV))
        return float4(centerAO, 0.0, 0.0, 1.0);

    float2 nativeUV = GTAOFirestormUV(screenUV);
    float centerRaw = GTAORawDepthNative(nativeUV);

    if (GTAOIsBackgroundDepth(centerRaw))
        return float4(1.0, 0.0, 0.0, 1.0);

    float centerDepth = GTAOViewDepthNative(nativeUV, centerRaw);
    float3 centerNormal = GTAONormalNative(nativeUV);
    float centerEdge = tex2D(SLGTAOEdgeSampler, screenUV).r;

    float sum = centerAO;
    float weightSum = 1.0;
    float2 screenTexel = 1.0 / float2(BUFFER_WIDTH, BUFFER_HEIGHT);

    [loop]
    for (int i = -SL_GTAO_MAX_FILTER_RADIUS; i <= SL_GTAO_MAX_FILTER_RADIUS; ++i)
    {
        if (i == 0 || i < -GTAODenoiseRadius || i > GTAODenoiseRadius)
            continue;

        float2 suv = screenUV + float2(0.0, float(i) * screenTexel.y);
        if (!GTAOInsideFirestormWorld(suv))
            continue;

        float2 snuv = GTAOFirestormUV(suv);
        float sraw = GTAORawDepthNative(snuv);
        if (GTAOIsBackgroundDepth(sraw))
            continue;

        float sdepth = GTAOViewDepthNative(snuv, sraw);
        float3 snormal = GTAONormalNative(snuv);
        float sedge = tex2D(SLGTAOEdgeSampler, suv).r;
        float w = GTAOBilateralWeight(
            centerDepth, centerNormal, sdepth, snormal,
            abs(float(i)), centerEdge, sedge);

        sum += tex2D(SLGTAOFilterHSampler, suv).r * w;
        weightSum += w;
    }

    return float4(sum / max(weightSum, 1e-5), 0.0, 0.0, 1.0);
}

float4 GTAOCompositePS(float4 pos : SV_Position, float2 screenUV : TEXCOORD) : SV_Target
{
    float4 scene = tex2D(ReShade::BackBuffer, screenUV);

    if (GTAODisplayMode == 7)
        return scene;

    bool ready = GTAOInputsReady() && GTAOInsideFirestormWorld(screenUV);
    if (!ready)
    {
        if (GTAODisplayMode == 0)
            return scene;
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 nativeUV = GTAOFirestormUV(screenUV);
    float rawDepth = GTAORawDepthNative(nativeUV);
    bool geometry = !GTAOIsBackgroundDepth(rawDepth);

    if (GTAODisplayMode == 1)
    {
        float d = geometry ? GTAOViewDepthNative(nativeUV, rawDepth) : 0.0;
        return float4(GTAODepthViz(d).xxx, 1.0);
    }

    if (GTAODisplayMode == 2)
    {
        if (!geometry)
            return float4(0.0, 0.0, 0.0, 1.0);
        float3 n = GTAONormalNative(nativeUV);
        return float4(n * 0.5 + 0.5, 1.0);
    }

    float rawAO = tex2D(SLGTAORawSampler, screenUV).r;
    float filteredAO = tex2D(SLGTAOFilteredSampler, screenUV).r;

    if (GTAODisplayMode == 3)
        return float4(rawAO.xxx, 1.0);

    if (GTAODisplayMode == 4)
        return float4(filteredAO.xxx, 1.0);

    if (GTAODisplayMode == 5)
    {
        float reject = tex2D(SLGTAOEdgeSampler, screenUV).r;
        return float4(reject.xxx, 1.0);
    }

    float selectedAO = GTAOEnableDenoise != 0 ? filteredAO : rawAO;
    float finalAO = geometry
        ? saturate(1.0 - (1.0 - selectedAO) * max(GTAOStrength, 0.0))
        : 1.0;

    if (GTAODisplayMode == 6)
    {
        float contribution = 1.0 - finalAO;
        return float4(contribution.xxx, 1.0);
    }

    if (GTAOEnable == 0 || !geometry)
        return scene;

    return float4(scene.rgb * finalAO, scene.a);
}

technique SL_GTAO_v0_1_Reference
<
    ui_label = "GTAO - v0.1 Full-Res D0 Reference";
    ui_tooltip = "Standalone GTAO from visible native D0 + SL_NORMALS. No Dstatic, no SSR, no temporal. Bilateral denoise defaults OFF until raw GTAO is validated.";
>
{
    pass DepthDiscontinuity
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAOEdgePS;
        RenderTarget = SLGTAOEdgeTex;
    }

    pass RawGTAO
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAORawPS;
        RenderTarget = SLGTAORawTex;
    }

    pass BilateralHorizontal
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAOFilterHPS;
        RenderTarget = SLGTAOFilterHTex;
    }

    pass BilateralVertical
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAOFilterVPS;
        RenderTarget = SLGTAOFilteredTex;
    }

    pass CompositeAndDiagnostics
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAOCompositePS;
    }
}
