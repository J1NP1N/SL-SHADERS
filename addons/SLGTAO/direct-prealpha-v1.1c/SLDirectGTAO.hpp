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

    using restore_callback =
        void (*)(api::command_list *cmd_list, void *user);

    class direct_gtao
    {
    public:
        bool init(api::device *device);
        void shutdown();

        bool arm(const frame_inputs &inputs);

        bool execute_pre_boundary(
            api::command_list *cmd_list,
            const frame_inputs &inputs,
            const settings &settings,
            restore_callback restore_app_state,
            void *restore_user);

        bool is_ready_for(const frame_inputs &inputs) const;

    private:
        struct impl;
        impl *_impl = nullptr;
    };
}
