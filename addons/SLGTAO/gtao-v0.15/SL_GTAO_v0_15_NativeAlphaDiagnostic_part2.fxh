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

    float2 nativeSize = GTAONativeSize();
    float2 nativeTexel = 1.0 / nativeSize;
    float2 nativePixel = floor(nativeUV * nativeSize);

    float jitterAmount = saturate(GTAOSamplingJitter);
    float sliceRotationNoise = GTAOHash12(nativePixel + float2(17.0, 59.0));
    float slicePhase = lerp(0.5, sliceRotationNoise, jitterAmount);

    float visibilitySum = 0.0;
    int activeSlices = min(max(GTAOSliceCount, 1), SL_GTAO_MAX_SLICES);
    int activeSteps = min(max(GTAOStepsPerSide, 1), SL_GTAO_MAX_STEPS);

    [loop]
    for (int slice = 0; slice < SL_GTAO_MAX_SLICES; ++slice)
    {
        if (slice >= activeSlices)
            break;

        float phi =
            ((float(slice) + slicePhase) / float(activeSlices)) *
            SL_GTAO_PI;
        float2 dir2 = float2(cos(phi), sin(phi));

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
            continue;

        projectedNormal /= projectedLength;
        float cosN = saturate(dot(projectedNormal, viewVec));
        float signN = dot(projectedNormal, tangentVS) >= 0.0 ? 1.0 : -1.0;
        float n = signN * acos(cosN);
        float sinN = sin(n);

        float lowHorizonCosPos = cos(n + SL_GTAO_HALF_PI);
        float lowHorizonCosNeg = cos(n - SL_GTAO_HALF_PI);
        float horizonCosPos = lowHorizonCosPos;
        float horizonCosNeg = lowHorizonCosNeg;

        float3 biasedOrigin = centerPos + centerNormal * GTAOSurfaceBias;

        [loop]
        for (int step = 0; step < SL_GTAO_MAX_STEPS; ++step)
        {
            if (step >= activeSteps)
                break;

            [unroll]
            for (int side = 0; side < 2; ++side)
            {
                float sideSign = side == 0 ? 1.0 : -1.0;
                float radialNoise = GTAOHash12(
                    nativePixel +
                    float2(
                        float(slice * 37 + side * 101 + 11),
                        float(step * 53 + side * 19 + 7)));

                float radialPhase = lerp(1.0, 0.25 + 0.75 * radialNoise, jitterAmount);
                float u =
                    (float(step) + radialPhase) /
                    float(activeSteps);
                u = saturate(u);

                float sampleRadiusPixels =
                    max(1.0, radiusPixels * u * u);

                float2 sampleUV =
                    nativeUV +
                    dir2 * sideSign *
                    sampleRadiusPixels * nativeTexel;

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

                float sampleDepth = max(-samplePos.z, 1e-4);
                float3 sampleNormal = GTAONormalNative(sampleUV);

                weight *= GTAOSilhouetteWeight(
                    centerDepth,
                    centerNormal,
                    sampleDepth,
                    sampleNormal,
                    distanceVS);

                if (weight <= 0.0)
                    continue;

                float horizonCos =
                    dot(horizonVec / distanceVS, viewVec);

                float lowHorizonCos =
                    side == 0
                        ? lowHorizonCosPos
                        : lowHorizonCosNeg;

                float weightedHorizonCos =
                    lerp(lowHorizonCos, horizonCos, weight);

                if (side == 0)
                    horizonCosPos =
                        max(horizonCosPos, weightedHorizonCos);
                else
                    horizonCosNeg =
                        max(horizonCosNeg, weightedHorizonCos);
            }
        }

        float h0 =
            -acos(clamp(horizonCosNeg, -1.0, 1.0));
        float h1 =
             acos(clamp(horizonCosPos, -1.0, 1.0));

        h0 = n + max(h0 - n, -SL_GTAO_HALF_PI);
        h1 = n + min(h1 - n,  SL_GTAO_HALF_PI);

        float sliceVisibility =
            projectedLength *
            (GTAOArcIntegral(h0, n, cosN, sinN) +
             GTAOArcIntegral(h1, n, cosN, sinN));

        visibilitySum += sliceVisibility;
    }

    return saturate(
        visibilitySum / float(activeSlices));
}

