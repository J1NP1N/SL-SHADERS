// SL_SSR_Temporal_v0_1.fx
// Standalone temporal SSR consumer for SL SSR v0.35 Legacy Resolve.
// Requires SLSSRTemporalLink.addon to bind v0.35 resolved/meta textures as semantics.
// Technique order: SL SSR v0.35 - Legacy Resolve, THEN SL SSR Temporal v0.1.

#include "ReShade.fxh"

// -----------------------------------------------------------------------------
// Existing Firestorm / SLProbeLighting bridge uniforms.
// Exact names intentionally match the proven HybridGI temporal path.
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
uniform float SLSceneLinearValid = 0.0;
uniform float SLGBufferSpecularValid = 0.0;

uniform float4 SLGIInvModelviewDeltaC0 = 0.0;
uniform float4 SLGIInvModelviewDeltaC1 = 0.0;
uniform float4 SLGIInvModelviewDeltaC2 = 0.0;
uniform float4 SLGIInvModelviewDeltaC3 = 0.0;
uniform float SLGIMotionValid = 0.0;

uniform float SLGITonemapValid = 0.0;
uniform float SLGIFinalExposure = 1.0;
uniform float SLGITonemapMix = 1.0;
uniform float SLGITonemapType = 0.0;

// Set by SLSSRTemporalLink.addon.
uniform float SLSSRTemporalLinkValid = 0.0;
uniform int SLSSRTemporalFrameIndex = 0;

// Mirrored from v0.35 every frame by the link add-on so the correction pass
// exactly replaces v0.35's current-frame contribution rather than doubling it.
uniform float SSRStrength = 1.0;
uniform float SSRBaseReplacement = 1.0;
uniform float SSRMinConfidence = 0.0;
uniform int SSRLongRayFadeEnable = 0;
uniform float SSRLongRayDistanceStart = 14.0;
uniform float SSRLongRayDistanceEnd = 30.0;
uniform float SSRLongRayStretchStartPx = 240.0;
uniform float SSRLongRayStretchEndPx = 900.0;
uniform float LegacySpecularScale = 1.0;
uniform float LegacyEnvScale = 1.0;
uniform float LegacyFallbackThreshold = 0.005;
uniform float LegacyDielectricFallback = 0.040;
uniform float PBRStrength = 0.65;
uniform float PBRRoughnessPower = 1.25;
uniform float AlphaReceiverProtection = 1.0;

// -----------------------------------------------------------------------------
// Temporal controls
// -----------------------------------------------------------------------------
uniform int SSRTemporalEnable
<
    ui_label = "Temporal Accumulation";
    ui_tooltip = "Accumulate v0.35's resolved SSR using Firestorm camera reprojection plus previous depth/normal rejection.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 1;

uniform float SSRTemporalHistoryWeight
<
    ui_label = "Temporal History Weight";
    ui_tooltip = "Maximum accepted previous-frame contribution. 0.86 integrates several frames without making camera-only history too sticky.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.97; ui_step = 0.01;
> = 0.86;

uniform float SSRTemporalDepthTolerance
<
    ui_label = "Temporal Depth Rejection";
    ui_tooltip = "Minimum previous-frame view-depth tolerance used for disocclusion and moving-object rejection.";
    ui_type = "drag";
    ui_min = 0.005; ui_max = 0.50; ui_step = 0.005;
> = 0.015;

uniform float SSRTemporalNormalThreshold
<
    ui_label = "Temporal Normal Agreement";
    ui_tooltip = "Minimum dot product between reprojected current normal and stored previous normal.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.99; ui_step = 0.01;
> = 0.90;

uniform float SSRTemporalClampExpansion
<
    ui_label = "Temporal Neighborhood Clamp";
    ui_tooltip = "Expands the current SSR RGB neighborhood before clamping history. Lower rejects stale reflected colors more aggressively.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 0.25;

uniform float SSRTemporalMotionStartPx
<
    ui_label = "Motion Trust Start (px)";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 16.0; ui_step = 0.25;
> = 1.5;

uniform float SSRTemporalMotionEndPx
<
    ui_label = "Motion Trust End (px)";
    ui_type = "drag";
    ui_min = 1.0; ui_max = 64.0; ui_step = 0.5;
> = 18.0;

uniform int SSRTemporalResetHistory
<
    ui_label = "Reset History";
    ui_tooltip = "Set to 1 for one frame to discard previous SSR history, then return to 0.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 0;

