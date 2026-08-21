
TemporalMRT TemporalResolvePS(float4 pos : SV_Position, float2 uv : TEXCOORD)
{
    TemporalMRT o;

    float4 current = tex2D(SLSSRCurrentContributionSampler, uv);
    float3 resolved = current.rgb;

    float historyWeight = 0.0;
    float rejectCode = 0.0;
    float clampAmount = 0.0;
    float motionPixels = 0.0;
    float depthAgreement = 0.0;
    float normalAgreement = 0.0;
    float transitionMismatch = 0.0;
    float radianceDifference = 0.0;
    float unsupportedDifference = 0.0;
    float reactiveTrust = 0.0;

    bool forceReset =
        SSRTemporalEnable <= 0 ||
        SSRTemporalResetHistory > 0 ||
        SLSSRTemporalFrameIndex < 2;

    if (forceReset)
    {
        rejectCode = 1.0;
    }
    else if (!HasBridgeRegistration() || !HasExactMatrices() || !HasTemporalMotion())
    {
        rejectCode = 2.0;
    }
    else if (CameraDeltaMetric() > SSRTemporalCameraCutThreshold)
    {
        rejectCode = 3.0;
    }
    else
    {
        float2 previousUV;
        float geometryValidity = EvaluateHistoryGeometry(
            uv,
            previousUV,
            depthAgreement,
            normalAgreement,
            motionPixels,
            rejectCode);

        if (geometryValidity > 1e-4)
        {
            float4 historyCenter = tex2D(SLSSRHistorySampler, previousUV);

            bool currentValid =
                current.a > max(SSRTemporalContributionEpsilon, 1e-6);
            bool historyValid =
                historyCenter.a > max(SSRTemporalContributionEpsilon, 1e-6);

            // Do not resurrect a prior reflected hit after it disappears, and do
            // not import a no-hit history into a newly valid reflection.
            if (currentValid != historyValid)
            {
                transitionMismatch = 1.0;
                rejectCode = 7.0;
            }
            else if (currentValid)
            {
                // History jitter is intentionally hard-disabled. ReShade presentation
                // jitter was rejected in runtime testing; reprojection samples the exact
                // camera-reprojected history coordinate.
                float2 historyUV = previousUV;

                if (!InsideTemporalEdge(historyUV))
                {
                    rejectCode = 4.0;
                }
                else
                {
                    float4 history = tex2D(SLSSRHistorySampler, historyUV);
                    float3 historyBefore = history.rgb;

                    float3 lo, hi;
                    CurrentNeighborhoodEnvelope(uv, lo, hi);
                    history.rgb = clamp(history.rgb, lo, hi);

                    clampAmount =
                        length(historyBefore - history.rgb) /
                        max(length(historyBefore), 0.01);

                    radianceDifference =
                        NormalizedContributionDifference(historyBefore, current.rgb);

                    // The old AABB clamp can accept stale avatar colors that happen
                    // to lie inside per-channel min/max bounds. Measure whether the
                    // actual history RGB is supported by any real current 3x3 sample.
                    unsupportedDifference =
                        CurrentNeighborhoodNearestDifference(uv, historyBefore);

                    float rr0 = min(
                        SSRTemporalRadianceRejectStart,
                        SSRTemporalRadianceRejectEnd - 1e-3);
                    float rr1 = max(
                        SSRTemporalRadianceRejectEnd,
                        rr0 + 1e-3);

                    float radianceTrust =
                        1.0 - smoothstep(rr0, rr1, radianceDifference);

                    float clampTrust =
                        1.0 - smoothstep(0.08, 0.75, clampAmount);

                    float ar0 = min(
                        SSRTemporalReactiveRejectStart,
                        SSRTemporalReactiveRejectEnd - 1e-3);
                    float ar1 = max(
                        SSRTemporalReactiveRejectEnd,
                        ar0 + 1e-3);

                    reactiveTrust =
                        1.0 - smoothstep(ar0, ar1, unsupportedDifference);

                    float motionTrust =
                        1.0 - smoothstep(
                            SSRTemporalMotionStartPx,
                            max(SSRTemporalMotionEndPx,
                                SSRTemporalMotionStartPx + 0.01),
                            motionPixels);

                    if (radianceTrust <= 0.02 ||
                        clampTrust <= 0.02 ||
                        reactiveTrust <= 0.02)
                    {
                        rejectCode = 8.0;
                    }
                    else
                    {
                        historyWeight = saturate(
                            SSRTemporalHistoryWeight *
                            geometryValidity *
                            radianceTrust *
                            clampTrust *
                            reactiveTrust *
                            motionTrust);

                        resolved = lerp(current.rgb, history.rgb, historyWeight);
                    }
                }
            }
        }
    }

    o.color = float4(resolved, current.a);
    o.debug = float4(
        historyWeight,
        saturate(rejectCode / 8.0),
        saturate(clampAmount),
        saturate(motionPixels / 32.0));
    o.reactive = float4(
        transitionMismatch,
        saturate(radianceDifference),
        saturate(unsupportedDifference),
        saturate(reactiveTrust));

    return o;
}
