// SL_SSR_Temporal_v0_3_AvatarReactive.fx
// Temporal accumulation/reprojection wrapper with animated-reflection reactive rejection.
// Required order:
//   TEMPORAL PRE — v0.3 Capture
//   CORE — accepted CORE+SPATIAL production core
//   TEMPORAL POST — v0.3 Avatar-Reactive Resolve
//
// Split source is intentional: numbered helper includes are part of this runtime milestone.

#include "ReShade.fxh"
#include "SL_SSR_Temporal_v0_3_01.fxh"
#include "SL_SSR_Temporal_v0_3_02.fxh"
#include "SL_SSR_Temporal_v0_3_03.fxh"
#include "SL_SSR_Temporal_v0_3_04.fxh"
#include "SL_SSR_Temporal_v0_3_05.fxh"
#include "SL_SSR_Temporal_v0_3_06.fxh"
#include "SL_SSR_Temporal_v0_3_07.fxh"
#include "SL_SSR_Temporal_v0_3_08.fxh"
#include "SL_SSR_Temporal_v0_3_09.fxh"
#include "SL_SSR_Temporal_v0_3_10.fxh"
#include "SL_SSR_Temporal_v0_3_11.fxh"
#include "SL_SSR_Temporal_v0_3_12.fxh"
#include "SL_SSR_Temporal_v0_3_13.fxh"
#include "SL_SSR_Temporal_v0_3_14.fxh"
#include "SL_SSR_Temporal_v0_3_15.fxh"
#include "SL_SSR_Temporal_v0_3_16.fxh"
#include "SL_SSR_Temporal_v0_3_17.fxh"
