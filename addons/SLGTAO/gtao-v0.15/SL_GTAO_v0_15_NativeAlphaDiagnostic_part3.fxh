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
    float2 texel = 1.0 / GTAONativeSize();

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

float4 GTAORawAlphaAwarePS(
    float4 pos : SV_Position,
    float2 screenUV : TEXCOORD) : SV_Target
{
    float visibility = GTAOComputeVisibilityAlphaAware(screenUV);
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

