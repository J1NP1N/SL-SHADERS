
bool HasTemporalMotion()
{
    float e =
        dot(abs(SLGIInvModelviewDeltaC0), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC1), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC2), 1.0) +
        dot(abs(SLGIInvModelviewDeltaC3), 1.0);

    return SLGIMotionValid > 0.5 && e > 0.01;
}

float2 FirestormUV(float2 screenUV)
{
    if (!HasBridgeRegistration())
        return float2(-2.0, -2.0);

    float2 windowPxGL =
        float2(screenUV.x * SLBridgeBufferInfo.x,
               (1.0 - screenUV.y) * SLBridgeBufferInfo.y);

    return (windowPxGL - SLBridgeViewport.xy) / SLBridgeViewport.zw;
}

float2 ScreenUVFromFirestormUV(float2 nativeUV)
{
    float2 windowPxGL = SLBridgeViewport.xy + nativeUV * SLBridgeViewport.zw;
    return float2(
        windowPxGL.x / SLBridgeBufferInfo.x,
        1.0 - windowPxGL.y / SLBridgeBufferInfo.y);
}

bool InsideFirestormWorld(float2 screenUV)
{
    float2 uv = FirestormUV(screenUV);
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

bool InsideTemporalEdge(float2 uv)
{
    float2 margin = float2(
        SSRTemporalEdgeMarginPx / max((float)BUFFER_WIDTH, 1.0),
        SSRTemporalEdgeMarginPx / max((float)BUFFER_HEIGHT, 1.0));

    return uv.x > margin.x && uv.x < 1.0 - margin.x &&
           uv.y > margin.y && uv.y < 1.0 - margin.y &&
           InsideFirestormWorld(uv);
}

float4 MulInvProj(float4 v)
{
    return SLGIInvProjC0 * v.x +
           SLGIInvProjC1 * v.y +
           SLGIInvProjC2 * v.z +
           SLGIInvProjC3 * v.w;
}

float4 MulProj(float4 v)
{
    return SLGIProjC0 * v.x +
           SLGIProjC1 * v.y +
           SLGIProjC2 * v.z +
           SLGIProjC3 * v.w;
}

float4 MulInvModelviewDelta(float4 v)
{
    return SLGIInvModelviewDeltaC0 * v.x +
           SLGIInvModelviewDeltaC1 * v.y +
           SLGIInvModelviewDeltaC2 * v.z +
           SLGIInvModelviewDeltaC3 * v.w;
}
