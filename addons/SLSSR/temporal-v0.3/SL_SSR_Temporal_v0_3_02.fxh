
// -----------------------------------------------------------------------------
// Temporal controls.
// -----------------------------------------------------------------------------
uniform int SSRTemporalEnable
<
    ui_label = "Temporal Accumulation";
    ui_tooltip = "Temporally reproject only the SSR contribution captured around the accepted CORE.";
    ui_type = "slider";
    ui_min = 0; ui_max = 1;
> = 1;

uniform float SSRTemporalHistoryWeight
<
    ui_label = "Temporal History Weight";
    ui_tooltip = "Maximum previous-frame contribution after all rejection tests.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.97; ui_step = 0.01;
> = 0.88;

uniform float SSRTemporalDepthTolerance
<
    ui_label = "Depth Rejection";
    ui_tooltip = "Minimum previous-frame view-depth tolerance. A relative depth term is added automatically.";
    ui_type = "drag";
    ui_min = 0.002; ui_max = 0.25; ui_step = 0.002;
> = 0.015;

uniform float SSRTemporalNormalThreshold
<
    ui_label = "Normal Agreement";
    ui_tooltip = "Minimum reprojected receiver-normal agreement.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.99; ui_step = 0.01;
> = 0.90;

uniform float SSRTemporalEdgeMarginPx
<
    ui_label = "Screen Edge Reject (px)";
    ui_tooltip = "Reject history when current or reprojected coordinates are too close to the screen edge.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 32.0; ui_step = 0.5;
> = 3.0;

uniform float SSRTemporalCameraCutThreshold
<
    ui_label = "Camera Cut Threshold";
    ui_tooltip = "Maximum allowed element delta from identity in the current-to-previous view transform. Lower values reset on faster camera changes.";
    ui_type = "drag";
    ui_min = 0.02; ui_max = 2.0; ui_step = 0.01;
> = 0.35;
