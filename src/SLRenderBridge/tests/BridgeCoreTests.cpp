#include "slrenderbridge/BridgeCore.hpp"
#include "slrenderbridge/PublicationPolicy.hpp"

#include <cassert>
#include <cstring>
#include <iostream>

using namespace slrb;

namespace
{
ResourceRef rr(std::uint64_t id, std::uint32_t w = 1920, std::uint32_t h = 1080)
{
    ResourceRef r;
    r.resource = id;
    r.view = id + 1000;
    r.width = w;
    r.height = h;
    r.usage = 0xffffffffu;
    return r;
}

TargetSet deferred(std::uint64_t base, std::uint32_t w = 1920, std::uint32_t h = 1080)
{
    TargetSet t;
    t.color_count = 3;
    t.colors[0] = rr(base + 0, w, h);
    t.colors[1] = rr(base + 1, w, h);
    t.colors[2] = rr(base + 2, w, h);
    t.depth = rr(base + 10, w, h);
    return t;
}

TargetSet scene(std::uint64_t base, std::uint32_t w = 1920, std::uint32_t h = 1080)
{
    TargetSet t;
    t.color_count = 1;
    t.colors[0] = rr(base, w, h);
    t.depth = rr(base + 10, w, h);
    return t;
}

SLRB_NativeEventV1 ev(std::uint32_t kind, std::uint64_t native_frame = 1)
{
    SLRB_NativeEventV1 e{};
    e.struct_size = sizeof(e);
    e.abi_version = SLRB_NATIVE_ABI_VERSION;
    e.kind = kind;
    e.native_frame_id = native_frame;
    return e;
}

void test_external_normal_candidate_is_not_published()
{
    BridgeCore core;
    core.on_bind_target(deferred(100));
    auto s = core.snapshot();
    assert(s.classification == ClassificationState::MainCandidate);
    assert(s.candidate_stage == CandidateStage::DeferredLikeBuilding);
    assert(s.confirmed_main_gbuffer.empty());
    assert(s.main_view_publication_count == 0);

    core.on_bind_target(scene(300));
    s = core.snapshot();
    assert(s.candidate_stage == CandidateStage::DeferredLikeComplete);
    assert(s.stage == RenderStage::Unknown);
    assert(s.confirmed_main_gbuffer.empty());
    assert(s.image_write_count == 0);
}

void test_native_main_sequence_publishes_only_confirmed_set()
{
    BridgeCore core;
    const TargetSet main = deferred(100);
    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 10));
    core.on_bind_target(main);
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 10)));

    auto s = core.snapshot();
    assert(s.classification == ClassificationState::MainConfirmed);
    assert(s.confidence == Confidence::SourceBackedNativeMarker);
    assert(s.stage == RenderStage::MainGBufferBuilding);
    assert(s.confirmed_main_gbuffer.same_resources(main));
    assert(s.resource_generation == 1);
    assert(s.main_view_publication_count == 1);

    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_COMPLETE, 10)));
    assert(core.snapshot().stage == RenderStage::MainGBufferComplete);
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_DEFERRED_LIGHTING_BEGIN, 10)));
    assert(core.snapshot().stage == RenderStage::MainDeferredLighting);
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_POST_DEFERRED_BEGIN, 10)));
    assert(core.snapshot().stage == RenderStage::MainPostDeferred);
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_SCENE_COMPLETE, 10)));
    assert(core.snapshot().stage == RenderStage::MainSceneComplete);
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_POST_PROCESS_BEGIN, 10)));
    assert(core.snapshot().stage == RenderStage::MainPostProcess);
    assert(core.snapshot().image_write_count == 0);
}

void test_standard_probe_cannot_replace_main()
{
    BridgeCore core;
    const TargetSet main = deferred(100);
    const TargetSet probe = deferred(500, 512, 512);

    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 1));
    core.on_bind_target(main);
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 1)));
    const auto generation = core.snapshot().resource_generation;

    core.on_native_event(ev(SLRB_EVENT_STANDARD_PROBE_BEGIN, 1));
    core.on_bind_target(probe);
    auto s = core.snapshot();
    assert(s.classification == ClassificationState::AuxiliaryConfirmed);
    assert(s.stage == RenderStage::AuxiliaryRender);
    assert(s.confirmed_main_gbuffer.same_resources(main));
    assert(s.resource_generation == generation);
    assert(s.rejected_auxiliary_candidate_count == 1);

    core.on_native_event(ev(SLRB_EVENT_AUXILIARY_END, 1));
    assert(core.snapshot().confirmed_main_gbuffer.same_resources(main));
}

void test_hero_probe_repeated_faces_cannot_replace_main()
{
    BridgeCore core;
    const TargetSet main = deferred(100);
    const TargetSet hero = deferred(700, 1024, 1024);
    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 2));
    core.on_bind_target(main);
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 2)));

    for (int face = 0; face < 6; ++face)
    {
        core.on_native_event(ev(SLRB_EVENT_HERO_PROBE_BEGIN, 2));
        core.on_bind_target(hero);
        core.on_native_event(ev(SLRB_EVENT_AUXILIARY_END, 2));
    }

    const auto s = core.snapshot();
    assert(s.confirmed_main_gbuffer.same_resources(main));
    assert(s.auxiliary_render_count == 6);
    assert(s.rejected_auxiliary_candidate_count == 6);
    assert(s.main_view_publication_count == 1);
}

