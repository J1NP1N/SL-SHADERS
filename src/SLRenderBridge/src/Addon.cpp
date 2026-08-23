#include <imgui.h>
#include <reshade.hpp>
#include <Windows.h>

#include "slrenderbridge/BridgeCore.hpp"
#include "slrenderbridge/PublicationPolicy.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

static_assert(RESHADE_API_VERSION == 20, "SLRenderBridge Phase 1.1 was reviewed against ReShade add-on API 20");

namespace
{
using namespace reshade::api;

std::mutex g_mutex;
slrb::BridgeCore g_core;

std::mutex g_runtime_mutex;
std::vector<effect_runtime *> g_runtimes;

enum class SemanticSlot : std::size_t
{
    Albedo = 0,
    Material,
    NormalMeta,
    Depth,
    Count,
};

constexpr std::size_t kSemanticCount = static_cast<std::size_t>(SemanticSlot::Count);
constexpr std::array<const char *, kSemanticCount> kSemanticNames = {
    "SL_MAIN_GBUFFER_ALBEDO",
    "SL_MAIN_GBUFFER_MATERIAL",
    "SL_MAIN_GBUFFER_NORMAL_META",
    "SL_MAIN_GBUFFER_DEPTH",
};
constexpr std::array<const char *, kSemanticCount> kSemanticLabels = {
    "ALBEDO",
    "MATERIAL",
    "NORMAL_META",
    "DEPTH",
};

enum class PublicationPath : std::uint32_t
{
    NullView = 0,
    PrivateSingleMipCopySrv,
    CreateFailed,
    StaleReleased,
};

const char *to_string(PublicationPath path) noexcept
{
    switch (path)
    {
    case PublicationPath::NullView: return "null view";
    case PublicationPath::PrivateSingleMipCopySrv: return "persistent private one-mip SRV";
    case PublicationPath::CreateFailed: return "create failed / null";
    case PublicationPath::StaleReleased: return "stale view released / null";
    default: return "unknown";
    }
}

struct PublicationSlotState
{
    slrb::ResourceRef confirmed{};
    resource publication_resource{};
    resource_view srv{};
    format srv_format = format::unknown;

    bool source_has_shader_resource = false;
    bool source_has_copy_source = false;
    bool create_resource_attempted = false;
    bool create_resource_succeeded = false;
    bool create_view_attempted = false;
    bool create_view_succeeded = false;
    bool copy_issued = false;
    bool semantic_update_issued = false;
    std::uint32_t descriptor_matches = 0;

