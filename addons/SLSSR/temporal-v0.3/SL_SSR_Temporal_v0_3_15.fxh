
float4 CopyTemporalHistoryPS(
    float4 pos : SV_Position,
    float2 uv : TEXCOORD) : SV_Target
{
    float4 temporal = tex2D(SLSSRTemporalSampler, uv);
    float4 current = tex2D(SLSSRCurrentContributionSampler, uv);
    return float4(temporal.rgb, current.a);
}

float4 StoreHistoryGeometryPS(
    float4 pos : SV_Position,
    float2 uv : TEXCOORD) : SV_Target
{
    return CurrentHistoryGeometry(uv);
}

float3 RejectionColor(float code)
{
    if (code < 0.5) return float3(0.0, 0.65, 0.0);
    if (code < 1.5) return float3(0.25, 0.25, 0.25);
    if (code < 2.5) return float3(1.0, 0.0, 1.0);
    if (code < 3.5) return float3(1.0, 0.5, 0.0);
    if (code < 4.5) return float3(0.0, 0.5, 1.0);
    if (code < 5.5) return float3(1.0, 0.0, 0.0);
    if (code < 6.5) return float3(0.9, 0.9, 0.0);
    if (code < 7.5) return float3(0.0, 1.0, 1.0);
    return float3(1.0, 0.25, 0.25);
}
