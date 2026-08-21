
// -----------------------------------------------------------------------------
// Half-resolution temporal storage retained from the validated v0.2 wrapper architecture.
// -----------------------------------------------------------------------------
texture SLSSRPreCaptureTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRPreCaptureSampler
{
    Texture = SLSSRPreCaptureTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRCurrentContributionTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRCurrentContributionSampler
{
    Texture = SLSSRCurrentContributionTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};
sampler SLSSRCurrentContributionPointSampler
{
    Texture = SLSSRCurrentContributionTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = POINT; MagFilter = POINT; MipFilter = POINT;
};

texture SLSSRTemporalTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRTemporalSampler
{
    Texture = SLSSRTemporalTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRTemporalDebugTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
sampler SLSSRTemporalDebugSampler
{
    Texture = SLSSRTemporalDebugTex;
    AddressU = CLAMP; AddressV = CLAMP;
    MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = POINT;
};

texture SLSSRTemporalReactiveDebugTex
{
    Width = BUFFER_WIDTH / 2;
    Height = BUFFER_HEIGHT / 2;
    Format = RGBA16F;
};
