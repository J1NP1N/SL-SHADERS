// SLHiZTraceLink.cpp
// Links SL Hi-Z v0.1b private pyramid textures and the v0.35 raw SSR buffer
// into semantics consumed by SL_HiZ_Trace_v0_1_Compare.fx.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <reshade.hpp>
#include <cstdint>

static constexpr const char *kHiZEffect = "SL_HiZ_v0_1b_Infrastructure.fx";
static constexpr const char *kOldSSREffect = "SL_SSR_v0_35_LegacyResolve.fx";
static constexpr const char *kTraceEffect = "SL_HiZ_Trace_v0_1_Compare.fx";

static bool bind_texture(reshade::api::effect_runtime *runtime, const char *effect, const char *variable_name, const char *semantic)
{
    const auto var = runtime->find_texture_variable(effect, variable_name);
    if (var.handle == 0) return false;
    reshade::api::resource_view srv = {0}, srv_srgb = {0};
    runtime->get_texture_binding(var, &srv, &srv_srgb);
    if (srv.handle == 0) return false;
    if (srv_srgb.handle == 0) srv_srgb = srv;
    runtime->update_texture_bindings(semantic, srv, srv_srgb);
    return true;
}

static void set_float(reshade::api::effect_runtime *runtime, const char *name, float v)
{
    const auto dst = runtime->find_uniform_variable(kTraceEffect, name);
    if (dst.handle != 0) runtime->set_uniform_value_float(dst, &v, 1);
}
static void mirror_float(reshade::api::effect_runtime *runtime, const char *name)
{
    const auto src = runtime->find_uniform_variable(kOldSSREffect, name);
    const auto dst = runtime->find_uniform_variable(kTraceEffect, name);
    if (src.handle == 0 || dst.handle == 0) return;
    float v = 0.0f;
    runtime->get_uniform_value_float(src, &v, 1);
    runtime->set_uniform_value_float(dst, &v, 1);
}

static void on_begin_effects(reshade::api::effect_runtime *runtime, reshade::api::command_list *, reshade::api::resource_view, reshade::api::resource_view)
{
    bool hiz_ok = true;
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel0Tex", "SL_HIZ_L0");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel1Tex", "SL_HIZ_L1");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel2Tex", "SL_HIZ_L2");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel3Tex", "SL_HIZ_L3");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel4Tex", "SL_HIZ_L4");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel5Tex", "SL_HIZ_L5");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel6Tex", "SL_HIZ_L6");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel7Tex", "SL_HIZ_L7");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel8Tex", "SL_HIZ_L8");
    hiz_ok &= bind_texture(runtime, kHiZEffect, "SLHiZLevel9Tex", "SL_HIZ_L9");

    const bool old_raw_ok = bind_texture(runtime, kOldSSREffect, "SLSSRRawTex", "SL_SSR_V035_RAW");
    set_float(runtime, "SLHiZTraceLinkValid", hiz_ok ? 1.0f : 0.0f);
    set_float(runtime, "SLHiZOldRawValid", old_raw_ok ? 1.0f : 0.0f);

    // Mirror the v0.35 receiver/trace contract. This keeps the comparison fair
    // without duplicating UI tuning in two effects.
    mirror_float(runtime, "SSRThickness");
    mirror_float(runtime, "SSRRayOriginBias");
    mirror_float(runtime, "SSRMaxDistance");
    mirror_float(runtime, "SSREdgeFade");
    mirror_float(runtime, "SSRDistanceFadeStart");
    mirror_float(runtime, "LegacySpecularScale");
    mirror_float(runtime, "LegacyEnvScale");
    mirror_float(runtime, "LegacyFallbackThreshold");
    mirror_float(runtime, "LegacyDielectricFallback");
    mirror_float(runtime, "LegacyMinReflectivity");
    mirror_float(runtime, "PBRStrength");
    mirror_float(runtime, "PBRRoughnessPower");
}

extern "C" __declspec(dllexport) const char *NAME = "SL Hi-Z Trace Link";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Links the validated SL Hi-Z depth pyramid and v0.35 raw SSR to the standalone Hi-Z tracer comparison effect.";

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        if (!reshade::register_addon(hModule)) return FALSE;
        reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin_effects);
    }
    else if (reason == DLL_PROCESS_DETACH)
    {
        reshade::unregister_addon(hModule);
    }
    return TRUE;
}
