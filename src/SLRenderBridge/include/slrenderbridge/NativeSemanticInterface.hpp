#pragma once

#include <cstdint>

// Versioned bridge-side ABI for a future minimal Firestorm semantic marker patch.
// Phase 1 implements this receiver but does not patch Firestorm.
#define SLRB_NATIVE_ABI_VERSION 1u

extern "C"
{
enum SLRB_NativeEventKind : std::uint32_t
{
    SLRB_EVENT_MAIN_VIEW_BEGIN = 1,
    SLRB_EVENT_MAIN_GBUFFER_BOUND = 2,
    SLRB_EVENT_MAIN_GBUFFER_COMPLETE = 3,
    SLRB_EVENT_MAIN_DEFERRED_LIGHTING_BEGIN = 4,
    SLRB_EVENT_MAIN_POST_DEFERRED_BEGIN = 5,
    SLRB_EVENT_MAIN_SCENE_COMPLETE = 6,
    SLRB_EVENT_MAIN_POST_PROCESS_BEGIN = 7,
    SLRB_EVENT_MAIN_FRAME_COMPLETE = 8,

    SLRB_EVENT_STANDARD_PROBE_BEGIN = 20,
    SLRB_EVENT_HERO_PROBE_BEGIN = 21,
    SLRB_EVENT_IMPOSTOR_BEGIN = 22,
    SLRB_EVENT_OTHER_AUXILIARY_BEGIN = 23,
    SLRB_EVENT_AUXILIARY_END = 24,

    SLRB_EVENT_MATRICES = 40,
    SLRB_EVENT_RENDERER_RESOURCES_INVALIDATED = 50,
};

enum SLRB_MatrixMask : std::uint32_t
{
    SLRB_MATRIX_MODELVIEW = 1u << 0,
    SLRB_MATRIX_PROJECTION = 1u << 1,
    SLRB_MATRIX_INV_MODELVIEW = 1u << 2,
    SLRB_MATRIX_INV_PROJECTION = 1u << 3,
    SLRB_MATRIX_MODELVIEW_DELTA = 1u << 4,
    SLRB_MATRIX_INV_MODELVIEW_DELTA = 1u << 5,
    SLRB_MATRIX_ALL = (1u << 6) - 1u,
};

struct SLRB_NativeEventV1
{
    std::uint32_t struct_size;
    std::uint32_t abi_version;
    std::uint32_t kind;
    std::uint32_t matrix_mask;
    std::uint64_t native_frame_id;

    float modelview[16];
    float projection[16];
    float inv_modelview[16];
    float inv_projection[16];
    float modelview_delta[16];
    float inv_modelview_delta[16];
};
}
