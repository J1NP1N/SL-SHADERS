// SLNativeAlphaLink.cpp
// Firestorm native alpha-geometry -> ReShade semantic bridge.
//
// Mirrors the already validated native depth bridge strategy:
// native OpenGL textures -> ReShade-owned shader-readable backups -> FX semantics.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <reshade.hpp>
#include <cstdint>

static constexpr uint32_t kGLTexture2D = 0x0DE1u;
static constexpr const char *kProofEffect = "SL_NativeAlphaProof_v0_1.fx";
static constexpr const char *kGTAOEffect  = "SL_GTAO_v0_14_NativeAlphaGeometry.fx";

using get_info_fn = int (__cdecl *)(unsigned int *, unsigned int *, unsigned int *);
using set_enabled_fn = void (__cdecl *)(int);

static get_info_fn g_get_material = nullptr;
static get_info_fn g_get_depth = nullptr;
static get_info_fn g_get_coverage = nullptr;
static set_enabled_fn g_set_enabled = nullptr;
static bool g_armed = false;

struct resource_backup
{
    unsigned int source_texture = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    reshade::api::format format = reshade::api::format::unknown;
    reshade::api::resource resource = { 0 };
    reshade::api::resource_view view = { 0 };
};

static resource_backup g_material;
static resource_backup g_depth;
static resource_backup g_coverage;

static void resolve_exports()
{
    if (g_get_material != nullptr && g_get_depth != nullptr &&
        g_get_coverage != nullptr && g_set_enabled != nullptr)
        return;

    const HMODULE exe = GetModuleHandleW(nullptr);
    if (exe == nullptr)
        return;

    g_get_material = reinterpret_cast<get_info_fn>(
        GetProcAddress(exe, "SL_GetAlphaMaterialInfo"));
    g_get_depth = reinterpret_cast<get_info_fn>(
        GetProcAddress(exe, "SL_GetAlphaDepthInfo"));
    g_get_coverage = reinterpret_cast<get_info_fn>(
        GetProcAddress(exe, "SL_GetAlphaCoverageInfo"));
    g_set_enabled = reinterpret_cast<set_enabled_fn>(
        GetProcAddress(exe, "SL_SetAlphaGeometryEnabled"));
}

static reshade::api::resource make_gl_texture_resource(unsigned int texture)
{
    return reshade::api::resource {
        (static_cast<uint64_t>(kGLTexture2D) << 40) |
        static_cast<uint64_t>(texture)
    };
}

static void set_float_for_effect(
    reshade::api::effect_runtime *runtime,
    const char *effect,
    const char *name,
    float value)
{
    const auto var = runtime->find_uniform_variable(effect, name);
    if (var.handle != 0)
        runtime->set_uniform_value_float(var, &value, 1);
}

static void set_float2_for_effect(
    reshade::api::effect_runtime *runtime,
    const char *effect,
    const char *name,
    float x,
    float y)
{
    const auto var = runtime->find_uniform_variable(effect, name);
    if (var.handle != 0)
    {
        const float values[2] = { x, y };
        runtime->set_uniform_value_float(var, values, 2);
    }
}

static void set_float_all(
    reshade::api::effect_runtime *runtime,
    const char *name,
    float value)
{
    set_float_for_effect(runtime, kProofEffect, name, value);
    set_float_for_effect(runtime, kGTAOEffect, name, value);
}

static void set_float2_all(
    reshade::api::effect_runtime *runtime,
    const char *name,
    float x,
    float y)
{
    set_float2_for_effect(runtime, kProofEffect, name, x, y);
    set_float2_for_effect(runtime, kGTAOEffect, name, x, y);
}

static void invalidate(reshade::api::effect_runtime *runtime)
{
    set_float_all(runtime, "SLAlphaMaterialValid", 0.0f);
    set_float_all(runtime, "SLAlphaDepthNativeValid", 0.0f);
    set_float_all(runtime, "SLAlphaCoverageValid", 0.0f);
}

static void destroy_backup(reshade::api::device *device, resource_backup &backup)
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
    resource_backup &backup)
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
    if (source_desc.texture.samples != 1)
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

