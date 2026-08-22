// SL_GTAO_v0_15_NativeAlphaDiagnostic.fx
// Correctness-first full-resolution GTAO for Firestorm + ReShade.
//
// Primary geometry depth: SL_DEPTH_PRIMARY_NATIVE (D0) only.
// Native normals:         SL_NORMALS (Firestorm stereographic XY encoding).
// Final application:      current ReShade backbuffer.
//
// No Dstatic, no SSR dependency, no temporal accumulation.
// Denoise is spatial bilateral only and defaults OFF so raw GTAO can be proven first.
// v0.15 diagnostic milestone: validated native alpha geometry is wired as a
// supplemental OCCLUDER path only. D0 remains the primary GTAO receiver/depth.
// Final composite remains the proven D0-only path until diagnostics are approved.
//
// Native alpha semantics:
//   SL_ALPHA_MATERIAL      binary Firestorm alpha/cutout geometry classification
//   SL_DEPTH_ALPHA_NATIVE  nearest eligible alpha/cutout fragment depth
//   SL_ALPHA_COVERAGE      authored alpha coverage (cutout survivor = 1)
//
// Coverage is applied to the alpha horizon candidate BEFORE the horizon max.
// No framebuffer-alpha, color, cloud, normal-payload, specular or depth-only
// classification heuristics are used.
// D0/normal semantic textures are used directly; no dependency on
// SLPrimaryDepthNativeValid or SLPrimaryDepthNativeSize advisory uniforms.

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
> = 0.50;

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
> = 0.35;

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
> = 160.0;

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
    ui_tooltip = "Relative view-depth discontinuity used to identify silhouette-like samples.";
    ui_type = "drag";
    ui_min = 0.001; ui_max = 0.25; ui_step = 0.001;
> = 0.025;

uniform float GTAOSilhouetteDepthAbsolute
<
    ui_label = "GTAO - Silhouette Absolute Depth";
    ui_tooltip = "Minimum view-space depth discontinuity used by silhouette rejection.";
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

uniform float GTAOSamplingJitter
<
    ui_label = "GTAO - Sampling Jitter";
    ui_tooltip = "Spatially rotates slice angles and jitters radial strata. 1.0 removes coherent spokes/rings; 0.0 restores the fixed reference pattern.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 1.0;

uniform float GTAOSilhouetteContactFraction
<
    ui_label = "GTAO - Silhouette Contact Fraction";
    ui_tooltip = "Depth discontinuities inside this fraction of Radius remain fully eligible so real contact AO survives.";
    ui_type = "drag";
    ui_min = 0.05; ui_max = 0.90; ui_step = 0.05;
> = 0.35;

uniform float GTAOSilhouetteFarReject
<
    ui_label = "GTAO - Far Silhouette Rejection";
    ui_tooltip = "Suppresses distant depth/normal discontinuities that otherwise behave like screen-space shadow casters.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
> = 0.90;

uniform float GTAOAlphaMaterialThreshold
<
    ui_label = "GTAO - Native Alpha Material Threshold";
    ui_tooltip = "SL_ALPHA_MATERIAL is validated binary classification; threshold is exposed only for inspection.";
    ui_type = "drag";
    ui_min = 0.01; ui_max = 0.99; ui_step = 0.01;
> = 0.50;

uniform float GTAOAlphaMinCoverage
<
    ui_label = "GTAO - Native Alpha Minimum Coverage";
    ui_tooltip = "Coverage below this value contributes no alpha blocker weight. Keep near zero while validating authored coverage.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.25; ui_step = 0.001;
> = 0.001;

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
        "Final AO composite (D0 baseline)\0"
        "Linear D0\0"
        "Decoded normals\0"
        "Native alpha material\0"
        "Native alpha coverage\0"
        "Native alpha depth\0"
        "GTAO alpha blocker weight\0"
        "GTAO raw AO before alpha-aware handling\0"
        "GTAO raw AO after alpha-aware handling\0"
        "Depth-discontinuity rejection (D0 baseline)\0"
        "Filtered GTAO (D0 baseline)\0"
        "Final AO contribution (D0 baseline)\0"
        "Passthrough\0";
> = 0;

texture SLGTAODepthTex : SL_DEPTH_PRIMARY_NATIVE;
texture SLGTAONormalsTex : SL_NORMALS;
texture SLGTAOAlphaMaterialTex : SL_ALPHA_MATERIAL;
texture SLGTAOAlphaDepthTex : SL_DEPTH_ALPHA_NATIVE;
texture SLGTAOAlphaCoverageTex : SL_ALPHA_COVERAGE;

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

