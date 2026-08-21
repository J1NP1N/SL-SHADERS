from pathlib import Path
import base64, gzip, hashlib

root = Path(__file__).resolve().parent
srcdir = root.parent / "static-hiz-v0.52"
parts = sorted(srcdir.glob("SL_SSR_StaticHiZ_v0_52_GrazingRefine_Diagnostic.fx.gz.b64.part*"))
if len(parts) != 2:
    raise SystemExit(f"expected 2 v0.52 parts, found {len(parts)}")
raw = gzip.decompress(base64.b64decode("".join(p.read_text("ascii").strip() for p in parts)))
if hashlib.sha256(raw).hexdigest() != "d499c8cedf922552a784a4ca4359ba74b1161b4026b6f20e263ef82715f94c38":
    raise SystemExit("v0.52 checksum mismatch")
s = raw.decode("utf-8")

def rep(old, new):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"expected one match, found {n}: {old[:80]!r}")
    s = s.replace(old, new, 1)

rep("// SL_SSR_StaticHiZ_v0_52_GrazingRefine_Diagnostic.fx",
    "// SL_SSR_StaticHiZ_v0_53_EdgeCoverage_Diagnostic.fx")
rep('ui_tooltip = "Maximum allowed change between the mip-0 hierarchy sample and a fresh Dstatic sample at the refined UV.";',
    'ui_tooltip = "Hierarchy-guide consistency only. Fresh full-resolution Dstatic slab membership is authoritative for final v0.53 edge acceptance."')
rep('"Reject code 7 count — already beyond slab\\0"\n        "Accepted hit distance\\0";',
    '"Reject code 7 count — already beyond slab\\0"\n        "Residual edge failure class\\0"\n        "Fresh-depth edge rescue count\\0"\n        "Accepted hit distance\\0";')
rep("texture SLStaticHiZRejectBTex { Width=BUFFER_WIDTH; Height=BUFFER_HEIGHT; Format=RGBA16F; };",
    "texture SLStaticHiZRejectBTex { Width=BUFFER_WIDTH; Height=BUFFER_HEIGHT; Format=RGBA16F; };\n"
    "texture SLStaticHiZEdgeDiagTex { Width=BUFFER_WIDTH; Height=BUFFER_HEIGHT; Format=RGBA16F; };")
rep("sampler SLStaticHiZRejectBSampler { Texture=SLStaticHiZRejectBTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };",
    "sampler SLStaticHiZRejectBSampler { Texture=SLStaticHiZRejectBTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };\n"
    "sampler SLStaticHiZEdgeDiagSampler { Texture=SLStaticHiZEdgeDiagTex; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };")
rep("out float4 rejectA,out float4 rejectB)\n{",
    "out float4 rejectA,out float4 rejectB,out float4 edgeDiag)\n{")
rep("rejectA=0.0;rejectB=0.0;",
    "rejectA=0.0;rejectB=0.0;edgeDiag=0.0;")
rep("        if(overlap&&mip==0)\n        {",
    "        bool mip0Attempted=overlap&&mip==0;\n"
    "        if(mip0Attempted)\n        {\n"
    "            edgeDiag.r+=1.0;")
rep("                        else\n                        {\n                            RecordFineReject(5.0,rejectedFine,lastFineReject,rejectA,rejectB);\n                        }",
    "                        else\n                        {\n                            edgeDiag.g+=1.0;\n"
    "                            RecordFineReject(5.0,rejectedFine,lastFineReject,rejectA,rejectB);\n                        }")
rep("""                if(freshDepth<=0.0)
                {
                    RecordFineReject(4.0,rejectedFine,lastFineReject,rejectA,rejectB);
                }
                else if(abs(freshDepth-sd)>max(StaticHiZDiscontinuityTolerance,0.001))
                {
                    RecordFineReject(5.0,rejectedFine,lastFineReject,rejectA,rejectB);
                }
                else if(candidateDepth<freshDepth-front-0.001||candidateDepth>freshDepth+back)
                {
                    RecordFineReject(6.0,rejectedFine,lastFineReject,rejectA,rejectB);
                }
                else
                {
                    if(grazingRecovered)rejectB.a+=1.0;""",
"""                float tol=max(StaticHiZDiscontinuityTolerance,0.001);
                bool mismatch=freshDepth>0.0&&abs(freshDepth-sd)>tol;
                bool freshInside=freshDepth>0.0&&candidateDepth>=freshDepth-front-0.001&&candidateDepth<=freshDepth+back;

                if(freshDepth<=0.0)
                {
                    RecordFineReject(4.0,rejectedFine,lastFineReject,rejectA,rejectB);
                }
                else if(!freshInside)
                {
                    if(mismatch)RecordFineReject(5.0,rejectedFine,lastFineReject,rejectA,rejectB);
                    else RecordFineReject(6.0,rejectedFine,lastFineReject,rejectA,rejectB);
                }
                else
                {
                    if(mismatch)edgeDiag.b+=1.0;
                    if(grazingRecovered)rejectB.a+=1.0;""")
