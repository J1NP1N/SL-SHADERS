
// -----------------------------------------------------------------------------
// Technique order is part of the contract. Keep only the accepted CORE+SPATIAL between these two.
// -----------------------------------------------------------------------------
technique SL_SSR_Temporal_v0_3_Capture
<
    ui_label = "TEMPORAL PRE — v0.3 Capture";
    ui_tooltip = "Place immediately BEFORE the accepted CORE+SPATIAL. Captures the pre-CORE backbuffer at half resolution.";
>
{
    pass CaptureBeforeSSR
    {
        VertexShader = PostProcessVS;
        PixelShader = CaptureBeforeSSRPS;
        RenderTarget = SLSSRPreCaptureTex;
    }
}

technique SL_SSR_Temporal_v0_3_Resolve
<
    ui_label = "TEMPORAL POST — v0.3 Avatar-Reactive Resolve";
    ui_tooltip = "Place immediately AFTER the accepted CORE+SPATIAL. Reprojects its captured SSR contribution with animated-content rejection.";
>
{
    pass CaptureCurrentContribution
    {
        VertexShader = PostProcessVS;
        PixelShader = CurrentSSRContributionPS;
        RenderTarget = SLSSRCurrentContributionTex;
    }

    pass TemporalResolve
    {
        VertexShader = PostProcessVS;
        PixelShader = TemporalResolvePS;
        RenderTarget0 = SLSSRTemporalTex;
        RenderTarget1 = SLSSRTemporalDebugTex;
        RenderTarget2 = SLSSRTemporalReactiveDebugTex;
    }

    pass CopyTemporalHistory
    {
        VertexShader = PostProcessVS;
        PixelShader = CopyTemporalHistoryPS;
        RenderTarget = SLSSRHistoryTex;
    }

    pass StoreHistoryGeometry
    {
        VertexShader = PostProcessVS;
        PixelShader = StoreHistoryGeometryPS;
        RenderTarget = SLSSRHistoryGeomTex;
    }

    pass CompositeCorrection
    {
        VertexShader = PostProcessVS;
        PixelShader = TemporalCompositeCorrectionPS;
    }
}
