// -----------------------------------------------------------------------------
// Existing Firestorm / SLProbeLighting bridge state.
// -----------------------------------------------------------------------------
uniform float4 SLBridgeViewport = float4(0.0, 0.0, 1.0, 1.0);
uniform float4 SLBridgeBufferInfo = float4(1.0, 1.0, 1.0, 1.0);
uniform float SLBridgeRegistrationValid = 0.0;

uniform float4 SLGIInvProjC0 = 0.0;
uniform float4 SLGIInvProjC1 = 0.0;
uniform float4 SLGIInvProjC2 = 0.0;
uniform float4 SLGIInvProjC3 = 0.0;
uniform float4 SLGIProjC0 = 0.0;
uniform float4 SLGIProjC1 = 0.0;
uniform float4 SLGIProjC2 = 0.0;
uniform float4 SLGIProjC3 = 0.0;
uniform float SLGIProjectionValid = 0.0;
uniform float SLProbeNativeValid = 0.0;

uniform float4 SLGIInvModelviewDeltaC0 = 0.0;
uniform float4 SLGIInvModelviewDeltaC1 = 0.0;
uniform float4 SLGIInvModelviewDeltaC2 = 0.0;
uniform float4 SLGIInvModelviewDeltaC3 = 0.0;
uniform float SLGIMotionValid = 0.0;

uniform int SLSSRTemporalFrameIndex < source = "framecount"; >;

// Current D0 and receiver normals from the existing native bridge. No object-motion vectors are invented.
texture SLPrimaryDepthTex : SL_DEPTH_PRIMARY_NATIVE;
texture SLNativeNormalsTex : SL_NORMALS;

sampler SLPrimaryDepthSampler
{
    Texture = SLPrimaryDepthTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = POINT;
};

sampler SLNativeNormalsSampler
{
    Texture = SLNativeNormalsTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = POINT;
};
