#include <imgui.h>
#include <reshade.hpp>
#include <Windows.h>

#include "slrenderbridge/BridgeCore.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>

static_assert(RESHADE_API_VERSION == 20, "SLRenderBridge Phase 1 was reviewed against ReShade add-on API 20");

namespace
{
using namespace reshade::api;

std::mutex g_mutex;
slrb::BridgeCore g_core;

struct RuntimeBindings
{
    resource_view albedo{};
    resource_view material{};
    resource_view normal_meta{};
    resource_view depth{};
};

slrb::ResourceRef describe_view(device *dev, resource_view view)
{
    slrb::ResourceRef out;
    if (view == 0)
        return out;

    const resource res = dev->get_resource_from_view(view);
    if (res == 0)
        return out;

    const resource_desc desc = dev->get_resource_desc(res);
    out.view = view.handle;
    out.resource = res.handle;
    out.width = desc.texture.width;
    out.height = desc.texture.height;
    out.format = static_cast<std::uint32_t>(desc.texture.format);
    out.usage = static_cast<std::uint32_t>(desc.usage);
    return out;
}

slrb::TargetSet describe_target(command_list *cmd_list, std::uint32_t count, const resource_view *rtvs, resource_view dsv)
{
    slrb::TargetSet target;
    device *const dev = cmd_list->get_device();
    target.color_count = count;
    target.color_count_overflow = count > slrb::kMaxColorAttachments;

    const std::uint32_t stored_count = std::min<std::uint32_t>(count, static_cast<std::uint32_t>(slrb::kMaxColorAttachments));
    for (std::uint32_t i = 0; i < stored_count; ++i)
        target.colors[i] = describe_view(dev, rtvs[i]);
    target.depth = describe_view(dev, dsv);
    return target;
}

void on_bind_render_targets_and_depth_stencil(command_list *cmd_list, std::uint32_t count, const resource_view *rtvs, resource_view dsv)
{
    const slrb::TargetSet target = describe_target(cmd_list, count, rtvs, dsv);
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_core.on_bind_target(target);
}

void on_destroy_resource(device *, resource handle)
{
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_core.on_resource_destroyed(handle.handle);
}

void on_init_swapchain(swapchain *, bool resize)
{
    if (!resize)
        return;
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_core.on_renderer_reset("ReShade swapchain resize");
}

void on_destroy_device(device *)
{
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_core.on_renderer_reset("ReShade device destruction");
}

void on_present(command_queue *, swapchain *, const rect *, const rect *, std::uint32_t, const rect *)
{
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_core.on_present();
}

void on_init_effect_runtime(effect_runtime *runtime)
{
    runtime->create_private_data<RuntimeBindings>();
}

void destroy_runtime_views(effect_runtime *runtime, RuntimeBindings &bindings)
{
    device *const dev = runtime->get_device();
    for (resource_view *view : std::array<resource_view *, 4>{&bindings.albedo, &bindings.material, &bindings.normal_meta, &bindings.depth})
    {
        if (*view != 0)
        {
            dev->destroy_resource_view(*view);
            *view = {0};
        }
    }
}

void on_destroy_effect_runtime(effect_runtime *runtime)
{
    if (RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>())
    {
        destroy_runtime_views(runtime, *bindings);
        runtime->destroy_private_data<RuntimeBindings>();
    }
}

bool create_shader_resource_view(device *dev, const slrb::ResourceRef &ref, resource_view &out)
{
    out = {0};
    if (!ref.valid() || dev->get_api() != device_api::opengl)
        return false;

    const resource res{ref.resource};
    const resource_desc desc = dev->get_resource_desc(res);
    if ((desc.usage & resource_usage::shader_resource) == 0)
        return false;

    // Current official ReShade generic-depth code uses the native depth format as-is on OpenGL.
    const resource_view_desc srv_desc(desc.texture.format);
    return dev->create_resource_view(res, resource_usage::shader_resource, srv_desc, &out);
}

void update_u32_uniform(effect_runtime *runtime, effect_uniform_variable variable, std::uint32_t value)
{
    runtime->set_uniform_value_uint(variable, &value, 1);
}

void update_u64_uniform(effect_runtime *runtime, effect_uniform_variable variable, std::uint64_t value)
{
    const std::uint32_t halves[2] = {
        static_cast<std::uint32_t>(value & 0xffffffffull),
        static_cast<std::uint32_t>(value >> 32),
    };
    runtime->set_uniform_value_uint(variable, halves, 2);
}

void publish_uniform_contract(effect_runtime *runtime, const slrb::BridgeSnapshot &snapshot, bool gbuffer_bindings_valid)
{
    runtime->enumerate_uniform_variables(nullptr, [&](effect_runtime *rt, effect_uniform_variable variable) {
        char name[128] = "";
        rt->get_uniform_variable_name(variable, name);

        if (std::strcmp(name, "SL_RENDER_STAGE") == 0)
            update_u32_uniform(rt, variable, static_cast<std::uint32_t>(snapshot.stage));
        else if (std::strcmp(name, "SL_MAIN_CLASSIFICATION") == 0)
            update_u32_uniform(rt, variable, static_cast<std::uint32_t>(snapshot.classification));
        else if (std::strcmp(name, "SL_MAIN_CONFIDENCE") == 0)
            update_u32_uniform(rt, variable, static_cast<std::uint32_t>(snapshot.confidence));
        else if (std::strcmp(name, "SL_FRAME_ID") == 0)
            update_u64_uniform(rt, variable, snapshot.frame_id);
        else if (std::strcmp(name, "SL_RESOURCE_GENERATION") == 0)
            update_u64_uniform(rt, variable, snapshot.resource_generation);
        else if (std::strcmp(name, "SL_MAIN_GBUFFER_VALID") == 0)
            update_u32_uniform(rt, variable, gbuffer_bindings_valid ? 1u : 0u);
        else if (std::strcmp(name, "SL_MATRIX_VALID") == 0)
            update_u32_uniform(rt, variable, snapshot.matrices.available ? 1u : 0u);
        else if (snapshot.matrices.available && std::strcmp(name, "SL_MAIN_MODELVIEW") == 0)
            rt->set_uniform_value_float(variable, snapshot.matrices.modelview.data(), 16);
        else if (snapshot.matrices.available && std::strcmp(name, "SL_MAIN_PROJECTION") == 0)
            rt->set_uniform_value_float(variable, snapshot.matrices.projection.data(), 16);
        else if (snapshot.matrices.available && std::strcmp(name, "SL_MAIN_INV_MODELVIEW") == 0)
            rt->set_uniform_value_float(variable, snapshot.matrices.inv_modelview.data(), 16);
        else if (snapshot.matrices.available && std::strcmp(name, "SL_MAIN_INV_PROJECTION") == 0)
            rt->set_uniform_value_float(variable, snapshot.matrices.inv_projection.data(), 16);
        else if (snapshot.matrices.available && std::strcmp(name, "SL_MAIN_MODELVIEW_DELTA") == 0)
            rt->set_uniform_value_float(variable, snapshot.matrices.modelview_delta.data(), 16);
        else if (snapshot.matrices.available && std::strcmp(name, "SL_MAIN_INV_MODELVIEW_DELTA") == 0)
            rt->set_uniform_value_float(variable, snapshot.matrices.inv_modelview_delta.data(), 16);
    });
}

void on_reshade_begin_effects(effect_runtime *runtime, command_list *, resource_view, resource_view)
{
    slrb::BridgeSnapshot snapshot;
    {
        const std::lock_guard<std::mutex> lock(g_mutex);
        snapshot = g_core.snapshot();
    }

    RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>();
    if (bindings == nullptr)
        return;

    destroy_runtime_views(runtime, *bindings);

    bool bindings_valid = false;
    if (!snapshot.confirmed_main_gbuffer.empty())
    {
        device *const dev = runtime->get_device();
        const bool a = create_shader_resource_view(dev, snapshot.confirmed_main_gbuffer.colors[0], bindings->albedo);
        const bool m = create_shader_resource_view(dev, snapshot.confirmed_main_gbuffer.colors[1], bindings->material);
        const bool n = create_shader_resource_view(dev, snapshot.confirmed_main_gbuffer.colors[2], bindings->normal_meta);
        const bool d = create_shader_resource_view(dev, snapshot.confirmed_main_gbuffer.depth, bindings->depth);
        bindings_valid = a && m && n && d;
    }

    runtime->update_texture_bindings("SL_MAIN_GBUFFER_ALBEDO", bindings->albedo, bindings->albedo);
    runtime->update_texture_bindings("SL_MAIN_GBUFFER_MATERIAL", bindings->material, bindings->material);
    runtime->update_texture_bindings("SL_MAIN_GBUFFER_NORMAL_META", bindings->normal_meta, bindings->normal_meta);
    runtime->update_texture_bindings("SL_MAIN_GBUFFER_DEPTH", bindings->depth, bindings->depth);
    runtime->update_texture_bindings("SL_MAIN_SCENE_COLOR", {0}, {0});

    publish_uniform_contract(runtime, snapshot, bindings_valid);
}

void on_reshade_finish_effects(effect_runtime *runtime, command_list *, resource_view, resource_view)
{
    RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>();
    if (bindings == nullptr)
        return;

    // Remove references before destroying the transient SRVs. This does not draw or alter Firestorm image resources.
    runtime->update_texture_bindings("SL_MAIN_GBUFFER_ALBEDO", {0}, {0});
    runtime->update_texture_bindings("SL_MAIN_GBUFFER_MATERIAL", {0}, {0});
    runtime->update_texture_bindings("SL_MAIN_GBUFFER_NORMAL_META", {0}, {0});
    runtime->update_texture_bindings("SL_MAIN_GBUFFER_DEPTH", {0}, {0});
    destroy_runtime_views(runtime, *bindings);
}

void draw_resource(const char *label, const slrb::ResourceRef &r)
{
    ImGui::Text("%s: resource=%llu view=%llu %ux%u format=%u", label,
        static_cast<unsigned long long>(r.resource),
        static_cast<unsigned long long>(r.view),
        r.width, r.height, r.format);
}

void draw_overlay(effect_runtime *)
{
    slrb::BridgeSnapshot snapshot;
    {
        const std::lock_guard<std::mutex> lock(g_mutex);
        snapshot = g_core.snapshot();
    }

    ImGui::TextUnformatted("SLRenderBridge 0.1.0 - observation-only Phase 1");
    ImGui::TextUnformatted("Firestorm source pin: 3e20e83b3ea01bb5ae3156d301d0d76ca88dd294");
    ImGui::TextUnformatted("ReShade API: 20 / OpenGL / Windows x64");
    ImGui::Separator();

    ImGui::Text("Classification: %s", slrb::to_string(snapshot.classification));
    ImGui::Text("Confidence: %s", slrb::to_string(snapshot.confidence));
    ImGui::Text("Semantic stage: %s", slrb::to_string(snapshot.stage));
    ImGui::Text("Candidate stage: %s", slrb::to_string(snapshot.candidate_stage));
    ImGui::Text("Native context: %s", slrb::to_string(snapshot.native_context));
    ImGui::Text("Frame ID (ReShade present epoch): %llu", static_cast<unsigned long long>(snapshot.frame_id));
    ImGui::Text("Resource generation: %llu", static_cast<unsigned long long>(snapshot.resource_generation));
    ImGui::Text("Candidate epoch: %llu", static_cast<unsigned long long>(snapshot.candidate_epoch));
    ImGui::Text("Main publications: %llu", static_cast<unsigned long long>(snapshot.main_view_publication_count));
    ImGui::Text("Auxiliary markers: %llu", static_cast<unsigned long long>(snapshot.auxiliary_render_count));
    ImGui::Text("Rejected auxiliary deferred-like binds: %llu", static_cast<unsigned long long>(snapshot.rejected_auxiliary_candidate_count));
    ImGui::Text("Ambiguous candidate transitions: %llu", static_cast<unsigned long long>(snapshot.ambiguous_candidate_count));
    ImGui::Text("Bridge image writes: %llu", static_cast<unsigned long long>(snapshot.image_write_count));

    if (!snapshot.last_invalidation_reason.empty())
        ImGui::TextWrapped("Last invalidation: %s", snapshot.last_invalidation_reason.c_str());

    ImGui::Separator();
    ImGui::TextUnformatted("Current observed target (ReShade views/resources; native FBO ID is not exposed by the supported add-on API):");
    const std::uint32_t current_count = std::min<std::uint32_t>(snapshot.current_target.color_count, static_cast<std::uint32_t>(slrb::kMaxColorAttachments));
    for (std::uint32_t i = 0; i < current_count; ++i)
    {
        char label[32];
        std::snprintf(label, sizeof(label), "Color[%u]", i);
        draw_resource(label, snapshot.current_target.colors[i]);
    }
    draw_resource("Depth", snapshot.current_target.depth);

    ImGui::Separator();
    ImGui::TextUnformatted("Confirmed main G-buffer (empty is a valid safe result):");
    draw_resource("Albedo", snapshot.confirmed_main_gbuffer.colors[0]);
    draw_resource("Material", snapshot.confirmed_main_gbuffer.colors[1]);
    draw_resource("Normal+metadata", snapshot.confirmed_main_gbuffer.colors[2]);
    draw_resource("Depth", snapshot.confirmed_main_gbuffer.depth);

    ImGui::Separator();
    ImGui::TextUnformatted("Recent semantic stage history:");
    for (const auto &entry : snapshot.stage_history)
        ImGui::BulletText("frame %llu: %s - %s", static_cast<unsigned long long>(entry.frame_id), slrb::to_string(entry.stage), entry.reason.c_str());
}
} // namespace

