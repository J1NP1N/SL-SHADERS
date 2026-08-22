from pathlib import Path
import argparse
import hashlib
import re

BASE_SHA256 = "715deb015938b879ae9a23cd24f1cc26adac2ffe3d731f9edaf70a911e0bb755"
OUTPUT_SHA256 = "b17afe7222e22cc7c4011d47910d81ca126256f82e2c6627c299eebb8f97c9ba"
OUTPUT_NAME = "SL_SSR_CORE_SPATIAL_HIZ_ENV_OCCLUSION_DIAG_v0_1.fx"


def function_span(text: str, signature: str):
    i = text.index(signature)
    start = text.rfind("\n", 0, i) + 1
    brace = text.index("{", i)
    depth = 0
    for j in range(brace, len(text)):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return start, j + 1
    raise RuntimeError(f"unterminated function: {signature}")


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected one anchor, found {count}: {old[:100]!r}")
    return text.replace(old, new, 1)


def build(base_path: Path) -> str:
    base_bytes = base_path.read_bytes()
    actual_base = hashlib.sha256(base_bytes).hexdigest()
    if actual_base != BASE_SHA256:
        raise SystemExit(f"base SHA-256 mismatch: {actual_base} != {BASE_SHA256}")

    base = base_bytes.decode("utf-8")
    trace_a, trace_b = function_span(base, "bool SLH53TraceWorld(")
    trace_world_exact = base[trace_a:trace_b]
    avatar_a, avatar_b = function_span(base, "bool TraceSSR(")
    avatar_trace_exact = base[avatar_a:avatar_b]

    s = base
    s = replace_once(s, "// SL_SSR_CORE_SPATIAL_HIZ_v1_0.fx",
                     "// SL_SSR_CORE_SPATIAL_HIZ_ENV_OCCLUSION_DIAG_v0_1.fx")
    s = replace_once(
        s,
        "// CORE+SPATIAL v1.0: accepted core/spatial + validated Hi-Z v0.53 WORLD tracer A/B.\n"
        "// v1.0 restores v0.49 normalized-TEXCOORD addressing and isolates all private RT names.",
        "// Environment-occlusion diagnostic v0.1 based byte-for-byte on production v1.0 before this patch.\n"
        "// Adds a separate Dstatic/Hi-Z visibility classifier only; accepted WORLD/AVATAR hit paths are unchanged."
    )

    # Isolate every private runtime target from production v1.0. ReShade shares
    # same-named textures even when the sibling technique is disabled.
    for old, new in {
        "SLCSH10Raw": "SLEOD01Raw",
        "SLCSH10Meta": "SLEOD01Meta",
        "SLCSH10BlurH": "SLEOD01BlurH",
        "SLCSH10Resolved": "SLEOD01Resolved",
        "SLCSH10H53": "SLEOD01H53",
    }.items():
        s = s.replace(old, new)

    s = replace_once(
        s,
        '        "WORLD tracer A/B coverage: old R / Hi-Z G / both white\\0";',
        '        "WORLD tracer A/B coverage: old R / Hi-Z G / both white\\0"\n'
        '        "Environment visibility: blocked red / escape blue / WORLD hit green\\0";'
    )

    # Separate environment-visibility query. It intentionally does not return a
    # hit, color, confidence, or candidate to production SSR. It descends the
    # existing min/max Hi-Z hierarchy and uses fresh full-resolution Dstatic at
    # mip 0 to classify geometry that the normal accepted-hit trace did not use.
    classifier = r'''

// -----------------------------------------------------------------------------
// Environment occlusion diagnostic only.
// Return: 0 = unclassified, 1 = unobstructed environment escape, 2 = occluded.
// This does not alter or feed SLH53TraceWorld hit acceptance.
// -----------------------------------------------------------------------------
float SLH53ClassifyEnvironmentVisibility(float2 receiverUV)
{
    if(!SLH53HasExactMatrices())return 0.0;
    if(!SLH53InsideFirestormWorld(receiverUV))return 0.0;

    float2 nativeUV=SLH53FirestormUV(receiverUV);
    float receiverRaw=tex2D(SLH53_PRIMARY_DEPTH_SAMPLER,nativeUV).r;
    if(SLH53IsBackgroundDepth(receiverRaw))return 0.0;

    float3 receiverPos=SLH53ReconstructViewPosition(receiverUV,receiverRaw);
    float3 receiverNormal=SLH53DecodeFirestormNormalRaw(tex2D(SLH53_NORMALS_SAMPLER,nativeUV));
    float3 incident=normalize(receiverPos);
    float3 rayDir=normalize(reflect(incident,receiverNormal));
    float3 startPos=receiverPos+receiverNormal*max(SLH53OriginBias,0.0)+rayDir*max(SLH53InitialTravel,0.0);

    SLH53ScreenRay r;
    if(!SLH53BuildScreenRay(startPos,rayDir,max(SLH53MaxDistance,0.01),r))return 0.0;

    int mip=clamp(SLH53StartMip,1,SLH53_TOP_MIP);
    float lambda=0.0;
    float lineLen=max(length(r.dpx),1e-5);
    float epsLambda=max(SLH53TileEpsilonPx,0.001)/lineLen;
    float selfGuardLambda=max(SLH53TileEpsilonPx,0.001)*2.0/lineLen;

    [loop]
    for(int i=0;i<SLH53_MAX_ITERS;++i)
    {
        if(i>=SLH53MaxIterations)return 0.0;
        if(lambda>=1.0)
        {
            float2 endUV=SLH53RayUV(r,1.0);
            if(!SLH53InsideScreen(endUV)||!SLH53InsideFirestormWorld(endUV))return 1.0;
            return SLH53SampleStaticDepthLinear(endUV)<=0.0?1.0:0.0;
        }

        float2 uv=SLH53RayUV(r,lambda);
        if(!SLH53InsideScreen(uv)||!SLH53InsideFirestormWorld(uv))return 1.0;

        float exitLambda=SLH53TileExitLambda(r,lambda,mip);
        exitLambda=max(exitLambda,lambda+epsLambda);
        exitLambda=min(exitLambda,1.0);

        float midLambda=(lambda+exitLambda)*0.5;
        float2 sampleUV=SLH53RayUV(r,midLambda);
        float2 scene=SLH53SampleInterval(sampleUV,mip);
        bool occupied=scene.y>0.0&&scene.x<=scene.y&&scene.x<SLH53_EMPTY*0.5;
        float d0=SLH53RayDepth(r,lambda);
        float d1=SLH53RayDepth(r,exitLambda);
        float rayMin=min(d0,d1),rayMax=max(d0,d1);
        float front=max(SLH53FrontTolerance,0.0);
        float back=max(SLH53Thickness,front+0.0001);

        // overlap catches an ordinary surface slab. behindInterval catches a ray
        // already hidden behind the nearest static interval even when normal hit
        // refinement did not produce an accepted SSR intersection.
        bool overlap=occupied&&rayMax>=max(scene.x-front,0.0)&&rayMin<=scene.y+back;
        bool behindInterval=occupied&&rayMin>scene.y+back;
        bool possibleBlock=overlap||behindInterval;

        if(possibleBlock&&mip>0){mip-=1;continue;}

        if(possibleBlock&&mip==0&&midLambda>selfGuardLambda)
        {
            // Fresh full-resolution Dstatic is authoritative for RED, matching the
            // production tracer's final-depth authority without changing its hit.
            float freshDepth=SLH53SampleStaticDepthLinear(sampleUV);
            if(freshDepth>0.0)
            {
                bool freshOverlap=rayMax>=max(freshDepth-front,0.0)&&rayMin<=freshDepth+back;
                bool freshBehind=rayMin>freshDepth+back;
                if(freshOverlap||freshBehind)return 2.0;
            }
        }

        lambda=min(exitLambda+epsLambda,1.0);
        mip=min(mip+1,SLH53_TOP_MIP);
    }

    return 0.0;
}
'''
    # Find the now-renamed source's exact production function and insert after it.
    out_trace_a, out_trace_b = function_span(s, "bool SLH53TraceWorld(")
    s = s[:out_trace_b] + classifier + s[out_trace_b:]

    s = replace_once(
        s,
        "         (SSRDisplayMode >= 22 && SSRDisplayMode <= 33) || SSRDisplayMode == 37 || SSRDisplayMode == 38);",
        "         (SSRDisplayMode >= 22 && SSRDisplayMode <= 33) || SSRDisplayMode == 37 || SSRDisplayMode == 38 || SSRDisplayMode == 39);"
    )
    s = replace_once(
        s,
        "    bool needHiZWorld = (SSRWorldTracerAB != 0) || SSRDisplayMode == 38;",
        "    bool needHiZWorld = (SSRWorldTracerAB != 0) || SSRDisplayMode == 38 || SSRDisplayMode == 39;"
    )

    diagnostic = r'''    if (SSRDisplayMode == 39)
    {
        // GREEN is the existing accepted WORLD result. A geometry hit rejected by
        // existing confidence policy is still static occlusion, therefore RED.
        if (hizWorldAccepted)
            return float4(0.0, 1.0, 0.0, 1.0);
        if (hizWorldGeometryHit)
            return float4(1.0, 0.0, 0.0, 1.0);

        float environmentVisibility=SLH53ClassifyEnvironmentVisibility(uv);
        if(environmentVisibility>1.5)
            return float4(1.0, 0.0, 0.0, 1.0);
        if(environmentVisibility>0.5)
            return float4(0.0, 0.0, 1.0, 1.0);
        return 0.0;
    }

'''
    s = replace_once(s, "    bool useHiZWorld = SSRWorldTracerAB != 0;\n",
                     diagnostic + "    bool useHiZWorld = SSRWorldTracerAB != 0;\n")

    s = replace_once(
        s,
        "    if (SSRDisplayMode == 30 || SSRDisplayMode == 31 || SSRDisplayMode == 32 || SSRDisplayMode == 33 || SSRDisplayMode == 37 || SSRDisplayMode == 38)\n",
        "    if (SSRDisplayMode == 30 || SSRDisplayMode == 31 || SSRDisplayMode == 32 || SSRDisplayMode == 33 || SSRDisplayMode == 37 || SSRDisplayMode == 38 || SSRDisplayMode == 39)\n"
    )

    s = replace_once(s, "technique SL_SSR_CORE_SPATIAL_HIZ_v1_0",
                     "technique SL_SSR_CORE_SPATIAL_HIZ_ENV_OCCLUSION_DIAG_v0_1")
    s = replace_once(s, '    ui_label = "CORE+SPATIAL — Hi-Z v0.53 WORLD A/B v1.0";',
                     '    ui_label = "CORE+SPATIAL — Hi-Z v0.53 ENV OCCLUSION DIAG v0.1";')
    s = replace_once(
        s,
        '    ui_tooltip = "Accepted v0.5 CORE+SPATIAL with validated Hi-Z v0.53 transplanted into WORLD/Dstatic only. Temporary WORLD tracer A/B selector retained; AVATAR, arbitration, Raw/Meta, Spatial and composite remain unchanged.";',
        '    ui_tooltip = "Diagnostic only: GREEN accepted WORLD hit, BLUE unobstructed Dstatic escape, RED static occlusion without environment eligibility. Production hit/composite behavior is unchanged outside mode 39.";'
    )

    # Contract guards: existing accepted WORLD and AVATAR tracers must remain
    # byte-for-byte unchanged, and the corrected normalized-TEXCOORD mapping stays.
    check_trace_a, check_trace_b = function_span(s, "bool SLH53TraceWorld(")
    if s[check_trace_a:check_trace_b] != trace_world_exact:
        raise SystemExit("SLH53TraceWorld changed")
    check_avatar_a, check_avatar_b = function_span(s, "bool TraceSSR(")
    if s[check_avatar_a:check_avatar_b] != avatar_trace_exact:
        raise SystemExit("TraceSSR changed")
    if "SSRFullResPixelCoord" in s or "SSRFullResScreenUV" in s:
        raise SystemExit("forbidden SV_Position raster remap restored")
    if "float4 SSRTracePS(float4 pos : SV_Position, float2 uv : TEXCOORD" not in s:
        raise SystemExit("Trace normalized TEXCOORD contract missing")
    for name in ("SLEOD01RawTex", "SLEOD01MetaTex", "SLEOD01BlurHTex", "SLEOD01ResolvedTex"):
        m = re.search(r"texture " + name + r"\s*\{([^}]*)\}", s, re.S)
        if not m or "Width = BUFFER_WIDTH;" not in m.group(1) or "Height = BUFFER_HEIGHT;" not in m.group(1):
            raise SystemExit(f"full-resolution private RT contract failed: {name}")
    if s.count("{") != s.count("}"):
        raise SystemExit("brace imbalance")

    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, type=Path,
                    help="exact generated production SL_SSR_CORE_SPATIAL_HIZ_v1_0.fx")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent / OUTPUT_NAME)
    args = ap.parse_args()

    text = build(args.base)
    args.out.write_text(text, encoding="utf-8", newline="\n")
    actual = hashlib.sha256(args.out.read_bytes()).hexdigest()
    print(args.out)
    print("SHA-256", actual)
    if OUTPUT_SHA256 != "__OUTPUT_SHA256__" and actual != OUTPUT_SHA256:
        raise SystemExit(f"output SHA-256 mismatch: {actual} != {OUTPUT_SHA256}")
    print("PASS")


if __name__ == "__main__":
    main()
