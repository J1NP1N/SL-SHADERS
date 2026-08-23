// SLSSRTemporalLink.cpp
// ReShade add-on: binds v0.35 private SSR textures to semantics consumed by
// SL_SSR_Temporal_v0_1.fx, and mirrors v0.35 composite controls to the consumer.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <reshade.hpp>
#include <cstdint>

static uint32_t g_frame_index = 0;
static constexpr const char *kProducerEffect = "SL_SSR_v0_35_LegacyResolve.fx";
static constexpr const char *kConsumerEffect = "SL_SSR_Temporal_v0_1.fx";

static bool bind_texture(reshade::api::effect_runtime *runtime, const char *variable_name, const char *semantic)
{
    const auto var = runtime->find_texture_variable(kProducerEffect, variable_name);
    if (var.handle == 0)
        return false;
    reshade::api::resource_view srv = { 0 }, srv_srgb = { 0 };
    runtime->get_texture_binding(var, &srv, &srv_srgb);
    if (srv.handle == 0)
        return false;
    if (srv_srgb.handle == 0)
        srv_srgb = srv;
    runtime->update_texture_bindings(semantic, srv, srv_srgb);
    return true;
}

static void set_consumer_float(reshade::api::effect_runtime *runtime, const char *name, float value)
{
    const auto dst = runtime->find_uniform_variable(kConsumerEffect, name);
    if (dst.handle != 0) runtime->set_uniform_value_float(dst, &value, 1);
}
static void set_consumer_int(reshade::api::effect_runtime *runtime, const char *name, int32_t value)
{
    const auto dst = runtime->find_uniform_variable(kConsumerEffect, name);
    if (dst.handle != 0) runtime->set_uniform_value_int(dst, &value, 1);
}
static void mirror_float(reshade::api::effect_runtime *runtime, const char *name)
{
    const auto src = runtime->find_uniform_variable(kProducerEffect, name);
    const auto dst = runtime->find_uniform_variable(kConsumerEffect, name);
    if (src.handle == 0 || dst.handle == 0) return;
    float v = 0.0f; runtime->get_uniform_value_float(src, &v, 1); runtime->set_uniform_value_float(dst, &v, 1);
}
static void mirror_int(reshade::api::effect_runtime *runtime, const char *name)
{
    const auto src = runtime->find_uniform_variable(kProducerEffect, name);
    const auto dst = runtime->find_uniform_variable(kConsumerEffect, name);
    if (src.handle == 0 || dst.handle == 0) return;
    int32_t v = 0; runtime->get_uniform_value_int(src, &v, 1); runtime->set_uniform_value_int(dst, &v, 1);
}

static void on_begin_effects(reshade::api::effect_runtime *runtime, reshade::api::command_list *, reshade::api::resource_view, reshade::api::resource_view)
{
    ++g_frame_index;
    const bool resolved_ok = bind_texture(runtime, "SLSSRResolvedTex", "SL_SSR_RESOLVED");
    const bool meta_ok = bind_texture(runtime, "SLSSRMetaTex", "SL_SSR_META");
    set_consumer_float(runtime, "SLSSRTemporalLinkValid", (resolved_ok && meta_ok) ? 1.0f : 0.0f);
    set_consumer_int(runtime, "SLSSRTemporalFrameIndex", static_cast<int32_t>(g_frame_index));

    mirror_float(runtime, "SSRStrength");
    mirror_float(runtime, "SSRBaseReplacement");
    mirror_float(runtime, "SSRMinConfidence");
    mirror_int(runtime, "SSRLongRayFadeEnable");
    mirror_float(runtime, "SSRLongRayDistanceStart");
    mirror_float(runtime, "SSRLongRayDistanceEnd");
    mirror_float(runtime, "SSRLongRayStretchStartPx");
    mirror_float(runtime, "SSRLongRayStretchEndPx");
    mirror_float(runtime, "LegacySpecularScale");
    mirror_float(runtime, "LegacyEnvScale");
    mirror_float(runtime, "LegacyFallbackThreshold");
    mirror_float(runtime, "LegacyDielectricFallback");
    mirror_float(runtime, "PBRStrength");
    mirror_float(runtime, "PBRRoughnessPower");
    mirror_float(runtime, "AlphaReceiverProtection");
}

extern "C" __declspec(dllexport) const char *NAME = "SL SSR Temporal Link";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Links SL SSR v0.35 resolved/meta textures into a standalone temporal ReShade effect.";

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