sampler SLGTAOAlphaMaterialSampler
{
    Texture = SLGTAOAlphaMaterialTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLGTAOAlphaDepthSampler
{
    Texture = SLGTAOAlphaDepthTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

sampler SLGTAOAlphaCoverageSampler
{
    Texture = SLGTAOAlphaCoverageTex;
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

texture SLGTAORawAlphaAwareTex
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R16F;
};
sampler SLGTAORawAlphaAwareSampler
{
    Texture = SLGTAORawAlphaAwareTex;
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

float2 GTAONativeSize()
{
    // D0 and SL_NORMALS are native Firestorm viewport resources.
    // Runtime proof shows the semantic textures are bound even when the
    // SLPrimaryDepthNativeValid/Size advisory uniforms are not published.
    return max(SLBridgeViewport.zw, float2(1.0, 1.0));
}

bool GTAOInputsReady()
{
    return GTAOHasExactMatrices();
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

float GTAOAlphaMaterialNative(float2 nativeUV)
{
    return saturate(tex2D(SLGTAOAlphaMaterialSampler, nativeUV).r);
}

float GTAOAlphaCoverageNative(float2 nativeUV)
{
    return saturate(tex2D(SLGTAOAlphaCoverageSampler, nativeUV).r);
}

float GTAOAlphaRawDepthNative(float2 nativeUV)
{
    return tex2D(SLGTAOAlphaDepthSampler, nativeUV).r;
}

float GTAOAlphaVisibleGateNative(float2 nativeUV)
{
    float material = GTAOAlphaMaterialNative(nativeUV);
    float coverage = GTAOAlphaCoverageNative(nativeUV);
    float alphaRaw = GTAOAlphaRawDepthNative(nativeUV);

    if (material < GTAOAlphaMaterialThreshold)
        return 0.0;

    if (coverage < GTAOAlphaMinCoverage)
        return 0.0;

    if (GTAOIsBackgroundDepth(alphaRaw))
        return 0.0;

    float d0Raw = GTAORawDepthNative(nativeUV);
    if (!GTAOIsBackgroundDepth(d0Raw) &&
        alphaRaw > d0Raw + 2e-6)
        return 0.0;

    return 1.0;
}

float GTAOAlphaBlockerWeightNative(float2 nativeUV)
{
    float material =
        GTAOAlphaMaterialNative(nativeUV) >= GTAOAlphaMaterialThreshold
            ? 1.0
            : 0.0;

    float coverage = GTAOAlphaCoverageNative(nativeUV);
    float visible = GTAOAlphaVisibleGateNative(nativeUV);

    return saturate(material * coverage * visible);
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

float GTAOHash12(float2 p)
{
    // Stable per-native-pixel scalar noise. Spatial decorrelation is intentional:
    // there is no temporal accumulation in this milestone, so coherent bands are
    // worse than small high-frequency raw noise that the bilateral pass can remove.
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

float GTAOSilhouetteWeight(
    float centerDepth,
    float3 centerNormal,
    float sampleDepth,
    float3 sampleNormal,
    float distanceVS)
{
    float discontinuity = GTAOPairDiscontinuity(
        centerDepth, centerNormal, sampleDepth, sampleNormal);

    float radius = max(GTAORadius, 1e-4);
    float contactDistance =
        saturate(GTAOSilhouetteContactFraction) * radius;

    // Near-contact discontinuities are legitimate AO (floor/wall, object/floor).
    // Only transition toward rejection once the discontinuity is spatially far
    // enough to look like an unrelated screen-space silhouette.
    float farFactor = smoothstep(
        contactDistance,
        radius,
        saturate(distanceVS / radius) * radius);

    return 1.0 - saturate(discontinuity * farFactor * GTAOSilhouetteFarReject);
}

float GTAOSilhouetteWeightDepthOnly(
    float centerDepth,
    float sampleDepth,
    float distanceVS)
{
    float threshold = max(
        GTAOSilhouetteDepthAbsolute,
        max(centerDepth, 0.25) * GTAOSilhouetteDepthRelative);

    float discontinuity = smoothstep(
        threshold,
        threshold * 2.0,
        abs(sampleDepth - centerDepth));

    float radius = max(GTAORadius, 1e-4);
    float contactDistance =
        saturate(GTAOSilhouetteContactFraction) * radius;

    float farFactor = smoothstep(
        contactDistance,
        radius,
        saturate(distanceVS / radius) * radius);

    return 1.0 - saturate(
        discontinuity * farFactor * GTAOSilhouetteFarReject);
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
    float2 texel = 1.0 / GTAONativeSize();
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