void test_resize_invalidates_and_increments_generation()
{
    BridgeCore core;
    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 3));
    core.on_bind_target(deferred(100));
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 3)));
    assert(core.snapshot().resource_generation == 1);

    core.on_renderer_reset("synthetic resize");
    auto s = core.snapshot();
    assert(s.confirmed_main_gbuffer.empty());
    assert(s.resource_generation == 2);
    assert(s.last_invalidation_reason == "synthetic resize");

    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 4));
    core.on_bind_target(deferred(900, 2560, 1440));
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 4)));
    s = core.snapshot();
    assert(s.resource_generation == 3);
    assert(s.confirmed_main_gbuffer.colors[0].width == 2560);
}

void test_resource_destroy_clears_stale_main_handles()
{
    BridgeCore core;
    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 5));
    core.on_bind_target(deferred(100));
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 5)));
    core.on_resource_destroyed(110);
    const auto s = core.snapshot();
    assert(s.confirmed_main_gbuffer.empty());
    assert(s.resource_generation == 2);
}

void test_ambiguous_external_input_is_not_published()
{
    BridgeCore core;
    core.on_bind_target(deferred(100, 1024, 1024));
    core.on_bind_target(scene(300, 1024, 1024));
    core.on_bind_target(deferred(500, 1024, 1024));
    const auto s = core.snapshot();
    assert(s.classification == ClassificationState::Ambiguous);
    assert(s.confirmed_main_gbuffer.empty());
    assert(s.main_view_publication_count == 0);
    assert(s.ambiguous_candidate_count == 1);
}

void test_passthrough_never_records_image_writes()
{
    BridgeCore core;
    for (int i = 0; i < 4; ++i)
    {
        core.on_bind_target(deferred(100 + i * 100));
        core.on_bind_target(scene(900 + i * 100));
        core.on_present();
    }
    assert(core.snapshot().image_write_count == 0);
}

void test_publication_policy_reuses_same_generation_and_sources()
{
    BridgeCore core;
    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 7));
    core.on_bind_target(deferred(1200));
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 7)));

    const auto snapshot = core.snapshot();
    const PublicationKey key = make_publication_key(snapshot);
    assert(key.valid());
    assert(!publication_requires_rebuild(key, snapshot));
}

void test_publication_policy_rebuilds_on_generation_change()
{
    BridgeCore core;
    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 8));
    core.on_bind_target(deferred(1300));
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 8)));

    const PublicationKey old_key = make_publication_key(core.snapshot());
    core.on_renderer_reset("publication policy synthetic reset");
    assert(publication_requires_rebuild(old_key, core.snapshot()));

    core.on_native_event(ev(SLRB_EVENT_MAIN_VIEW_BEGIN, 9));
    core.on_bind_target(deferred(1400));
    assert(core.on_native_event(ev(SLRB_EVENT_MAIN_GBUFFER_BOUND, 9)));
    assert(publication_requires_rebuild(old_key, core.snapshot()));
}

void test_publication_policy_fails_closed_for_incomplete_set()
{
    BridgeSnapshot snapshot;
    snapshot.resource_generation = 12;
    snapshot.confirmed_main_gbuffer = deferred(1500);
    snapshot.confirmed_main_gbuffer.colors[2] = {};

    const PublicationKey key = make_publication_key(snapshot);
    assert(!key.valid());
    assert(publication_requires_rebuild(PublicationKey{}, snapshot));
}

void test_matrix_marker_requires_complete_matrix_set()
{
    BridgeCore core;
    auto e = ev(SLRB_EVENT_MATRICES, 6);
    e.matrix_mask = SLRB_MATRIX_ALL;
    for (int i = 0; i < 16; ++i)
    {
        e.modelview[i] = static_cast<float>(i);
        e.projection[i] = static_cast<float>(i + 20);
        e.inv_modelview[i] = static_cast<float>(i + 40);
        e.inv_projection[i] = static_cast<float>(i + 60);
        e.modelview_delta[i] = static_cast<float>(i + 80);
        e.inv_modelview_delta[i] = static_cast<float>(i + 100);
    }
    assert(core.on_native_event(e));
    const auto s = core.snapshot();
    assert(s.matrices.available);
    assert(s.matrices.inv_projection[3] == 63.0f);
}
} // namespace

int main()
{
    test_external_normal_candidate_is_not_published();
    test_native_main_sequence_publishes_only_confirmed_set();
    test_standard_probe_cannot_replace_main();
    test_hero_probe_repeated_faces_cannot_replace_main();
    test_resize_invalidates_and_increments_generation();
    test_resource_destroy_clears_stale_main_handles();
    test_ambiguous_external_input_is_not_published();
    test_passthrough_never_records_image_writes();
    test_publication_policy_reuses_same_generation_and_sources();
    test_publication_policy_rebuilds_on_generation_change();
    test_publication_policy_fails_closed_for_incomplete_set();
    test_matrix_marker_requires_complete_matrix_set();
    std::cout << "SLRenderBridge core tests: PASS\n";
    return 0;
}