static bool copy_resource(
    reshade::api::command_list *cmd_list,
    unsigned int source_texture,
    const resource_backup &backup)
{
    if (cmd_list == nullptr || source_texture == 0 ||
        backup.resource.handle == 0 || backup.view.handle == 0)
        return false;

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

    if (g_set_enabled == nullptr || g_get_material == nullptr ||
        g_get_depth == nullptr || g_get_coverage == nullptr)
    {
        invalidate(runtime);
        return;
    }

    // The pre-deferred capture has already happened for this frame. Arming here
    // therefore makes the following frame authoritative; valid stays zero once.
    g_set_enabled(1);

    unsigned int material_texture = 0, material_width = 0, material_height = 0;
    unsigned int depth_texture = 0, depth_width = 0, depth_height = 0;
    unsigned int coverage_texture = 0, coverage_width = 0, coverage_height = 0;

    const bool material_native_ok =
        g_get_material(&material_texture, &material_width, &material_height) != 0 &&
        material_texture != 0 && material_width != 0 && material_height != 0;
    const bool depth_native_ok =
        g_get_depth(&depth_texture, &depth_width, &depth_height) != 0 &&
        depth_texture != 0 && depth_width != 0 && depth_height != 0;
    const bool coverage_native_ok =
        g_get_coverage(&coverage_texture, &coverage_width, &coverage_height) != 0 &&
        coverage_texture != 0 && coverage_width != 0 && coverage_height != 0;

    reshade::api::device *const device = runtime->get_device();
    if (!material_native_ok || !depth_native_ok || !coverage_native_ok ||
        device == nullptr || device->get_api() != reshade::api::device_api::opengl)
    {
        invalidate(runtime);
        g_armed = true;
        return;
    }

    // All three semantics must be one native viewport.
    if (material_width != depth_width || material_height != depth_height ||
        material_width != coverage_width || material_height != coverage_height)
    {
        invalidate(runtime);
        g_armed = true;
        return;
    }

    if (!ensure_backup(device, material_texture, material_width, material_height, g_material) ||
        !ensure_backup(device, depth_texture, depth_width, depth_height, g_depth) ||
        !ensure_backup(device, coverage_texture, coverage_width, coverage_height, g_coverage))
    {
        invalidate(runtime);
        g_armed = true;
        return;
    }

    if (!copy_resource(cmd_list, material_texture, g_material) ||
        !copy_resource(cmd_list, depth_texture, g_depth) ||
        !copy_resource(cmd_list, coverage_texture, g_coverage))
    {
        invalidate(runtime);
        g_armed = true;
        return;
    }

    runtime->update_texture_bindings(
        "SL_ALPHA_MATERIAL", g_material.view, g_material.view);
    runtime->update_texture_bindings(
        "SL_DEPTH_ALPHA_NATIVE", g_depth.view, g_depth.view);
    runtime->update_texture_bindings(
        "SL_ALPHA_COVERAGE", g_coverage.view, g_coverage.view);

    set_float2_all(runtime, "SLAlphaMaterialSize",
        static_cast<float>(material_width), static_cast<float>(material_height));
    set_float2_all(runtime, "SLAlphaDepthNativeSize",
        static_cast<float>(depth_width), static_cast<float>(depth_height));
    set_float2_all(runtime, "SLAlphaCoverageSize",
        static_cast<float>(coverage_width), static_cast<float>(coverage_height));

    const float valid = g_armed ? 1.0f : 0.0f;
    set_float_all(runtime, "SLAlphaMaterialValid", valid);
    set_float_all(runtime, "SLAlphaDepthNativeValid", valid);
    set_float_all(runtime, "SLAlphaCoverageValid", valid);
    g_armed = true;
}

extern "C" __declspec(dllexport) const char *NAME =
    "SL Native Alpha Geometry Link v0.1";
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "Publishes Firestorm-classified alpha material, alpha depth and coverage semantics to ReShade.";

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

        g_material = {};
        g_depth = {};
        g_coverage = {};
        reshade::unregister_addon(hModule);
    }

    return TRUE;
}
