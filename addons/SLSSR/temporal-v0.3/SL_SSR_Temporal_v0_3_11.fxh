
float EvaluateHistoryGeometry(
    float2 uv,
    out float2 previousUV,
    out float depthAgreement,
    out float normalAgreement,
    out float motionPixels,
    out float rejectCode)
{
    previousUV = uv;
    depthAgreement = 0.0;
    normalAgreement = 0.0;
    motionPixels = 0.0;
    rejectCode = 0.0;

    if (!HasBridgeRegistration() || !HasExactMatrices() || !HasTemporalMotion())
    {
        rejectCode = 2.0;
        return 0.0;
    }

    if (!InsideTemporalEdge(uv))
    {
        rejectCode = 4.0;
        return 0.0;
    }

    float rawDepth = GetRawDepth(uv);
    if (IsBackgroundDepth(rawDepth))
    {
        rejectCode = 4.0;
        return 0.0;
    }

    float3 currentPos = ReconstructViewPosition(uv, rawDepth);
    float4 pp4 = MulInvModelviewDelta(float4(currentPos, 1.0));
    float sw = abs(pp4.w) > 1e-8 ? pp4.w : 1.0;
    float3 previousPos = pp4.xyz / sw;

    if (!ProjectViewPosition(previousPos, previousUV) || !InsideTemporalEdge(previousUV))
    {
        rejectCode = 4.0;
        return 0.0;
    }

    motionPixels = length(
        (previousUV - uv) *
        float2((float)BUFFER_WIDTH, (float)BUFFER_HEIGHT));

    float4 hg = tex2D(SLSSRHistoryGeomSampler, previousUV);
    float historyDepth = hg.a;
    if (historyDepth <= 1e-5)
    {
        rejectCode = 5.0;
        return 0.0;
    }

    float predictedDepth = max(-previousPos.z, 0.0);
    float depthError = abs(historyDepth - predictedDepth);
    float depthTolerance = max(
        SSRTemporalDepthTolerance,
        predictedDepth * 0.0035);

    depthAgreement =
        1.0 - smoothstep(depthTolerance, depthTolerance * 2.0, depthError);

    if (depthAgreement <= 0.02)
    {
        rejectCode = 5.0;
        return 0.0;
    }

    float3 previousNormal =
        MulInvModelviewDelta(float4(GetTransportNormal(uv), 0.0)).xyz;
    float nl = dot(previousNormal, previousNormal);
    if (nl <= 1e-8)
    {
        rejectCode = 6.0;
        return 0.0;
    }
    previousNormal *= rsqrt(nl);

    float nd = saturate(dot(previousNormal, DecodeHistoryNormal(hg.rgb)));
    float n1 = min(SSRTemporalNormalThreshold + 0.15, 0.999);
    normalAgreement = smoothstep(SSRTemporalNormalThreshold, n1, nd);

    if (normalAgreement <= 0.02)
    {
        rejectCode = 6.0;
        return 0.0;
    }

    return saturate(depthAgreement * normalAgreement);
}
