
uniform float SSRTemporalReactiveRejectStart
<
    ui_label = "Animated Content Reject Start";
    ui_tooltip = "Begin reducing history when its reflected content has no close RGB match in the current 3x3 contribution neighborhood.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.10;

uniform float SSRTemporalReactiveRejectEnd
<
    ui_label = "Animated Content Reject End";
    ui_tooltip = "Fully reject history when unsupported reflected-content divergence reaches this normalized distance.";
    ui_type = "drag";
    ui_min = 0.02; ui_max = 1.0; ui_step = 0.01;
> = 0.30;

uniform int SSRTemporalResetHistory
<
    ui_label = "Reset History";
    ui_tooltip = "Set to 1 for one frame to discard temporal history, then return to 0.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 0;

uniform int SSRTemporalDisplayMode
<
    ui_label = "Temporal Display";
    ui_type = "combo";
    ui_items =
        "Final temporal SSR\0"
        "Current SSR contribution\0"
        "Temporal SSR contribution\0"
        "History weight\0"
        "History rejection reason\0"
        "Reprojected motion\0"
        "Depth agreement\0"
        "Normal agreement\0"
        "Neighborhood clamp amount\0"
        "Camera cut status\0"
        "History jitter status (hard off)\0"
        "Correction magnitude\0"
        "Reactive gate audit (R=transition G=radiance B=unsupported)\0"
        "Reactive history trust\0";
> = 0;

uniform float SSRTemporalDebugGain
<
    ui_label = "Temporal Debug Gain";
    ui_type = "drag";
    ui_min = 0.25; ui_max = 32.0; ui_step = 0.25;
> = 6.0;
