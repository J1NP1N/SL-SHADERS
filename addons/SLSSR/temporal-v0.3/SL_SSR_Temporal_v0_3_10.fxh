
// -----------------------------------------------------------------------------
// History geometry and reprojection.
// Rejection codes:
//   0 accepted/no history needed
//   1 reset/disabled/first frames
//   2 bridge or motion unavailable
//   3 camera cut / excessive camera delta
//   4 screen edge / reprojection / invalid receiver
//   5 depth mismatch / disocclusion
//   6 normal mismatch
//   7 invalid hit transition
//   8 radiance/clamp/unsupported-content reactive rejection
// -----------------------------------------------------------------------------
float3 EncodeHistoryNormal(float3 n)
{
    return saturate(n * 0.5 + 0.5);
}

float3 DecodeHistoryNormal(float3 e)
{
    float3 n = e * 2.0 - 1.0;
    float l = dot(n, n);
    return l > 1e-8 ? n * rsqrt(l) : float3(0.0, 0.0, 1.0);
}

float4 CurrentHistoryGeometry(float2 uv)
{
    if (!HasBridgeRegistration() || !HasExactMatrices() || !InsideFirestormWorld(uv))
        return 0.0;

    float rawDepth = GetRawDepth(uv);
    if (IsBackgroundDepth(rawDepth))
        return 0.0;

    float3 p = ReconstructViewPosition(uv, rawDepth);
    float linearDepth = max(-p.z, 0.0);
    if (linearDepth <= 1e-5)
        return 0.0;

    return float4(EncodeHistoryNormal(GetTransportNormal(uv)), linearDepth);
}
