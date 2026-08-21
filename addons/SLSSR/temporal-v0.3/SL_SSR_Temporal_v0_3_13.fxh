
float CurrentNeighborhoodNearestDifference(float2 uv, float3 historyRGB)
{
    float2 px = float2(
        2.0 / (float)BUFFER_WIDTH,
        2.0 / (float)BUFFER_HEIGHT);

    float nearest = NormalizedContributionDifference(
        historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv).rgb);

    nearest = min(nearest, NormalizedContributionDifference(historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv + float2( px.x, 0.0)).rgb));
    nearest = min(nearest, NormalizedContributionDifference(historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv + float2(-px.x, 0.0)).rgb));
    nearest = min(nearest, NormalizedContributionDifference(historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv + float2(0.0,  px.y)).rgb));
    nearest = min(nearest, NormalizedContributionDifference(historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv + float2(0.0, -px.y)).rgb));
    nearest = min(nearest, NormalizedContributionDifference(historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv + float2( px.x,  px.y)).rgb));
    nearest = min(nearest, NormalizedContributionDifference(historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv + float2(-px.x,  px.y)).rgb));
    nearest = min(nearest, NormalizedContributionDifference(historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv + float2( px.x, -px.y)).rgb));
    nearest = min(nearest, NormalizedContributionDifference(historyRGB, tex2D(SLSSRCurrentContributionPointSampler, uv + float2(-px.x, -px.y)).rgb));

    return saturate(nearest);
}

struct TemporalMRT
{
    float4 color : SV_Target0;
    float4 debug : SV_Target1;
    float4 reactive : SV_Target2;
};
