
float4 TemporalCompositeCorrectionPS(
    float4 pos : SV_Position,
    float2 uv : TEXCOORD) : SV_Target
{
    float4 color = tex2D(ReShade::BackBuffer, uv);

    float4 current = tex2D(SLSSRCurrentContributionSampler, uv);
    float4 temporal = tex2D(SLSSRTemporalSampler, uv);
    float4 debug = tex2D(SLSSRTemporalDebugSampler, uv);
    float4 reactiveDebug = tex2D(SLSSRTemporalReactiveDebugSampler, uv);

    if (SSRTemporalDisplayMode == 1)
        return float4(saturate(abs(current.rgb) * SSRTemporalDebugGain), 1.0);

    if (SSRTemporalDisplayMode == 2)
        return float4(saturate(abs(temporal.rgb) * SSRTemporalDebugGain), 1.0);

    if (SSRTemporalDisplayMode == 3)
        return float4(debug.r.xxx, 1.0);

    if (SSRTemporalDisplayMode == 4)
    {
        float code = floor(debug.g * 8.0 + 0.5);
        return float4(RejectionColor(code), 1.0);
    }

    if (SSRTemporalDisplayMode == 5)
        return float4(debug.a.xxx, 1.0);

    if (SSRTemporalDisplayMode == 6 ||
        SSRTemporalDisplayMode == 7)
    {
        float2 previousUV;
        float depthAgreement;
        float normalAgreement;
        float motionPixels;
        float rejectCode;

        EvaluateHistoryGeometry(
            uv,
            previousUV,
            depthAgreement,
            normalAgreement,
            motionPixels,
            rejectCode);

        float v =
            SSRTemporalDisplayMode == 6 ?
            depthAgreement : normalAgreement;

        return float4(v.xxx, 1.0);
    }

    if (SSRTemporalDisplayMode == 8)
        return float4(debug.b.xxx, 1.0);

    if (SSRTemporalDisplayMode == 9)
    {
        float cut =
            HasTemporalMotion() &&
            CameraDeltaMetric() <= SSRTemporalCameraCutThreshold ?
            0.0 : 1.0;

        return float4(cut, 1.0 - cut, 0.0, 1.0);
    }

    if (SSRTemporalDisplayMode == 10)
        return float4(0.0, 0.0, 0.0, 1.0);

    float3 correction = temporal.rgb - current.rgb;

    if (SSRTemporalDisplayMode == 11)
        return float4(saturate(abs(correction) * SSRTemporalDebugGain), 1.0);

    if (SSRTemporalDisplayMode == 12)
        return float4(reactiveDebug.rgb, 1.0);

    if (SSRTemporalDisplayMode == 13)
        return float4(reactiveDebug.a.xxx, 1.0);

    if (SSRTemporalEnable <= 0)
        return color;

    color.rgb = max(color.rgb + correction, 0.0);
    return color;
}
