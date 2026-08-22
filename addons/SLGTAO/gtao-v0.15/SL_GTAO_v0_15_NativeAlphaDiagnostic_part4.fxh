float4 GTAOCompositePS(float4 pos : SV_Position, float2 screenUV : TEXCOORD) : SV_Target
{
    float4 scene = tex2D(ReShade::BackBuffer, screenUV);

    if (GTAODisplayMode == 12)
        return scene;

    bool ready = GTAOInputsReady() && GTAOInsideFirestormWorld(screenUV);
    if (!ready)
    {
        if (GTAODisplayMode == 0)
            return scene;
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 nativeUV = GTAOFirestormUV(screenUV);
    float rawDepth = GTAORawDepthNative(nativeUV);
    bool geometry = !GTAOIsBackgroundDepth(rawDepth);

    if (GTAODisplayMode == 1)
    {
        float d = geometry ? GTAOViewDepthNative(nativeUV, rawDepth) : 0.0;
        return float4(GTAODepthViz(d).xxx, 1.0);
    }

    if (GTAODisplayMode == 2)
    {
        if (!geometry)
            return float4(0.0, 0.0, 0.0, 1.0);
        float3 n = GTAONormalNative(nativeUV);
        return float4(n * 0.5 + 0.5, 1.0);
    }

    if (GTAODisplayMode == 3)
    {
        float material = GTAOAlphaMaterialNative(nativeUV);
        return float4(material.xxx, 1.0);
    }

    if (GTAODisplayMode == 4)
    {
        float coverage = GTAOAlphaCoverageNative(nativeUV);
        return float4(coverage.xxx, 1.0);
    }

    if (GTAODisplayMode == 5)
    {
        float material =
            GTAOAlphaMaterialNative(nativeUV) >= GTAOAlphaMaterialThreshold
                ? 1.0
                : 0.0;
        float alphaRaw = GTAOAlphaRawDepthNative(nativeUV);
        float alphaDepth =
            material > 0.0 && !GTAOIsBackgroundDepth(alphaRaw)
                ? GTAOViewDepthNative(nativeUV, alphaRaw)
                : 0.0;
        return float4(GTAODepthViz(alphaDepth).xxx, 1.0);
    }

    if (GTAODisplayMode == 6)
    {
        float blockerWeight = GTAOAlphaBlockerWeightNative(nativeUV);
        return float4(blockerWeight.xxx, 1.0);
    }

    float rawAO = tex2D(SLGTAORawSampler, screenUV).r;
    float rawAlphaAwareAO =
        tex2D(SLGTAORawAlphaAwareSampler, screenUV).r;
    float filteredAO = tex2D(SLGTAOFilteredSampler, screenUV).r;

    if (GTAODisplayMode == 7)
        return float4(rawAO.xxx, 1.0);

    if (GTAODisplayMode == 8)
        return float4(rawAlphaAwareAO.xxx, 1.0);

    if (GTAODisplayMode == 9)
    {
        float reject = tex2D(SLGTAOEdgeSampler, screenUV).r;
        return float4(reject.xxx, 1.0);
    }

    if (GTAODisplayMode == 10)
        return float4(filteredAO.xxx, 1.0);

    float selectedAO =
        GTAOEnableDenoise != 0 ? filteredAO : rawAO;

    float finalAO = geometry
        ? saturate(1.0 - (1.0 - selectedAO) * max(GTAOStrength, 0.0))
        : 1.0;

    if (GTAODisplayMode == 11)
    {
        float contribution = 1.0 - finalAO;
        return float4(contribution.xxx, 1.0);
    }

    if (GTAOEnable == 0 || !geometry)
        return scene;

    return float4(scene.rgb * finalAO, scene.a);
}

technique SL_GTAO_v0_15_NativeAlphaDiagnostic
<
    ui_label = "GTAO — v0.15 Native Alpha Diagnostic";
    ui_tooltip = "Diagnostic milestone: D0 baseline remains final; validated native alpha material/depth/coverage feed a separate coverage-aware raw horizon pass for before/after proof.";
>
{
    pass DepthDiscontinuity
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAOEdgePS;
        RenderTarget = SLGTAOEdgeTex;
    }

    pass RawGTAO
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAORawPS;
        RenderTarget = SLGTAORawTex;
    }

    pass RawGTAOAlphaAware
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAORawAlphaAwarePS;
        RenderTarget = SLGTAORawAlphaAwareTex;
    }

    pass BilateralHorizontal
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAOFilterHPS;
        RenderTarget = SLGTAOFilterHTex;
    }

    pass BilateralVertical
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAOFilterVPS;
        RenderTarget = SLGTAOFilteredTex;
    }

    pass CompositeAndDiagnostics
    {
        VertexShader = PostProcessVS;
        PixelShader = GTAOCompositePS;
    }
}
