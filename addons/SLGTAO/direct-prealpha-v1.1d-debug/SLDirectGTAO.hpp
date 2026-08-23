#pragma once

#include <reshade.hpp>
#include <cstdint>

namespace slgtao
{
    namespace api = reshade::api;

    enum class diagnostic_mode : int32_t
    {
        final_opaque_composite = 0,
        raw_ao = 1,
        denoised_ao = 2,
        d0 = 3,
        n0 = 4,
    };

    struct settings
    {
        float radius = 0.50f;
        float strength = 1.00f;
        float falloff_start = 0.35f;
        float max_radius_pixels = 160.0f;

        float surface_bias = 0.005f;
        float silhouette_depth_relative = 0.025f;
        float silhouette_depth_absolute = 0.040f;
        float silhouette_normal_dot = 0.65f;

        float sampling_jitter = 1.00f;
        float silhouette_contact_fraction = 0.35f;
        float silhouette_far_reject = 0.90f;
        float depth_display_range = 64.0f;

        float denoise_depth_sigma = 0.025f;
        float denoise_normal_power = 24.0f;
        float denoise_edge_stop = 1.0f;

        uint32_t slices = 8;
        uint32_t steps_per_side = 8;
        uint32_t denoise_radius = 2;

        diagnostic_mode diagnostic = diagnostic_mode::final_opaque_composite;
    };

    // The matrix is required at the same frame/boundary as the D0/N0 data.
    // Memory is four column vectors, matching the existing SLGIInvProjC0..C3
    // convention and GLSL mat4 column-major std140 layout.
    struct debug_views
    {
        api::resource_view d0 = { 0 };
        api::resource_view n0 = { 0 };
        api::resource_view raw_ao = { 0 };
        api::resource_view denoised_ao = { 0 };
        uint32_t width = 0;
        uint32_t height = 0;
        bool inputs_valid = false;
        bool ao_valid = false;
    };

    struct frame_inputs
    {
        api::resource d0 = { 0 };
        api::resource_desc d0_desc = {};

        api::resource n0 = { 0 };
        api::resource_desc n0_desc = {};

        api::resource scene_color = { 0 };
        api::resource_view scene_color_rtv = { 0 };
        api::resource_desc scene_color_desc = {};

        float inv_projection_columns[16] = {};
        bool projection_valid = false;
    };

    // Direct GTAO changes render targets, viewport/scissor, shader/raster/depth/
    // output-merger pipeline stages and private descriptor slots while executing.
    // The hook supplies this callback to restore the exact application state that
    // existed immediately before GTAO. It is called on every path after GPU state
    // has first been modified.
    using restore_callback =
        void (*)(api::command_list *cmd_list, void *user);

    class direct_gtao
    {
    public:
        bool init(api::device *device);
        void shutdown();

        // Safe-phase preparation only. Call from reshade_begin_effects/present or
        // another point outside application draw/state callbacks. Never allocate or
        // recreate these resources in the qualifying draw callback.
        bool arm(
            const frame_inputs &inputs);

        // Called exactly once at the proven opaque->straight-draw boundary.
        // Returns false without modifying scene color when validation fails.
        bool execute_pre_boundary(
            api::command_list *cmd_list,
            const frame_inputs &inputs,
            const settings &settings,
            restore_callback restore_app_state,
            void *restore_user);

        bool is_ready_for(
            const frame_inputs &inputs) const;

        // Read-only ReShade diagnostic views. These expose the exact resources
        // already owned by the direct pass; they do not execute or copy GPU work.
        bool get_debug_views(debug_views &out) const;

    private:
        struct impl;
        impl *_impl = nullptr;
    };
}
