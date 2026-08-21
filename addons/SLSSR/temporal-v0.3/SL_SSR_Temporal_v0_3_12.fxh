
void ExpandEnvelope(float3 s, inout float3 lo, inout float3 hi)
{
    lo = min(lo, s);
    hi = max(hi, s);
}

void CurrentNeighborhoodEnvelope(float2 uv, out float3 lo, out float3 hi)
{
    float2 px = float2(
        2.0 / (float)BUFFER_WIDTH,
        2.0 / (float)BUFFER_HEIGHT);

    float3 c = tex2D(SLSSRCurrentContributionSampler, uv).rgb;
    lo = c;
    hi = c;

    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2( px.x, 0.0)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(-px.x, 0.0)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(0.0,  px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(0.0, -px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2( px.x,  px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(-px.x,  px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2( px.x, -px.y)).rgb, lo, hi);
    ExpandEnvelope(tex2D(SLSSRCurrentContributionSampler, uv + float2(-px.x, -px.y)).rgb, lo, hi);

    float3 span = hi - lo;
    float peak = max(
        max(max(abs(lo.r), abs(lo.g)), abs(lo.b)),
        max(max(abs(hi.r), abs(hi.g)), abs(hi.b)));

    float floorPad = max(0.0010, peak * 0.05);
    float3 pad = max(span * SSRTemporalClampExpansion, floorPad.xxx);

    lo -= pad;
    hi += pad;
}

float NormalizedContributionDifference(float3 a, float3 b)
{
    return saturate(length(a - b) / max(length(a) + length(b), 0.02));
}
