
float GetRawDepth(float2 screenUV)
{
    return tex2D(SLPrimaryDepthSampler, FirestormUV(screenUV)).r;
}

float4 GetRawNormalData(float2 screenUV)
{
    return tex2D(SLNativeNormalsSampler, FirestormUV(screenUV));
}

bool IsBackgroundDepth(float d)
{
    return d >= 0.999999;
}

float3 DecodeFirestormNormalRaw(float4 encodedNormal)
{
    float2 fenc = encodedNormal.xy * 4.0 - 2.0;
    float f = dot(fenc, fenc);
    float g = sqrt(saturate(1.0 - f * 0.25));

    float3 n;
    n.xy = fenc * g;
    n.z = 1.0 - f * 0.5;

    float len2 = dot(n, n);
    return len2 > 1e-8 ? n * rsqrt(len2) : float3(0.0, 0.0, 1.0);
}

float3 GetTransportNormal(float2 uv)
{
    return DecodeFirestormNormalRaw(GetRawNormalData(uv));
}

float3 ReconstructViewPosition(float2 screenUV, float rawDepth)
{
    float2 nativeUV = FirestormUV(screenUV);
    float4 p = MulInvProj(float4(
        nativeUV * 2.0 - 1.0,
        rawDepth * 2.0 - 1.0,
        1.0));

    float safeW = abs(p.w) > 1e-8 ? p.w : (p.w < 0.0 ? -1e-8 : 1e-8);
    return p.xyz / safeW;
}

bool ProjectViewPosition(float3 viewPos, out float2 screenUV)
{
    float4 clip = MulProj(float4(viewPos, 1.0));
    if (abs(clip.w) <= 1e-8)
    {
        screenUV = 0.0;
        return false;
    }

    float2 nativeUV = (clip.xy / clip.w) * 0.5 + 0.5;
    if (nativeUV.x <= 0.0 || nativeUV.x >= 1.0 ||
        nativeUV.y <= 0.0 || nativeUV.y >= 1.0)
    {
        screenUV = 0.0;
        return false;
    }

    screenUV = ScreenUVFromFirestormUV(nativeUV);
    return InsideFirestormWorld(screenUV);
}
