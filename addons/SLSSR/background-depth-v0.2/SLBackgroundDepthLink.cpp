// SLBackgroundDepthLink.cpp
// ReShade add-on for Firestorm-native SSR background-depth v0.2.
//
// The patched Firestorm executable exports:
//   SL_SetSSRBackgroundDepthEnabled(int)
//   SL_GetSSRPrimaryDepthInfo(unsigned int*, unsigned int*, unsigned int*)
//   SL_GetSSRBackgroundDepthInfo(unsigned int*, unsigned int*, unsigned int*)
//
// v0.2 binds both Firestorm-native depth textures so the diagnostic no longer
// depends on ReShade's generic SL_DEPTH selection.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <reshade.hpp>
#include <cstdint>

static constexpr const char *kEffect = "SL_BackgroundDepth_v0_2.fx";
static constexpr uint32_t kGLTexture2D = 0x0DE1u;

using get_info_fn = int (__cdecl *)(unsigned int *, unsigned int *, unsigned int *);
using set_enabled_fn = void (__cdecl *)(int);

static get_info_fn g_get_primary = nullptr;
static get_info_fn g_get_background = nullptr;
static set_enabled_fn g_set_enabled = nullptr;
static bool g_armed = false;

static void resolve_exports()
{
    if (g_get_primary != nullptr && g_get_background != nullptr && g_set_enabled != nullptr)
        return;

    const HMODULE exe = GetModuleHandleW(nullptr);
    if (exe == nullptr)
        return;

    g_get_primary = reinterpret_cast<get_info_fn>(
        GetProcAddress(exe, "SL_GetSSRPrimaryDepthInfo"));
    g_get_background = reinterpret_cast<get_info_fn>(
        GetProcAddress(exe, "SL_GetSSRBackgroundDepthInfo"));
    g_set_enabled = reinterpret_cast<set_enabled_fn>(
        GetProcAddress(exe, "SL_SetSSRBackgroundDepthEnabled"));
}

static reshade::api::resource_view make_gl_texture_view(unsigned int texture)
{
    return reshade::api::resource_view {
        (static_cast<uint64_t>(kGLTexture2D) << 40) |
        static_cast<uint64_t>(texture)
    };
}

static void set_float(reshade::api::effect_runtime *runtime, const char *name, float value)
{
    const auto var = runtime->find_uniform_variable(kEffect, name);
    if (var.handle != 0)
        runtime->set_uniform_value_float(var, &value, 1);
}

static void set_float2(reshade::api::effect_runtime *runtime, const char *name, float x, float y)
{
    const auto var = runtime->find_uniform_variable(kEffect, name);
    if (var.handle != 0)
    {
        const float values[2] = { x, y };
        runtime->set_uniform_value_float(var, values, 2);
    }
}

static void invalidate(reshade::api::effect_runtime *runtime)
{
    set_float(runtime, "SLPrimaryDepthNativeValid", 0.0f);
    set_float(runtime, "SLBackgroundDepthValid", 0.0f);
}

static void on_begin_effects(
    reshade::api::effect_runtime *runtime,
    reshade::api::command_list *,
    reshade::api::resource_view,
    reshade::api::resource_view)
{
    resolve_exports();

    if (g_set_enabled == nullptr || g_get_primary == nullptr || g_get_background == nullptr)
    {
        invalidate(runtime);
        return;
    }

    // Firestorm renders before ReShade effects. Enabling here means the first
    // usable auxiliary frame is the next game frame.
    g_set_enabled(1);

    unsigned int primary_texture = 0, primary_width = 0, primary_height = 0;
    unsigned int background_texture = 0, background_width = 0, background_height = 0;

    const bool primary_ok =
        g_get_primary(&primary_texture, &primary_width, &primary_height) != 0 &&
        primary_texture != 0 && primary_width != 0 && primary_height != 0;

    const bool background_ok =
        g_get_background(&background_texture, &background_width, &background_height) != 0 &&
        background_texture != 0 && background_width != 0 && background_height != 0;

    if (!primary_ok || !background_ok)
    {
        invalidate(runtime);
        g_armed = true;
        return;
    }

    const auto primary_view = make_gl_texture_view(primary_texture);
    const auto background_view = make_gl_texture_view(background_texture);

    runtime->update_texture_bindings(
        "SL_DEPTH_PRIMARY_NATIVE", primary_view, primary_view);
    runtime->update_texture_bindings(
        "SL_DEPTH_BACKGROUND", background_view, background_view);

    set_float2(runtime, "SLPrimaryDepthNativeSize",
        static_cast<float>(primary_width), static_cast<float>(primary_height));
    set_float2(runtime, "SLBackgroundDepthSize",
        static_cast<float>(background_width), static_cast<float>(background_height));

    const float valid = g_armed ? 1.0f : 0.0f;
    set_float(runtime, "SLPrimaryDepthNativeValid", valid);
    set_float(runtime, "SLBackgroundDepthValid", valid);
    g_armed = true;
}

extern "C" __declspec(dllexport) const char *NAME =
    "SL SSR Background Depth Link v0.2";
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "Publishes Firestorm native primary and static-background depth for direct comparison.";

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        if (!reshade::register_addon(hModule))
            return FALSE;

        reshade::register_event<reshade::addon_event::reshade_begin_effects>(
            on_begin_effects);
    }
    else if (reason == DLL_PROCESS_DETACH)
    {
        resolve_exports();
        if (g_set_enabled != nullptr)
            g_set_enabled(0);

        reshade::unregister_addon(hModule);
    }

    return TRUE;
}