rep("""        lambda=min(exitLambda+epsLambda,1.0);
        mip=min(mip+1,SL_STATIC_HIZ_TOP_MIP);""",
"""        if(mip0Attempted)
        {
            float nextLambda=min(exitLambda+epsLambda,1.0);
            if(nextLambda<1.0)
            {
                float2 nextUV=StaticScreenRayUV(r,nextLambda);
                if(InsideScreen(nextUV)&&InsideFirestormWorld(nextUV))
                {
                    float nextSurface=SampleStaticDepthLinear(nextUV);
                    float nextRayDepth=StaticScreenRayDepth(r,nextLambda);
                    if(nextSurface>0.0&&nextRayDepth>=nextSurface-front-0.001&&nextRayDepth<=nextSurface+back)
                        edgeDiag.a+=1.0;
                }
            }
        }

        lambda=min(exitLambda+epsLambda,1.0);
        mip=min(mip+1,SL_STATIC_HIZ_TOP_MIP);""")
rep("out float4 rejectA:SV_Target3,out float4 rejectB:SV_Target4):SV_Target0",
    "out float4 rejectA:SV_Target3,out float4 rejectB:SV_Target4,\n"
    "                        out float4 edgeDiag:SV_Target5):SV_Target0")
rep("termination,lastFineReject,lastMip,rejectA,rejectB);",
    "termination,lastFineReject,lastMip,rejectA,rejectB,edgeDiag);")
rep("float4 StaticHiZDisplayPS(float4 pos:SV_Position,float2 uv:TEXCOORD):SV_Target",
"""float3 ResidualEdgeFailureColor(float4 d,float term,float hit)
{
    if(hit>0.5&&d.b>0.0)return float3(0.0,1.0,0.0);
    if((term>4.5&&term<6.5)&&d.r<0.5)return float3(1.0,0.0,0.0);
    if(d.g>0.0)return float3(1.0,0.0,1.0);
    if(d.a>0.0)return float3(1.0,0.45,0.0);
    if(term>5.5&&term<6.5)return float3(1.0,1.0,0.0);
    if(term>6.5)return float3(0.2,0.4,1.0);
    return 0.0;
}

float4 StaticHiZDisplayPS(float4 pos:SV_Position,float2 uv:TEXCOORD):SV_Target""")
rep("    float4 rejectB=tex2D(SLStaticHiZRejectBSampler,uv);",
    "    float4 rejectB=tex2D(SLStaticHiZRejectBSampler,uv);\n"
    "    float4 edgeDiag=tex2D(SLStaticHiZEdgeDiagSampler,uv);")
rep("    if(StaticHiZDisplayMode==14)return float4(saturate(rejectB.b/8.0).xxx,1.0);\n    return float4(DepthViz(events.b).xxx,1.0);",
    "    if(StaticHiZDisplayMode==14)return float4(saturate(rejectB.b/8.0).xxx,1.0);\n"
    "    if(StaticHiZDisplayMode==15)return float4(ResidualEdgeFailureColor(edgeDiag,events.r,hit.a),1.0);\n"
    "    if(StaticHiZDisplayMode==16)return float4(0.0,saturate(edgeDiag.b/4.0),0.0,1.0);\n"
    "    return float4(DepthViz(events.b).xxx,1.0);")
rep("technique HIZ_DEBUG_SL_SSR_StaticHiZ_v0_52_GrazingRefine_Diagnostic",
    "technique HIZ_DEBUG_SL_SSR_StaticHiZ_v0_53_EdgeCoverage_Diagnostic")
rep('ui_label = "HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.52 Grazing Refine";',
    'ui_label = "HIZ DEBUG — Dstatic Hi-Z Diagnostic v0.53 Edge Coverage";')
rep('ui_tooltip = "H2 diagnostic: distinguishes fine-reject causes and recovers locally continuous mip-0 grazing candidates that begin already inside the Dstatic slab. Dstatic/Cstatic only, no pixel DDA, avatar thickness path untouched.";',
    'ui_tooltip = "Preserves v0.52 H2 grazing recovery and targets only residual silhouette/discontinuity coverage. Dstatic/Cstatic only, no pixel DDA, avatar path untouched."')
rep("        RenderTarget4=SLStaticHiZRejectBTex;\n    }",
    "        RenderTarget4=SLStaticHiZRejectBTex;\n"
    "        RenderTarget5=SLStaticHiZEdgeDiagTex;\n    }")

out = root / "SL_SSR_StaticHiZ_v0_53_EdgeCoverage_Diagnostic.fx"
out.write_text(s, encoding="utf-8")
sha = hashlib.sha256(out.read_bytes()).hexdigest()
print(out)
print("SHA-256:", sha)
if sha != "d4e4e9f72fae5a02ad2a1c9b7b534587a67aa3a7be441e4d4e2968eee91544e4":
    raise SystemExit("v0.53 checksum mismatch")
print("PASS")
