
uniform float SSRTemporalContributionEpsilon
<
    ui_label = "Hit Transition Epsilon";
    ui_tooltip = "Presentation-space SSR contribution below this is treated as no current hit for temporal transition rejection.";
    ui_type = "drag";
    ui_min = 0.0001; ui_max = 0.05; ui_step = 0.0001;
> = 0.0015;

uniform float SSRTemporalClampExpansion
<
    ui_label = "Neighborhood Clamp";
    ui_tooltip = "Expands the current 3x3 SSR-contribution envelope before clamping history.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 0.20;

uniform float SSRTemporalRadianceRejectStart
<
    ui_label = "Radiance Reject Start";
    ui_tooltip = "Begin reducing stale history when it differs strongly from the current SSR contribution.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.12;

uniform float SSRTemporalRadianceRejectEnd
<
    ui_label = "Radiance Reject End";
    ui_tooltip = "Fully reject stale history by this normalized current/history difference.";
    ui_type = "drag";
    ui_min = 0.05; ui_max = 2.0; ui_step = 0.01;
> = 0.55;

uniform float SSRTemporalMotionStartPx
<
    ui_label = "Motion Trust Start (px)";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 16.0; ui_step = 0.25;
> = 1.5;

uniform float SSRTemporalMotionEndPx
<
    ui_label = "Motion Trust End (px)";
    ui_tooltip = "History reaches zero at this camera-reprojected motion magnitude.";
    ui_type = "drag";
    ui_min = 1.0; ui_max = 64.0; ui_step = 0.5;
> = 24.0;

uniform float SSRTemporalJitterPixels
<
    ui_label = "History Jitter (hard disabled)";
    ui_tooltip = "Compatibility control only. v0.3 never applies history jitter; the runtime requirement is hard-off.";
    ui_type = "drag";
    ui_min = 0.0; ui_max = 0.0; ui_step = 0.01;
> = 0.00;