uniform int SSRTemporalDisplayMode
<
    ui_label = "Temporal Display";
    ui_type = "combo";
    ui_items =
        "Final temporal correction\0"
        "Current resolved SSR input\0"
        "Temporal resolved SSR\0"
        "History acceptance\0"
        "Reprojected motion pixels\0"
        "Depth agreement\0"
        "Normal agreement\0"
        "History weight\0"
        "Link / motion status\0"
        "Temporal correction magnitude\0";
> = 0;

// -----------------------------------------------------------------------------
// Inputs
// -----------------------------------------------------------------------------
texture SLNativeNormalsTex : SL_NORMALS;
texture SLNativeDepthTex : SL_DEPTH;
texture SLAlphaMaskTex : SL_ALPHA_MASK;
texture SLSceneLinearTex : SL_SCENE_LINEAR;
texture SLGBufferSpecularTex : SL_GBUFFER_SPECULAR;

// These two semantics are supplied by SLSSRTemporalLink.addon from v0.35's
// private effect textures. This is the modular inter-effect boundary.
texture SLSSRResolvedInputTex : SL_SSR_RESOLVED;
texture SLSSRMetaInputTex : SL_SSR_META;

sampler SLNativeNormalsSampler { Texture = SLNativeNormalsTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler SLNativeDepthSampler { Texture = SLNativeDepthTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler SLAlphaMaskSampler { Texture = SLAlphaMaskTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler SLSceneLinearSampler { Texture = SLSceneLinearTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=LINEAR; MagFilter=LINEAR; MipFilter=POINT; };
sampler SLGBufferSpecularSampler { Texture = SLGBufferSpecularTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler SLSSRResolvedInputSampler { Texture = SLSSRResolvedInputTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=LINEAR; MagFilter=LINEAR; MipFilter=POINT; };
sampler SLSSRMetaInputSampler { Texture = SLSSRMetaInputTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=LINEAR; MagFilter=LINEAR; MipFilter=POINT; };

// -----------------------------------------------------------------------------
// Temporal storage (half resolution, matching v0.35 resolved SSR)
// -----------------------------------------------------------------------------
texture SLSSRTemporalTex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler SLSSRTemporalSampler { Texture=SLSSRTemporalTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=LINEAR; MagFilter=LINEAR; MipFilter=POINT; };

texture SLSSRTemporalDebugTex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler SLSSRTemporalDebugSampler { Texture=SLSSRTemporalDebugTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=LINEAR; MagFilter=LINEAR; MipFilter=POINT; };

texture SLSSRHistoryTex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler SLSSRHistorySampler { Texture=SLSSRHistoryTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=LINEAR; MagFilter=LINEAR; MipFilter=POINT; };

texture SLSSRHistoryGeomTex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler SLSSRHistoryGeomSampler { Texture=SLSSRHistoryGeomTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };

// -----------------------------------------------------------------------------
// Bridge helpers
// -----------------------------------------------------------------------------
bool HasBridgeRegistration()
{
    return SLBridgeRegistrationValid > 0.5 && SLBridgeViewport.z > 1.0 && SLBridgeViewport.w > 1.0 && SLBridgeBufferInfo.x > 1.0 && SLBridgeBufferInfo.y > 1.0;
}

bool HasExactMatrices()
{
    float invEnergy = dot(abs(SLGIInvProjC0),1.0)+dot(abs(SLGIInvProjC1),1.0)+dot(abs(SLGIInvProjC2),1.0)+dot(abs(SLGIInvProjC3),1.0);
    float projEnergy = dot(abs(SLGIProjC0),1.0)+dot(abs(SLGIProjC1),1.0)+dot(abs(SLGIProjC2),1.0)+dot(abs(SLGIProjC3),1.0);
    return HasBridgeRegistration() && SLGIProjectionValid > 0.5 && SLProbeNativeValid > 0.5 && invEnergy > 0.01 && projEnergy > 0.01;
}

bool HasTemporalMotion()
{
    float e = dot(abs(SLGIInvModelviewDeltaC0),1.0)+dot(abs(SLGIInvModelviewDeltaC1),1.0)+dot(abs(SLGIInvModelviewDeltaC2),1.0)+dot(abs(SLGIInvModelviewDeltaC3),1.0);
    return SLGIMotionValid > 0.5 && e > 0.01;
}

float2 FirestormUV(float2 screenUV)
{
    if (!HasBridgeRegistration()) return float2(-2.0,-2.0);
    float2 windowPxGL=float2(screenUV.x*SLBridgeBufferInfo.x,(1.0-screenUV.y)*SLBridgeBufferInfo.y);
    return (windowPxGL-SLBridgeViewport.xy)/SLBridgeViewport.zw;
}

float2 ScreenUVFromFirestormUV(float2 nativeUV)
{
    float2 windowPxGL=SLBridgeViewport.xy+nativeUV*SLBridgeViewport.zw;
    return float2(windowPxGL.x/SLBridgeBufferInfo.x,1.0-windowPxGL.y/SLBridgeBufferInfo.y);
}

bool InsideFirestormWorld(float2 screenUV)
{
    float2 uv=FirestormUV(screenUV);
    return uv.x>=0.0 && uv.x<=1.0 && uv.y>=0.0 && uv.y<=1.0;
}

float4 MulInvProj(float4 v) { return SLGIInvProjC0*v.x+SLGIInvProjC1*v.y+SLGIInvProjC2*v.z+SLGIInvProjC3*v.w; }
float4 MulProj(float4 v) { return SLGIProjC0*v.x+SLGIProjC1*v.y+SLGIProjC2*v.z+SLGIProjC3*v.w; }
float4 MulInvModelviewDelta(float4 v) { return SLGIInvModelviewDeltaC0*v.x+SLGIInvModelviewDeltaC1*v.y+SLGIInvModelviewDeltaC2*v.z+SLGIInvModelviewDeltaC3*v.w; }

float3 ReconstructViewPosition(float2 screenUV,float rawDepth)
{
    float2 nativeUV=FirestormUV(screenUV);
    float4 p=MulInvProj(float4(nativeUV*2.0-1.0,rawDepth*2.0-1.0,1.0));
    float safeW=abs(p.w)>1e-8?p.w:(p.w<0.0?-1e-8:1e-8);
    return p.xyz/safeW;
}

bool ProjectViewPosition(float3 viewPos,out float2 screenUV)
{
    float4 clip=MulProj(float4(viewPos,1.0));
    if(abs(clip.w)<=1e-8){screenUV=0.0;return false;}
    float2 nativeUV=(clip.xy/clip.w)*0.5+0.5;
    if(nativeUV.x<=0.0||nativeUV.x>=1.0||nativeUV.y<=0.0||nativeUV.y>=1.0){screenUV=0.0;return false;}
    screenUV=ScreenUVFromFirestormUV(nativeUV);
    return InsideFirestormWorld(screenUV);
}

bool IsBackgroundDepth(float d){return d>=0.999999;}
float GetRawDepth(float2 uv){return tex2D(SLNativeDepthSampler,FirestormUV(uv)).r;}
float4 GetRawNormalData(float2 uv){return tex2D(SLNativeNormalsSampler,FirestormUV(uv));}

float3 DecodeFirestormNormalRaw(float4 encodedNormal)
{
    float2 fenc=encodedNormal.xy*4.0-2.0;
    float f=dot(fenc,fenc);
    float g=sqrt(saturate(1.0-f*0.25));
    float3 n; n.xy=fenc*g; n.z=1.0-f*0.5;
    float len2=dot(n,n); return len2>1e-8?n*rsqrt(len2):float3(0.0,0.0,1.0);
}

float3 GetTransportNormal(float2 uv){return DecodeFirestormNormalRaw(GetRawNormalData(uv));}
float4 GetSceneLinear(float2 uv){if(!InsideFirestormWorld(uv)||SLSceneLinearValid<0.5)return 0.0;return tex2D(SLSceneLinearSampler,FirestormUV(uv));}
float4 GetGBufferSpecular(float2 uv){if(!InsideFirestormWorld(uv)||SLGBufferSpecularValid<0.5)return 0.0;return tex2D(SLGBufferSpecularSampler,FirestormUV(uv));}
float GetAlphaCoverage(float2 uv){if(!InsideFirestormWorld(uv))return 0.0;return saturate(tex2D(SLAlphaMaskSampler,FirestormUV(uv)).a);}
bool IsPBR(float4 rawNormal){return abs(rawNormal.a-0.67)<0.1;}

// -----------------------------------------------------------------------------
// Material / presentation helpers copied from the v0.35 composite contract.
// -----------------------------------------------------------------------------
float LegacyAuthoredSignal(float4 rawNormal,float4 specInfo){return max(max(specInfo.r,max(specInfo.g,specInfo.b)),saturate(rawNormal.b));}
bool LegacyUsesDielectricFallback(float4 rawNormal,float4 specInfo){return LegacyAuthoredSignal(rawNormal,specInfo)<=LegacyFallbackThreshold;}
float3 LegacySpecularTint(float4 rawNormal,float4 specInfo)
{
    float3 materialSpec=saturate(specInfo.rgb*LegacySpecularScale);
    float classicEnv=saturate(rawNormal.b)*LegacyEnvScale;
    float3 authoredTint=max(materialSpec,classicEnv.xxx);
    if(LegacyUsesDielectricFallback(rawNormal,specInfo)) return saturate(LegacyDielectricFallback).xxx;
    return authoredTint;
}
float PBRReflectivity(float4 specInfo)
{
    float roughness=saturate(specInfo.g), metallic=saturate(specInfo.b);
    float smoothness=pow(saturate(1.0-roughness),PBRRoughnessPower);
    return saturate(PBRStrength*smoothness*lerp(0.18,1.0,metallic));
}
float ViewFresnel(float3 viewPos,float3 normal)
{
    float nv=saturate(dot(normal,normalize(-viewPos)));
    return lerp(0.45,1.0,pow(1.0-nv,5.0));
}
float SSRLongRayRejectAmount(float4 traceMeta)
{
    float d0=min(SSRLongRayDistanceStart,SSRLongRayDistanceEnd-1e-3);
    float d1=max(SSRLongRayDistanceEnd,d0+1e-3);
    float s0=min(SSRLongRayStretchStartPx,SSRLongRayStretchEndPx-1e-3);
    float s1=max(SSRLongRayStretchEndPx,s0+1e-3);
    return smoothstep(d0,d1,traceMeta.r)*smoothstep(s0,s1,traceMeta.g);
}

float3 SLLinearToSRGB(float3 cl)
{
    cl=saturate(cl); float3 lo=cl*12.92; float3 hi=1.055*pow(cl,0.41666)-0.055; float3 r;
    r.r=cl.r<0.0031308?lo.r:hi.r; r.g=cl.g<0.0031308?lo.g:hi.g; r.b=cl.b<0.0031308?lo.b:hi.b; return r;
}
float3 SLPBRNeutralToneMap(float3 color)
{
    const float startCompression=0.76,desaturation=0.15; float x=min(color.r,min(color.g,color.b)); float offset=x<0.08?x-6.25*x*x:0.04; color-=offset;
    float peak=max(color.r,max(color.g,color.b)); if(peak<startCompression)return color; const float d=1.0-startCompression; float newPeak=1.0-d*d/(peak+d-startCompression); color*=newPeak/max(peak,1e-6); float g=1.0-1.0/(desaturation*(peak-newPeak)+1.0); return lerp(color,newPeak.xxx,g);
}
float3 SLACESInput(float3 c){return float3(0.59719*c.r+0.35458*c.g+0.04823*c.b,0.07600*c.r+0.90834*c.g+0.01566*c.b,0.02840*c.r+0.13383*c.g+0.83777*c.b);}
float3 SLACESOutput(float3 c){return float3(1.60475*c.r-0.53108*c.g-0.07367*c.b,-0.10208*c.r+1.10813*c.g-0.00605*c.b,-0.00327*c.r-0.07276*c.g+1.07602*c.b);}
float3 SLRRTAndODTFit(float3 c){float3 a=c*(c+0.0245786)-0.000090537;float3 b=c*(0.983729*c+0.4329510)+0.238081;return a/max(b,1e-6);}
float3 SLACESHillToneMap(float3 c){return saturate(SLACESOutput(SLRRTAndODTFit(SLACESInput(c))));}
float3 SLFirestormToneMapLinear(float3 c){float3 e=max(c,0.0)*max(SLGIFinalExposure,0.0);float3 m=SLGITonemapType<0.5?SLPBRNeutralToneMap(e):SLACESHillToneMap(e);return saturate(lerp(e,m,saturate(SLGITonemapMix)));}
float SLUseSRGBEncoding(float3 sceneLinear,float3 actual){float3 tm=SLFirestormToneMapLinear(sceneLinear),s=SLLinearToSRGB(tm);return dot(abs(s-actual),1.0)<dot(abs(tm-actual),1.0)?1.0:0.0;}
float3 SLFirestormPresentation(float3 sceneLinear,float useSRGB){float3 tm=SLFirestormToneMapLinear(sceneLinear);return lerp(tm,SLLinearToSRGB(tm),useSRGB);}

float SceneToPresentationScaleFromReference(float2 uv,float3 presentedReference)
{
    const float3 luma=float3(0.2126,0.7152,0.0722); float3 scene=max(GetSceneLinear(uv).rgb,0.0); float ll=dot(scene,luma); if(ll<=1e-5)return 0.0; return clamp(dot(max(presentedReference,0.0),luma)/ll,0.0,8.0);
}

// Compute the exact presentation-space contribution that v0.35 applies for a
// supplied resolved SSR sample. presentedReference should be the current backbuffer.
float3 SSRPresentationDelta(float2 uv,float4 ssrSample,float4 traceMeta,float3 presentedReference)
{
    if(SLSSRTemporalLinkValid<0.5||!InsideFirestormWorld(uv)||!HasExactMatrices()||SLSceneLinearValid<0.5||SLGBufferSpecularValid<0.5)return 0.0;
    float depth=GetRawDepth(uv); if(IsBackgroundDepth(depth))return 0.0;
    float4 rawNormal=GetRawNormalData(uv); bool pbr=IsPBR(rawNormal); float4 specInfo=GetGBufferSpecular(uv);
    float3 legacyTint=pbr?1.0.xxx:LegacySpecularTint(rawNormal,specInfo);
    float reflectivity=pbr?PBRReflectivity(specInfo):max(legacyTint.r,max(legacyTint.g,legacyTint.b));
    float receiver=1.0-saturate(GetAlphaCoverage(uv)*AlphaReceiverProtection);
    float3 normal=DecodeFirestormNormalRaw(rawNormal); float3 viewPos=ReconstructViewPosition(uv,depth); float fresnel=ViewFresnel(viewPos,normal);
    float confidenceGate=step(SSRMinConfidence,ssrSample.a);
    float longRayWeight=1.0-(SSRLongRayFadeEnable>0?SSRLongRayRejectAmount(traceMeta):0.0);
    float materialWeight=pbr?saturate(reflectivity):1.0;
    float weight=saturate(ssrSample.a)*confidenceGate*longRayWeight*materialWeight*fresnel*max(SSRStrength,0.0)*receiver;
    if(weight<=1e-5)return 0.0;
    float3 reflectionLinear=max(ssrSample.rgb,0.0)*weight*(pbr?1.0.xxx:legacyTint);
    float appliedWeight=pbr?weight:weight*reflectivity;
    float baseRemoval=saturate(appliedWeight*saturate(SSRBaseReplacement));
    float3 sceneLinear=max(GetSceneLinear(uv).rgb,0.0);
    float3 compositeLinear=sceneLinear*(1.0-baseRemoval)+reflectionLinear;
    if(SLGITonemapValid<0.5) return (compositeLinear-sceneLinear)*SceneToPresentationScaleFromReference(uv,presentedReference);
    float useSRGB=SLUseSRGBEncoding(sceneLinear,presentedReference);
    return SLFirestormPresentation(compositeLinear,useSRGB)-SLFirestormPresentation(sceneLinear,useSRGB);
}

// -----------------------------------------------------------------------------
// Temporal history
// -----------------------------------------------------------------------------
float3 EncodeHistoryNormal(float3 n){return saturate(n*0.5+0.5);}
float3 DecodeHistoryNormal(float3 e){float3 n=e*2.0-1.0;float l=dot(n,n);return l>1e-8?n*rsqrt(l):float3(0.0,0.0,1.0);}

float4 CurrentHistoryGeometry(float2 uv)
{
    if(!HasBridgeRegistration()||!HasExactMatrices()||!InsideFirestormWorld(uv))return 0.0;
    float rawDepth=GetRawDepth(uv); if(IsBackgroundDepth(rawDepth))return 0.0;
    float3 p=ReconstructViewPosition(uv,rawDepth); float linearDepth=max(-p.z,0.0); if(linearDepth<=1e-5)return 0.0;
    return float4(EncodeHistoryNormal(GetTransportNormal(uv)),linearDepth);
}

float TemporalHistoryValidity(float2 uv,out float2 previousUV,out float depthAgreement,out float normalAgreement,out float motionPixels)
{
    previousUV=uv; depthAgreement=0.0; normalAgreement=0.0; motionPixels=0.0;
    if(!HasTemporalMotion()||!HasBridgeRegistration()||!HasExactMatrices()||!InsideFirestormWorld(uv))return 0.0;
    float rawDepth=GetRawDepth(uv); if(IsBackgroundDepth(rawDepth))return 0.0;
    float3 currentPos=ReconstructViewPosition(uv,rawDepth); float4 pp4=MulInvModelviewDelta(float4(currentPos,1.0)); float sw=abs(pp4.w)>1e-8?pp4.w:1.0; float3 previousPos=pp4.xyz/sw;
    if(!ProjectViewPosition(previousPos,previousUV))return 0.0;
    motionPixels=length((previousUV-uv)*float2((float)BUFFER_WIDTH,(float)BUFFER_HEIGHT));
    float4 hg=tex2D(SLSSRHistoryGeomSampler,previousUV); float historyDepth=hg.a; if(historyDepth<=1e-5)return 0.0;
    float predictedDepth=max(-previousPos.z,0.0); float depthError=abs(historyDepth-predictedDepth); float dt=max(SSRTemporalDepthTolerance,predictedDepth*0.0035);
    depthAgreement=1.0-smoothstep(dt,dt*2.0,depthError);
    float3 pn=MulInvModelviewDelta(float4(GetTransportNormal(uv),0.0)).xyz; float nl=dot(pn,pn); if(nl<=1e-8)return 0.0; pn*=rsqrt(nl);
    float nd=saturate(dot(pn,DecodeHistoryNormal(hg.rgb)));
    normalAgreement=smoothstep(SSRTemporalNormalThreshold,min(SSRTemporalNormalThreshold+0.15,0.999),nd);
    return saturate(depthAgreement*normalAgreement);
}

void CurrentNeighborhoodEnvelope(float2 uv,out float3 lo,out float3 hi)
{
    float2 px=float2(2.0/(float)BUFFER_WIDTH,2.0/(float)BUFFER_HEIGHT);
    float3 c=tex2D(SLSSRResolvedInputSampler,uv).rgb; lo=c;hi=c;
    float3 s0=tex2D(SLSSRResolvedInputSampler,uv+float2(px.x,0)).rgb;
    float3 s1=tex2D(SLSSRResolvedInputSampler,uv-float2(px.x,0)).rgb;
    float3 s2=tex2D(SLSSRResolvedInputSampler,uv+float2(0,px.y)).rgb;
    float3 s3=tex2D(SLSSRResolvedInputSampler,uv-float2(0,px.y)).rgb;
    lo=min(lo,s0);hi=max(hi,s0);lo=min(lo,s1);hi=max(hi,s1);lo=min(lo,s2);hi=max(hi,s2);lo=min(lo,s3);hi=max(hi,s3);
    float3 span=hi-lo; float peak=max(max(hi.r,hi.g),hi.b); float floorPad=max(0.0015,peak*0.10); float3 pad=max(span*SSRTemporalClampExpansion,floorPad.xxx); lo=max(lo-pad,0.0);hi+=pad;
}

struct TemporalMRT { float4 color : SV_Target0; float4 debug : SV_Target1; };
TemporalMRT TemporalResolvePS(float4 pos:SV_Position,float2 uv:TEXCOORD)
{
    TemporalMRT o; float4 current=tex2D(SLSSRResolvedInputSampler,uv);
    float2 previousUV;float depthAgreement,normalAgreement,motionPixels;float validity=TemporalHistoryValidity(uv,previousUV,depthAgreement,normalAgreement,motionPixels);
    float historyWeight=0.0, motionTrust=0.0, clampTrust=0.0; float3 resolved=current.rgb;
    bool forceReset=SSRTemporalResetHistory>0||SLSSRTemporalFrameIndex<2||SLSSRTemporalLinkValid<0.5||SSRTemporalEnable<=0;
    if(!forceReset&&validity>1e-4&&SSRTemporalHistoryWeight>1e-4&&current.a>1e-5)
    {
        float4 history=tex2D(SLSSRHistorySampler,previousUV);float3 before=history.rgb;float3 lo,hi;CurrentNeighborhoodEnvelope(uv,lo,hi);history.rgb=clamp(history.rgb,lo,hi);
        motionTrust=1.0-smoothstep(SSRTemporalMotionStartPx,max(SSRTemporalMotionEndPx,SSRTemporalMotionStartPx+0.01),motionPixels);
        float clipRatio=length(before-history.rgb)/max(length(before),0.01);clampTrust=1.0-smoothstep(0.05,0.60,clipRatio);
        // Current confidence is deliberately required: do not resurrect an old
        // SSR hit when this frame has no accepted hit. This is the safe v0.1 mode.
        historyWeight=saturate(SSRTemporalHistoryWeight*validity*saturate(current.a)*lerp(0.25,1.0,motionTrust)*lerp(0.15,1.0,clampTrust));
        resolved=lerp(current.rgb,history.rgb,historyWeight);
    }
    o.color=float4(max(resolved,0.0),validity);
    o.debug=float4(validity,saturate(motionPixels/32.0),depthAgreement,historyWeight);
    return o;
}

float4 CopyTemporalHistoryPS(float4 pos:SV_Position,float2 uv:TEXCOORD):SV_Target { float4 t=tex2D(SLSSRTemporalSampler,uv); float4 c=tex2D(SLSSRResolvedInputSampler,uv); return float4(t.rgb,c.a); }
float4 StoreHistoryGeometryPS(float4 pos:SV_Position,float2 uv:TEXCOORD):SV_Target { return CurrentHistoryGeometry(uv); }

float4 TemporalCompositeCorrectionPS(float4 pos:SV_Position,float2 uv:TEXCOORD):SV_Target
{
    float4 color=tex2D(ReShade::BackBuffer,uv);
    float4 current=tex2D(SLSSRResolvedInputSampler,uv); float4 temp=tex2D(SLSSRTemporalSampler,uv); float4 dbg=tex2D(SLSSRTemporalDebugSampler,uv); float4 meta=tex2D(SLSSRMetaInputSampler,uv);
    float4 temporalSample=float4(temp.rgb,current.a);
    if(SSRTemporalDisplayMode==1)return float4(saturate(current.rgb),1.0);
    if(SSRTemporalDisplayMode==2)return float4(saturate(temp.rgb),1.0);
    if(SSRTemporalDisplayMode==3)return float4(1.0-dbg.r,dbg.r,0.0,1.0);
    if(SSRTemporalDisplayMode==4)return float4(dbg.g.xxx,1.0);
    if(SSRTemporalDisplayMode==5)return float4(dbg.b.xxx,1.0);
    if(SSRTemporalDisplayMode==6)
    {
        float2 pu;float da,na,mp;TemporalHistoryValidity(uv,pu,da,na,mp);return float4(na.xxx,1.0);
    }
    if(SSRTemporalDisplayMode==7)return float4(dbg.a.xxx,1.0);
    if(SSRTemporalDisplayMode==8)
    {
        float link=saturate(SLSSRTemporalLinkValid);float motion=HasTemporalMotion()?1.0:0.0;return float4(1.0-link,motion,link,1.0);
    }
    float3 currentDelta=SSRPresentationDelta(uv,current,meta,color.rgb);
    float3 temporalDelta=SSRPresentationDelta(uv,temporalSample,meta,color.rgb-currentDelta);
    float3 correction=temporalDelta-currentDelta;
    if(SSRTemporalDisplayMode==9)return float4(saturate(abs(correction)*8.0),1.0);
    if(SSRTemporalEnable<=0||SLSSRTemporalLinkValid<0.5)return color;
    color.rgb=max(color.rgb+correction,0.0);return color;
}

technique SL_SSR_Temporal_v0_1
<
    ui_label = "SL SSR Temporal v0.1 - Reprojected History";
    ui_tooltip = "Standalone temporal consumer for v0.35. Reuses proven HybridGI camera reprojection and depth/normal history rejection. Keep this technique AFTER SL SSR v0.35 in ReShade order.";
>
{
    pass TemporalResolve
    {
        VertexShader=PostProcessVS;
        PixelShader=TemporalResolvePS;
        RenderTarget0=SLSSRTemporalTex;
        RenderTarget1=SLSSRTemporalDebugTex;
    }
    pass CopyTemporalHistory
    {
        VertexShader=PostProcessVS;
        PixelShader=CopyTemporalHistoryPS;
        RenderTarget=SLSSRHistoryTex;
    }
    pass StoreHistoryGeometry
    {
        VertexShader=PostProcessVS;
        PixelShader=StoreHistoryGeometryPS;
        RenderTarget=SLSSRHistoryGeomTex;
    }
    pass CompositeCorrection
    {
        VertexShader=PostProcessVS;
        PixelShader=TemporalCompositeCorrectionPS;
    }
}
