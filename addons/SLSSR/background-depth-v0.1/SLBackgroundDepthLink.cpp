// SLBackgroundDepthLink.cpp
// ReShade add-on for the Firestorm-native SL SSR background-depth v0.1 pass.
//
// The patched Firestorm executable exports:
//   SL_SetSSRBackgroundDepthEnabled(int)
//   SL_GetSSRBackgroundDepthInfo(unsigned int*, unsigned int*, unsigned int*)
//
// The add-on enables the native pass and binds its OpenGL depth texture to the
// custom ReShade semantic SL_DEPTH_BACKGROUND.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <reshade.hpp>
#include <cstdint>

static constexpr const char *kEffect = "SL_BackgroundDepth_v0_1.fx";
static constexpr uint32_t kGLTexture2D = 0x0DE1u;

using get_info_fn = int (__cdecl *)(unsigned int *, unsigned int *, unsigned int *);
using set_enabled_fn = void (__cdecl *)(int);

static get_info_fn g_get_info = nullptr;
static set_enabled_fn g_set_enabled = nullptr;
static bool g_armed = false;

static void resolve_exports()
{
    if (g_get_info != nullptr && g_set_enabled != nullptr)
        return;

    const HMODULE exe = GetModuleHandleW(nullptr);
    if (exe == nullptr)
        return;

    g_get_info = reinterpret_cast<get_info_fn>(
        GetProcAddress(exe, "SL_GetSSRBackgroundDepthInfo"));
    g_set_enabled = reinterpret_cast<set_enabled_fn>(
        GetProcAddress(exe, "SL_SetSSRBackgroundDepthEnabled"));
}

static void set_valid(reshade::api::effect_runtime *runtime, float valid)
{
    const auto var = runtime->find_uniform_variable(kEffect, "SLBackgroundDepthValid");
    if (var.handle != 0)
        runtime->set_uniform_value_float(var, &valid, 1);
}

static void set_size(reshade::api::effect_runtime *runtime, float w, float h)
{
    const auto var = runtime->find_uniform_variable(kEffect, "SLBackgroundDepthSize");
    if (var.handle != 0)
    {
        const float values[2] = { w, h };
        runtime->set_uniform_value_float(var, values, 2);
    }
}

static void on_begin_effects(
    reshade::api::effect_runtime *runtime,
    reshade::api::command_list *,
    reshade::api::resource_view,
    reshade::api::resource_view)
{
    resolve_exports();

    if (g_set_enabled == nullptr || g_get_info == nullptr)
    {
        set_valid(runtime, 0.0f);
        return;
    }

    // Firestorm renders before ReShade effects. Enabling here means the first
    // usable auxiliary frame is the next game frame.
    g_set_enabled(1);

    unsigned int texture = 0, width = 0, height = 0;
    const bool native_ok = g_get_info(&texture, &width, &height) != 0 &&
                           texture != 0 && width != 0 && height != 0;

    if (!native_ok)
    {
        set_valid(runtime, 0.0f);
        g_armed = true;
        return;
    }

    // ReShade's OpenGL backend represents a non-standalone texture view as
    // (GL target << 40) | GLuint. This matches make_resource_view_handle()
    // in the ReShade OpenGL implementation pinned for this prototype.
    const reshade::api::resource_view depth_view = {
        (static_cast<uint64_t>(kGLTexture2D) << 40) |
        static_cast<uint64_t>(texture)
    };

    runtime->update_texture_bindings(
        "SL_DEPTH_BACKGROUND", depth_view, depth_view);

    set_size(runtime, static_cast<float>(width), static_cast<float>(height));
    set_valid(runtime, g_armed ? 1.0f : 0.0f);
    g_armed = true;
}

extern "C" __declspec(dllexport) const char *NAME =
    "SL SSR Background Depth Link";
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "Publishes Firestorm's camera-aligned static background depth as SL_DEPTH_BACKGROUND.";

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