float GTAOComputeVisibilityAlphaAware(float2 screenUV)
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

    float2 nativeSize = GTAONativeSize();
    float2 nativeTexel = 1.0 / nativeSize;
    float2 nativePixel = floor(nativeUV * nativeSize);

    float jitterAmount = saturate(GTAOSamplingJitter);
    float sliceRotationNoise = GTAOHash12(nativePixel + float2(17.0, 59.0));
    float slicePhase = lerp(0.5, sliceRotationNoise, jitterAmount);

    float visibilitySum = 0.0;
    int activeSlices = min(max(GTAOSliceCount, 1), SL_GTAO_MAX_SLICES);
    int activeSteps = min(max(GTAOStepsPerSide, 1), SL_GTAO_MAX_STEPS);

    [loop]
    for (int slice = 0; slice < SL_GTAO_MAX_SLICES; ++slice)
    {
        if (slice >= activeSlices)
            break;

        float phi =
            ((float(slice) + slicePhase) / float(activeSlices)) *
            SL_GTAO_PI;
        float2 dir2 = float2(cos(phi), sin(phi));

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
            continue;

        projectedNormal /= projectedLength;
        float cosN = saturate(dot(projectedNormal, viewVec));
        float signN = dot(projectedNormal, tangentVS) >= 0.0 ? 1.0 : -1.0;
        float n = signN * acos(cosN);
        float sinN = sin(n);

        float lowHorizonCosPos = cos(n + SL_GTAO_HALF_PI);
        float lowHorizonCosNeg = cos(n - SL_GTAO_HALF_PI);
        float horizonCosPos = lowHorizonCosPos;
        float horizonCosNeg = lowHorizonCosNeg;

        float3 biasedOrigin = centerPos + centerNormal * GTAOSurfaceBias;

        [loop]
        for (int step = 0; step < SL_GTAO_MAX_STEPS; ++step)
        {
            if (step >= activeSteps)
                break;

            [unroll]
            for (int side = 0; side < 2; ++side)
            {
                float sideSign = side == 0 ? 1.0 : -1.0;
                float radialNoise = GTAOHash12(
                    nativePixel +
                    float2(
                        float(slice * 37 + side * 101 + 11),
                        float(step * 53 + side * 19 + 7)));

                float radialPhase = lerp(1.0, 0.25 + 0.75 * radialNoise, jitterAmount);
                float u =
                    (float(step) + radialPhase) /
                    float(activeSteps);
                u = saturate(u);

                float sampleRadiusPixels =
                    max(1.0, radiusPixels * u * u);

                float2 sampleUV =
                    nativeUV +
                    dir2 * sideSign *
                    sampleRadiusPixels * nativeTexel;

                if (!GTAOInsideNativeUV(sampleUV))
                    continue;

                float lowHorizonCos =
                    side == 0
                        ? lowHorizonCosPos
                        : lowHorizonCosNeg;

                float sampleRaw = GTAORawDepthNative(sampleUV);
                if (!GTAOIsBackgroundDepth(sampleRaw))
                {
                    float3 samplePos =
                        GTAOReconstructViewPositionNative(sampleUV, sampleRaw);
                    float3 horizonVec = samplePos - biasedOrigin;
                    float distanceVS = length(horizonVec);

                    if (distanceVS > max(GTAOSurfaceBias, 1e-5))
                    {
                        float weight = GTAODistanceWeight(distanceVS);

                        if (weight > 0.0)
                        {
                            float sampleDepth = max(-samplePos.z, 1e-4);
                            float3 sampleNormal = GTAONormalNative(sampleUV);

                            weight *= GTAOSilhouetteWeight(
                                centerDepth,
                                centerNormal,
                                sampleDepth,
                                sampleNormal,
                                distanceVS);

                            if (weight > 0.0)
                            {
                                float horizonCos =
                                    dot(horizonVec / distanceVS, viewVec);
                                float weightedHorizonCos =
                                    lerp(lowHorizonCos, horizonCos, weight);

                                if (side == 0)
                                    horizonCosPos =
                                        max(horizonCosPos, weightedHorizonCos);
                                else
                                    horizonCosNeg =
                                        max(horizonCosNeg, weightedHorizonCos);
                            }
                        }
                    }
                }

                float alphaBlockerWeight =
                    GTAOAlphaBlockerWeightNative(sampleUV);

                if (alphaBlockerWeight > 0.0)
                {
                    float alphaRaw = GTAOAlphaRawDepthNative(sampleUV);
                    float3 alphaPos =
                        GTAOReconstructViewPositionNative(sampleUV, alphaRaw);
                    float3 alphaHorizonVec = alphaPos - biasedOrigin;
                    float alphaDistanceVS = length(alphaHorizonVec);

                    if (alphaDistanceVS > max(GTAOSurfaceBias, 1e-5))
                    {
                        float alphaWeight =
                            GTAODistanceWeight(alphaDistanceVS) *
                            alphaBlockerWeight;

                        if (alphaWeight > 0.0)
                        {
                            float alphaDepth = max(-alphaPos.z, 1e-4);

                            alphaWeight *= GTAOSilhouetteWeightDepthOnly(
                                centerDepth,
                                alphaDepth,
                                alphaDistanceVS);

                            if (alphaWeight > 0.0)
                            {
                                float alphaHorizonCos =
                                    dot(alphaHorizonVec / alphaDistanceVS, viewVec);
                                float weightedAlphaHorizonCos =
                                    lerp(lowHorizonCos, alphaHorizonCos, alphaWeight);

                                if (side == 0)
                                    horizonCosPos =
                                        max(horizonCosPos, weightedAlphaHorizonCos);
                                else
                                    horizonCosNeg =
                                        max(horizonCosNeg, weightedAlphaHorizonCos);
                            }
                        }
                    }
                }
            }
        }

        float h0 =
            -acos(clamp(horizonCosNeg, -1.0, 1.0));
        float h1 =
             acos(clamp(horizonCosPos, -1.0, 1.0));

        h0 = n + max(h0 - n, -SL_GTAO_HALF_PI);
        h1 = n + min(h1 - n,  SL_GTAO_HALF_PI);

        float sliceVisibility =
            projectedLength *
            (GTAOArcIntegral(h0, n, cosN, sinN) +
             GTAOArcIntegral(h1, n, cosN, sinN));

        visibilitySum += sliceVisibility;
    }

    return saturate(
        visibilitySum / float(activeSlices));
}