    std::uint64_t last_copy_frame = 0;
    std::uint64_t last_bind_frame = 0;
    slrb::RenderStage last_bind_stage = slrb::RenderStage::Unknown;
    PublicationPath path = PublicationPath::NullView;
    std::string last_status;
};

struct RuntimeBindings
{
    slrb::PublicationKey key{};
    std::array<PublicationSlotState, kSemanticCount> slots{};
    bool semantics_bound = false;
    bool needs_rebind = true;
    std::uint64_t private_copy_count = 0;
    std::string last_invalidation_reason;
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

const slrb::ResourceRef &confirmed_ref(const slrb::BridgeSnapshot &snapshot, std::size_t index)
{
    switch (static_cast<SemanticSlot>(index))
    {
    case SemanticSlot::Albedo: return snapshot.confirmed_main_gbuffer.colors[0];
    case SemanticSlot::Material: return snapshot.confirmed_main_gbuffer.colors[1];
    case SemanticSlot::NormalMeta: return snapshot.confirmed_main_gbuffer.colors[2];
    case SemanticSlot::Depth: return snapshot.confirmed_main_gbuffer.depth;
    default: return snapshot.confirmed_main_gbuffer.depth;
    }
}

void log_slot_message(reshade::log::level level, std::size_t index, const char *message)
{
    char buffer[512];
    std::snprintf(buffer, sizeof(buffer), "SLRenderBridge Phase 1.1 %s: %s", kSemanticLabels[index], message);
    reshade::log::message(level, buffer);
}

void on_bind_render_targets_and_depth_stencil(command_list *cmd_list, std::uint32_t count, const resource_view *rtvs, resource_view dsv)
{
    const slrb::TargetSet target = describe_target(cmd_list, count, rtvs, dsv);
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_core.on_bind_target(target);
}

void clear_semantic_bindings(effect_runtime *runtime, RuntimeBindings &bindings)
{
    if (!bindings.semantics_bound)
        return;

    for (const char *semantic : kSemanticNames)
        runtime->update_texture_bindings(semantic, {0}, {0});

    bindings.semantics_bound = false;
}

void destroy_publication_slot(device *dev, PublicationSlotState &slot, const char *reason)
{
    const resource_view old_view = slot.srv;
    const resource old_resource = slot.publication_resource;

    slot.srv = {0};
    slot.publication_resource = {0};
    if (old_view != 0 || old_resource != 0)
    {
        slot.path = PublicationPath::StaleReleased;
        slot.last_status = reason != nullptr ? reason : "released";
    }
    else if (slot.path != PublicationPath::CreateFailed)
    {
        slot.path = PublicationPath::NullView;
        slot.last_status = reason != nullptr ? reason : "released";
    }
    slot.descriptor_matches = 0;
    slot.semantic_update_issued = false;
    slot.copy_issued = false;

    if (old_view != 0)
        dev->destroy_resource_view(old_view);
    if (old_resource != 0)
        dev->destroy_resource(old_resource);
}

void release_runtime_publication(effect_runtime *runtime, RuntimeBindings &bindings, const char *reason)
{
    clear_semantic_bindings(runtime, bindings);

    device *const dev = runtime->get_device();
    for (PublicationSlotState &slot : bindings.slots)
        destroy_publication_slot(dev, slot, reason);

    bindings.key = {};
    bindings.needs_rebind = true;
    bindings.last_invalidation_reason = reason != nullptr ? reason : "publication released";
}

std::vector<effect_runtime *> runtimes_snapshot()
{
    const std::lock_guard<std::mutex> lock(g_runtime_mutex);
    return g_runtimes;
}

void invalidate_all_runtime_publications(const char *reason)
{
    for (effect_runtime *runtime : runtimes_snapshot())
    {
        if (runtime == nullptr)
            continue;
        if (RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>())
            release_runtime_publication(runtime, *bindings, reason);
    }
}

void invalidate_device_publications(device *dev, const char *reason)
{
    for (effect_runtime *runtime : runtimes_snapshot())
    {
        if (runtime == nullptr || runtime->get_device() != dev)
            continue;
        if (RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>())
            release_runtime_publication(runtime, *bindings, reason);
    }
}

void invalidate_source_resource_publications(device *dev, std::uint64_t source_resource)
{
    for (effect_runtime *runtime : runtimes_snapshot())
    {
        if (runtime == nullptr || runtime->get_device() != dev)
            continue;

        RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>();
        if (bindings == nullptr)
            continue;

        bool references_source = false;
        for (const PublicationSlotState &slot : bindings->slots)
            references_source = references_source || slot.confirmed.resource == source_resource;

        if (references_source)
            release_runtime_publication(runtime, *bindings, "confirmed source resource destroyed");
    }
}

void on_destroy_resource(device *dev, resource handle)
{
    invalidate_source_resource_publications(dev, handle.handle);

    const std::lock_guard<std::mutex> lock(g_mutex);
    g_core.on_resource_destroyed(handle.handle);
}

void on_init_swapchain(swapchain *chain, bool resize)
{
    if (!resize)
        return;

    invalidate_device_publications(chain->get_device(), "ReShade swapchain resize");
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_core.on_renderer_reset("ReShade swapchain resize");
}

void on_destroy_device(device *dev)
{
    invalidate_device_publications(dev, "ReShade device destruction");
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
    const std::lock_guard<std::mutex> lock(g_runtime_mutex);
    g_runtimes.push_back(runtime);
}

void on_destroy_effect_runtime(effect_runtime *runtime)
{
    {
        const std::lock_guard<std::mutex> lock(g_runtime_mutex);
        g_runtimes.erase(std::remove(g_runtimes.begin(), g_runtimes.end(), runtime), g_runtimes.end());
    }

    if (RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>())
    {
        release_runtime_publication(runtime, *bindings, "effect runtime destruction");
        runtime->destroy_private_data<RuntimeBindings>();
    }
}

bool create_publication_slot(device *dev, const slrb::ResourceRef &ref, PublicationSlotState &slot, std::size_t index)
{
    slot = {};
    slot.confirmed = ref;

    if (!ref.valid() || dev->get_api() != device_api::opengl)
    {
        slot.path = PublicationPath::CreateFailed;
        slot.last_status = "invalid source or non-OpenGL device";
        return false;
    }

    const resource source{ref.resource};
    const resource_desc source_desc = dev->get_resource_desc(source);
    slot.confirmed.width = source_desc.texture.width;
    slot.confirmed.height = source_desc.texture.height;
    slot.confirmed.format = static_cast<std::uint32_t>(source_desc.texture.format);
    slot.confirmed.usage = static_cast<std::uint32_t>(source_desc.usage);
    slot.source_has_shader_resource = (source_desc.usage & resource_usage::shader_resource) != 0;
    slot.source_has_copy_source = (source_desc.usage & resource_usage::copy_source) != 0;

    if (source_desc.type != resource_type::texture_2d || source_desc.texture.samples != 1 ||
        !slot.source_has_shader_resource || !slot.source_has_copy_source)
    {
        slot.path = PublicationPath::CreateFailed;
        slot.last_status = "source is not a sampleable single-sample 2D copy source";
        log_slot_message(reshade::log::level::warning, index, slot.last_status.c_str());
        return false;
    }

    // ReShade/OpenGL returns the application texture itself for a same-format, level-0 view.
    // Firestorm render targets are level-0 non-mip targets, while ReShade effect sampler objects
    // may request mipmapped minification. Use a bridge-owned immutable one-level texture so the
    // semantic is sampler-complete without changing Firestorm's texture parameters.
    resource_desc publication_desc{};
    publication_desc.type = resource_type::texture_2d;
    publication_desc.texture.width = source_desc.texture.width;
    publication_desc.texture.height = source_desc.texture.height;
    publication_desc.texture.depth_or_layers = 1;
    publication_desc.texture.levels = 1;
    publication_desc.texture.format = source_desc.texture.format;
    publication_desc.texture.samples = 1;
    publication_desc.heap = memory_heap::default_;
    publication_desc.usage = resource_usage::shader_resource | resource_usage::copy_dest;

    slot.create_resource_attempted = true;
    if (!dev->create_resource(publication_desc, nullptr, resource_usage::shader_resource, &slot.publication_resource))
    {
        slot.path = PublicationPath::CreateFailed;
        slot.last_status = "create_resource failed for private one-mip publication texture";
        log_slot_message(reshade::log::level::error, index, slot.last_status.c_str());
        return false;
    }
    slot.create_resource_succeeded = true;

    const resource_view_desc srv_desc(resource_view_type::texture_2d, publication_desc.texture.format, 0, 1, 0, 1);
    slot.create_view_attempted = true;
    if (!dev->create_resource_view(slot.publication_resource, resource_usage::shader_resource, srv_desc, &slot.srv))
    {
        const resource old_resource = slot.publication_resource;
        slot.publication_resource = {0};
        dev->destroy_resource(old_resource);
        slot.path = PublicationPath::CreateFailed;
        slot.last_status = "create_resource_view failed for private publication texture";
        log_slot_message(reshade::log::level::error, index, slot.last_status.c_str());
        return false;
    }

    slot.create_view_succeeded = true;
    slot.srv_format = dev->get_resource_view_desc(slot.srv).format;
    slot.path = PublicationPath::PrivateSingleMipCopySrv;
    slot.last_status = "persistent private publication resource/SRV ready";
    return true;
}

resource_usage source_effect_usage(const resource_desc &desc)
{
    resource_usage usage = desc.usage & (resource_usage::shader_resource | resource_usage::render_target | resource_usage::depth_stencil);
    if (usage == resource_usage::undefined)
        usage = resource_usage::shader_resource;
    return usage;
}

bool refresh_publication_slot(command_list *cmd_list, PublicationSlotState &slot, std::uint64_t frame_id, std::size_t index)
{
    if (slot.confirmed.resource == 0 || slot.publication_resource == 0 || slot.srv == 0)
        return false;

    device *const dev = cmd_list->get_device();
    const resource source{slot.confirmed.resource};
    const resource_desc source_desc = dev->get_resource_desc(source);
    const resource_desc dest_desc = dev->get_resource_desc(slot.publication_resource);

    if (source_desc.type != resource_type::texture_2d || source_desc.texture.samples != 1 ||
        source_desc.texture.width != dest_desc.texture.width || source_desc.texture.height != dest_desc.texture.height ||
        source_desc.texture.format != dest_desc.texture.format ||
        (source_desc.usage & resource_usage::copy_source) == 0 ||
        (dest_desc.usage & resource_usage::copy_dest) == 0)
    {
        slot.last_status = "copy preconditions failed; semantic left fail-closed";
        log_slot_message(reshade::log::level::error, index, slot.last_status.c_str());
        return false;
    }

    const resource resources[2] = {source, slot.publication_resource};
    const resource_usage old_states[2] = {source_effect_usage(source_desc), resource_usage::shader_resource};
    const resource_usage copy_states[2] = {resource_usage::copy_source, resource_usage::copy_dest};

    // These transitions express the supported ReShade API contract. In the OpenGL backend they
    // do not emit a memory barrier for ordinary RT/depth -> copy/sample usage; command ordering is
    // already sufficient. They do not modify Firestorm texture contents or persistent GL state.
    cmd_list->barrier(2, resources, old_states, copy_states);
    cmd_list->copy_texture_region(source, 0, nullptr, slot.publication_resource, 0, nullptr);
    cmd_list->barrier(2, resources, copy_states, old_states);

    slot.copy_issued = true;
    slot.last_copy_frame = frame_id;
    slot.last_status = "private one-mip copy refreshed before effect execution";
    return true;
}

std::uint32_t count_descriptor_matches(effect_runtime *runtime, resource_view expected)
{
    if (expected == 0)
        return 0;

    std::uint32_t matches = 0;
    runtime->enumerate_texture_variables(nullptr, [&](effect_runtime *rt, effect_texture_variable variable) {
        resource_view srv{};
        resource_view srv_srgb{};
        rt->get_texture_binding(variable, &srv, &srv_srgb);
        if (srv == expected || srv_srgb == expected)
            ++matches;
    });
    return matches;
}

void bind_semantics(effect_runtime *runtime, RuntimeBindings &bindings, const slrb::BridgeSnapshot &snapshot)
{
    for (std::size_t i = 0; i < kSemanticCount; ++i)
    {
        PublicationSlotState &slot = bindings.slots[i];
        runtime->update_texture_bindings(kSemanticNames[i], slot.srv, slot.srv);
        slot.semantic_update_issued = true;
        slot.last_bind_frame = snapshot.frame_id;
        slot.last_bind_stage = snapshot.stage;
        slot.descriptor_matches = count_descriptor_matches(runtime, slot.srv);

        if (slot.descriptor_matches == 0)
            log_slot_message(reshade::log::level::warning, i, "semantic update issued but no loaded effect texture currently resolves to this SRV");
    }

    runtime->update_texture_bindings("SL_MAIN_SCENE_COLOR", {0}, {0});
    bindings.semantics_bound = true;
    bindings.needs_rebind = false;
}

bool all_publication_slots_ready(const RuntimeBindings &bindings)
{
    for (const PublicationSlotState &slot : bindings.slots)
        if (slot.publication_resource == 0 || slot.srv == 0 || !slot.create_view_succeeded)
            return false;
    return true;
}

bool ensure_publication(effect_runtime *runtime, command_list *cmd_list, RuntimeBindings &bindings, const slrb::BridgeSnapshot &snapshot)
{
    const slrb::PublicationKey wanted = slrb::make_publication_key(snapshot);
    if (!wanted.valid())
    {
        if (bindings.key.valid() || bindings.semantics_bound)
            release_runtime_publication(runtime, bindings, "confirmed main G-buffer unavailable");
        return false;
    }

    if (bindings.key != wanted || !all_publication_slots_ready(bindings))
    {
        if (bindings.key.valid() || bindings.semantics_bound)
            release_runtime_publication(runtime, bindings, "confirmed resource generation/source set changed");

        bindings.key = wanted;
        bool created_all = true;
        for (std::size_t i = 0; i < kSemanticCount; ++i)
            created_all = create_publication_slot(runtime->get_device(), confirmed_ref(snapshot, i), bindings.slots[i], i) && created_all;

        if (!created_all)
        {
            release_runtime_publication(runtime, bindings, "publication resource/SRV creation failed");
            return false;
        }
        bindings.needs_rebind = true;
    }

    bool copied_all = true;
    for (std::size_t i = 0; i < kSemanticCount; ++i)
    {
        bindings.slots[i].copy_issued = false;
        copied_all = refresh_publication_slot(cmd_list, bindings.slots[i], snapshot.frame_id, i) && copied_all;
        if (bindings.slots[i].copy_issued)
            ++bindings.private_copy_count;
    }

    if (!copied_all)
    {
        clear_semantic_bindings(runtime, bindings);
        bindings.needs_rebind = true;
        return false;
    }

    if (bindings.needs_rebind || !bindings.semantics_bound)
        bind_semantics(runtime, bindings, snapshot);

    return all_publication_slots_ready(bindings) && bindings.semantics_bound;
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

void on_reshade_begin_effects(effect_runtime *runtime, command_list *cmd_list, resource_view, resource_view)
{
    slrb::BridgeSnapshot snapshot;
    {
        const std::lock_guard<std::mutex> lock(g_mutex);
        snapshot = g_core.snapshot();
    }

    RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>();
    if (bindings == nullptr || cmd_list == nullptr)
        return;

    const bool bindings_valid = ensure_publication(runtime, cmd_list, *bindings, snapshot);
    publish_uniform_contract(runtime, snapshot, bindings_valid);
}

void on_reshade_finish_effects(effect_runtime *, command_list *, resource_view, resource_view)
{
    // Persistent publication SRVs/resources intentionally survive the effect interval.
    // Copy transitions are restored in 'on_reshade_begin_effects'; there is no per-frame view churn.
}

void on_reshade_reloaded_effects(effect_runtime *runtime)
{
    if (RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>())
        bindings->needs_rebind = true;
}

void draw_resource(const char *label, const slrb::ResourceRef &r)
{
    ImGui::Text("%s: resource=%llu observed_view=%llu %ux%u format=%u usage=0x%08X", label,
        static_cast<unsigned long long>(r.resource),
        static_cast<unsigned long long>(r.view),
        r.width, r.height, r.format, r.usage);
}

void draw_publication_slot(const char *label, const PublicationSlotState &slot)
{
    ImGui::TextUnformatted(label);
    ImGui::Indent();
    ImGui::Text("confirmed resource: %llu", static_cast<unsigned long long>(slot.confirmed.resource));
    ImGui::Text("confirmed observed view: %llu (event-only; not reused)", static_cast<unsigned long long>(slot.confirmed.view));
    ImGui::Text("source: %ux%u format=%u usage=0x%08X", slot.confirmed.width, slot.confirmed.height, slot.confirmed.format, slot.confirmed.usage);
    ImGui::Text("source shader_resource=%s copy_source=%s", slot.source_has_shader_resource ? "yes" : "no", slot.source_has_copy_source ? "yes" : "no");
    ImGui::Text("publication resource: %llu", static_cast<unsigned long long>(slot.publication_resource.handle));
    ImGui::Text("created SRV: %llu format=%u", static_cast<unsigned long long>(slot.srv.handle), static_cast<unsigned int>(slot.srv_format));
    ImGui::Text("create_resource: attempted=%s success=%s", slot.create_resource_attempted ? "yes" : "no", slot.create_resource_succeeded ? "yes" : "no");
    ImGui::Text("create_resource_view: attempted=%s success=%s", slot.create_view_attempted ? "yes" : "no", slot.create_view_succeeded ? "yes" : "no");
    ImGui::Text("publication path: %s", to_string(slot.path));
    ImGui::Text("semantic update issued=%s descriptor matches=%u", slot.semantic_update_issued ? "yes" : "no", slot.descriptor_matches);
    ImGui::Text("last bind: frame=%llu stage=%s", static_cast<unsigned long long>(slot.last_bind_frame), slrb::to_string(slot.last_bind_stage));
    ImGui::Text("last private copy: frame=%llu issued=%s", static_cast<unsigned long long>(slot.last_copy_frame), slot.copy_issued ? "yes" : "no");
    ImGui::TextWrapped("status: %s", slot.last_status.empty() ? "not initialized" : slot.last_status.c_str());
    ImGui::Unindent();
}

void draw_overlay(effect_runtime *runtime)
{
    slrb::BridgeSnapshot snapshot;
    {
        const std::lock_guard<std::mutex> lock(g_mutex);
        snapshot = g_core.snapshot();
    }

    ImGui::TextUnformatted("SLRenderBridge 0.1.1 - Phase 1.1 resource publication");
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
    ImGui::Text("Bridge Firestorm image writes: %llu", static_cast<unsigned long long>(snapshot.image_write_count));

    if (!snapshot.last_invalidation_reason.empty())
        ImGui::TextWrapped("Last core invalidation: %s", snapshot.last_invalidation_reason.c_str());

    ImGui::Separator();
    ImGui::TextUnformatted("Current observed target (application views are event-callback lifetime only):");
    const std::uint32_t current_count = std::min<std::uint32_t>(snapshot.current_target.color_count, static_cast<std::uint32_t>(slrb::kMaxColorAttachments));
    for (std::uint32_t i = 0; i < current_count; ++i)
    {
        char label[32];
        std::snprintf(label, sizeof(label), "Color[%u]", i);
        draw_resource(label, snapshot.current_target.colors[i]);
    }
    draw_resource("Depth", snapshot.current_target.depth);

    ImGui::Separator();
    ImGui::TextUnformatted("Confirmed main G-buffer:");
    draw_resource("Albedo", snapshot.confirmed_main_gbuffer.colors[0]);
    draw_resource("Material", snapshot.confirmed_main_gbuffer.colors[1]);
    draw_resource("Normal+metadata", snapshot.confirmed_main_gbuffer.colors[2]);
    draw_resource("Depth", snapshot.confirmed_main_gbuffer.depth);

    ImGui::Separator();
    ImGui::TextUnformatted("Phase 1.1 ReShade semantic publication:");
    if (RuntimeBindings *const bindings = runtime->get_private_data<RuntimeBindings>())
    {
        ImGui::Text("publication generation: %llu", static_cast<unsigned long long>(bindings->key.generation));
        ImGui::Text("semantic bindings active: %s", bindings->semantics_bound ? "yes" : "no");
        ImGui::Text("private publication copies issued: %llu", static_cast<unsigned long long>(bindings->private_copy_count));
        if (!bindings->last_invalidation_reason.empty())
            ImGui::TextWrapped("last publication invalidation: %s", bindings->last_invalidation_reason.c_str());
        for (std::size_t i = 0; i < kSemanticCount; ++i)
        {
            ImGui::Separator();
            draw_publication_slot(kSemanticLabels[i], bindings->slots[i]);
        }
    }
    else
    {
        ImGui::TextUnformatted("No effect-runtime publication state.");
    }

    ImGui::Separator();
    ImGui::TextUnformatted("Recent semantic stage history:");
    for (const auto &entry : snapshot.stage_history)
        ImGui::BulletText("frame %llu: %s - %s", static_cast<unsigned long long>(entry.frame_id), slrb::to_string(entry.stage), entry.reason.c_str());
}
} // namespace

extern "C" __declspec(dllexport) const char *NAME = "SLRenderBridge";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Firestorm-aware semantic renderer bridge (Phase 1.1 resource publication fix).";

extern "C" __declspec(dllexport) std::uint32_t SLRenderBridge_Notify(const SLRB_NativeEventV1 *event)
{
    if (event == nullptr)
        return 0;

    bool handled = false;
    {
        const std::lock_guard<std::mutex> lock(g_mutex);
        handled = g_core.on_native_event(*event);
    }

    if (handled && event->kind == SLRB_EVENT_RENDERER_RESOURCES_INVALIDATED)
        invalidate_all_runtime_publications("Firestorm renderer resources invalidated");

    return handled ? 1u : 0u;
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
        reshade::register_event<reshade::addon_event::reshade_reloaded_effects>(on_reshade_reloaded_effects);
        reshade::register_overlay("SLRenderBridge", draw_overlay);
        reshade::log::message(reshade::log::level::info, "SLRenderBridge 0.1.1 loaded (Phase 1.1 resource publication fix).");
        break;

    case DLL_PROCESS_DETACH:
        // ReShade destroys effect runtimes/device objects before unregistering the add-on in normal teardown.
        // Do not call graphics APIs from DllMain; remaining runtime private data is released by callbacks above.
        reshade::unregister_addon(module);
        break;
    }

    return TRUE;
}
