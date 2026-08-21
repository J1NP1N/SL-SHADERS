
float CameraDeltaMetric()
{
    float4 e0 = abs(SLGIInvModelviewDeltaC0 - float4(1.0, 0.0, 0.0, 0.0));
    float4 e1 = abs(SLGIInvModelviewDeltaC1 - float4(0.0, 1.0, 0.0, 0.0));
    float4 e2 = abs(SLGIInvModelviewDeltaC2 - float4(0.0, 0.0, 1.0, 0.0));
    float4 e3 = abs(SLGIInvModelviewDeltaC3 - float4(0.0, 0.0, 0.0, 1.0));

    float m0 = max(max(e0.x, e0.y), max(e0.z, e0.w));
    float m1 = max(max(e1.x, e1.y), max(e1.z, e1.w));
    float m2 = max(max(e2.x, e2.y), max(e2.z, e2.w));
    float m3 = max(max(e3.x, e3.y), max(e3.z, e3.w));

    return max(max(m0, m1), max(m2, m3));
}

// -----------------------------------------------------------------------------
// Current SSR contribution capture.
// -----------------------------------------------------------------------------
float ContributionEnergy(float3 delta)
{
    float3 a = abs(delta);
    return max(a.r, max(a.g, a.b));
}

float4 CaptureBeforeSSRPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return float4(tex2D(ReShade::BackBuffer, uv).rgb, 1.0);
}

float4 CurrentSSRContributionPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 before = tex2D(SLSSRPreCaptureSampler, uv).rgb;
    float3 after = tex2D(ReShade::BackBuffer, uv).rgb;
    float3 delta = after - before;
    return float4(delta, ContributionEnergy(delta));
}