extern "C" __declspec(dllexport) const char *NAME = "SLRenderBridge";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Firestorm-aware semantic renderer bridge foundation (observation-only Phase 1).";

extern "C" __declspec(dllexport) std::uint32_t SLRenderBridge_Notify(const SLRB_NativeEventV1 *event)
{
    if (event == nullptr)
        return 0;
    const std::lock_guard<std::mutex> lock(g_mutex);
    return g_core.on_native_event(*event) ? 1u : 0u;
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    switch (reason)
    {
    case DLL_PROCESS_ATTACH:
        if (!reshade::register_addon(module))
            return FALSE;

        reshade::register_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(on_bind_render_targets_and_depth_stencil);
        reshade::register_event<reshade::addon_event::destroy_resource>(on_destroy_resource);
        reshade::register_event<reshade::addon_event::init_swapchain>(on_init_swapchain);
        reshade::register_event<reshade::addon_event::destroy_device>(on_destroy_device);
        reshade::register_event<reshade::addon_event::present>(on_present);
        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init_effect_runtime);
        reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy_effect_runtime);
        reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_reshade_begin_effects);
        reshade::register_event<reshade::addon_event::reshade_finish_effects>(on_reshade_finish_effects);
        reshade::register_overlay("SLRenderBridge", draw_overlay);
        reshade::log::message(reshade::log::level::info, "SLRenderBridge 0.1.0 loaded (observation-only Phase 1).");
        break;

    case DLL_PROCESS_DETACH:
        reshade::unregister_addon(module);
        break;
    }

    return TRUE;
}
