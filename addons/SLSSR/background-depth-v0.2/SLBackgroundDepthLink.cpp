// SLBackgroundDepthLink_v0_2_2.cpp
// ReShade add-on for Firestorm-native SSR background depth.
//
// v0.2.2 does NOT bind Firestorm depth attachments directly.
// Instead it mirrors ReShade's Generic Depth strategy:
//   native Firestorm depth texture -> ReShade-owned shader-readable backup -> FX semantic.

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

struct depth_backup
{
    unsigned int source_texture = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    reshade::api::format format = reshade::api::format::unknown;
    reshade::api::resource resource = { 0 };
    reshade::api::resource_view view = { 0 };
};

static depth_backup g_primary;
static depth_backup g_background;

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

static reshade::api::resource make_gl_texture_resource(unsigned int texture)
{
    return reshade::api::resource {
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

static void destroy_backup(reshade::api::device *device, depth_backup &backup)
{
    if (device != nullptr)
    {
        if (backup.view.handle != 0)
            device->destroy_resource_view(backup.view);
        if (backup.resource.handle != 0)
            device->destroy_resource(backup.resource);
    }

    backup = {};
}

static bool ensure_backup(
    reshade::api::device *device,
    unsigned int source_texture,
    uint32_t expected_width,
    uint32_t expected_height,
    depth_backup &backup)
{
    if (device == nullptr || source_texture == 0)
        return false;

    const reshade::api::resource source = make_gl_texture_resource(source_texture);
    reshade::api::resource_desc source_desc = device->get_resource_desc(source);

    if (source_desc.type != reshade::api::resource_type::texture_2d ||
        source_desc.texture.width == 0 ||
        source_desc.texture.height == 0 ||
        source_desc.texture.format == reshade::api::format::unknown)
    {
        return false;
    }

    if (expected_width != 0 && source_desc.texture.width != expected_width)
        return false;
    if (expected_height != 0 && source_desc.texture.height != expected_height)
        return false;

    if (backup.source_texture == source_texture &&
        backup.width == source_desc.texture.width &&
        backup.height == source_desc.texture.height &&
        backup.format == source_desc.texture.format &&
        backup.resource.handle != 0 &&
        backup.view.handle != 0)
    {
        return true;
    }

    destroy_backup(device, backup);

    reshade::api::resource_desc backup_desc = source_desc;
    backup_desc.type = reshade::api::resource_type::texture_2d;
    backup_desc.heap = reshade::api::memory_heap::default_;
    backup_desc.usage =
        reshade::api::resource_usage::shader_resource |
        reshade::api::resource_usage::copy_dest;

    if (backup_desc.texture.samples != 1)
        return false;

    if (!device->create_resource(
            backup_desc,
            nullptr,
            reshade::api::resource_usage::copy_dest,
            &backup.resource))
    {
        destroy_backup(device, backup);
        return false;
    }

    const reshade::api::resource_view_desc view_desc(backup_desc.texture.format);

    if (!device->create_resource_view(
            backup.resource,
            reshade::api::resource_usage::shader_resource,
            view_desc,
            &backup.view))
    {
        destroy_backup(device, backup);
        return false;
    }

    backup.source_texture = source_texture;
    backup.width = backup_desc.texture.width;
    backup.height = backup_desc.texture.height;
    backup.format = backup_desc.texture.format;

    return true;
}

static bool copy_depth(
    reshade::api::command_list *cmd_list,
    unsigned int source_texture,
    const depth_backup &backup)
{
    if (cmd_list == nullptr ||
        source_texture == 0 ||
        backup.resource.handle == 0 ||
        backup.view.handle == 0)
    {
        return false;
    }

    const reshade::api::resource source = make_gl_texture_resource(source_texture);
    cmd_list->copy_resource(source, backup.resource);
    return true;
}

static void on_begin_effects(
    reshade::api::effect_runtime *runtime,
    reshade::api::command_list *cmd_list,
    reshade::api::resource_view,
    reshade::api::resource_view)
{
    resolve_exports();

    if (g_set_enabled == nullptr || g_get_primary == nullptr || g_get_background == nullptr)
    {
        invalidate(runtime);
        return;
    }

    g_set_enabled(1);

    unsigned int primary_texture = 0, primary_width = 0, primary_height = 0;
    unsigned int background_texture = 0, background_width = 0, background_height = 0;

    const bool primary_native_ok =
        g_get_primary(&primary_texture, &primary_width, &primary_height) != 0 &&
        primary_texture != 0 && primary_width != 0 && primary_height != 0;

    const bool background_native_ok =
        g_get_background(&background_texture, &background_width, &background_height) != 0 &&
        background_texture != 0 && background_width != 0 && background_height != 0;

    reshade::api::device *const device = runtime->get_device();

    if (!primary_native_ok ||
        !background_native_ok ||
        device == nullptr ||
        device->get_api() != reshade::api::device_api::opengl)
    {
        invalidate(runtime);
        g_armed = true;
        return;
    }

    const bool primary_backup_ok =
        ensure_backup(device, primary_texture, primary_width, primary_height, g_primary);
    const bool background_backup_ok =
        ensure_backup(device, background_texture, background_width, background_height, g_background);

    if (!primary_backup_ok || !background_backup_ok)
    {
        invalidate(runtime);
        g_armed = true;
        return;
    }

    if (!copy_depth(cmd_list, primary_texture, g_primary) ||
        !copy_depth(cmd_list, background_texture, g_background))
    {
        invalidate(runtime);
        g_armed = true;
        return;
    }

    runtime->update_texture_bindings(
        "SL_DEPTH_PRIMARY_NATIVE", g_primary.view, g_primary.view);
    runtime->update_texture_bindings(
        "SL_DEPTH_BACKGROUND", g_background.view, g_background.view);

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
    "SL SSR Background Depth Link v0.2.2";
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "Copies Firestorm native depth attachments into ReShade-owned shader-readable backups.";

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

        g_primary = {};
        g_background = {};

        reshade::unregister_addon(hModule);
    }

    return TRUE;
}
