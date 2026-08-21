sampler SLSSRTemporalReactiveDebugSampler
{
    Texture = SLSSRTemporalReactiveDebugTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRHistoryTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRHistorySampler
{
    Texture = SLSSRHistoryTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRHistoryGeomTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRHistoryGeomSampler
{
    Texture = SLSSRHistoryGeomTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

// -----------------------------------------------------------------------------
// Firestorm bridge helpers. These match the proven HybridGI temporal contract.
// -----------------------------------------------------------------------------
bool HasBridgeRegistration()
{
    return SLBridgeRegistrationValid > 0.5 &&
           SLBridgeViewport.z > 1.0 && SLBridgeViewport.w > 1.0 &&
           SLBridgeBufferInfo.x > 1.0 && SLBridgeBufferInfo.y > 1.0;
}

bool HasExactMatrices()
{
    float invEnergy =
        dot(abs(SLGIInvProjC0), 1.0) + dot(abs(SLGIInvProjC1), 1.0) +
        dot(abs(SLGIInvProjC2), 1.0) + dot(abs(SLGIInvProjC3), 1.0);
    float projEnergy =
        dot(abs(SLGIProjC0), 1.0) + dot(abs(SLGIProjC1), 1.0) +
        dot(abs(SLGIProjC2), 1.0) + dot(abs(SLGIProjC3), 1.0);

    return HasBridgeRegistration() &&
           SLGIProjectionValid > 0.5 &&
           SLProbeNativeValid > 0.5 &&
           invEnergy > 0.01 && projEnergy > 0.01;
}
