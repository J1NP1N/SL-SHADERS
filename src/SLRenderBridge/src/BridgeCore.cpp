#include "slrenderbridge/BridgeCore.hpp"

#include <algorithm>

namespace slrb
{
BridgeCore::BridgeCore()
{
    classifier_.start_observing();
}

void BridgeCore::on_bind_target(const TargetSet &target)
{
    const TargetSet previous = resources_.current_target();
    const bool previous_candidate = previous.deferred_like_candidate();

    resources_.observe_target(target);

    if (classifier_.state() == ClassificationState::AuxiliaryConfirmed)
    {
        stages_.set_semantic(RenderStage::AuxiliaryRender, frame_id_, "source-backed auxiliary marker active");
        if (target.deferred_like_candidate())
            ++rejected_auxiliary_candidate_count_;
        return;
    }

    if (target.deferred_like_candidate())
    {
        const ClassificationState before = classifier_.state();
        classifier_.observe_candidate(target.identity_hash());
        stages_.candidate_bound();
        if (before != ClassificationState::Ambiguous && classifier_.state() == ClassificationState::Ambiguous)
            ++ambiguous_candidate_count_;
    }
    else if (previous_candidate)
    {
        stages_.candidate_unbound();
    }
}

void BridgeCore::on_resource_destroyed(std::uint64_t resource)
{
    if (resources_.invalidate_resource(resource, "ReShade destroy_resource event"))
        stages_.clear_semantic(frame_id_, "confirmed main resource destroyed");
}

void BridgeCore::on_renderer_reset(const char *reason)
{
    resources_.reset(reason);
    classifier_.start_observing();
    stages_.clear_semantic(frame_id_, reason);
    matrices_ = {};
}

void BridgeCore::on_present()
{
    ++frame_id_;
    classifier_.on_present();
    stages_.on_present(frame_id_);
}

bool BridgeCore::on_native_event(const SLRB_NativeEventV1 &event)
{
    if (event.struct_size < sizeof(SLRB_NativeEventV1) || event.abi_version != SLRB_NATIVE_ABI_VERSION)
        return false;

    switch (static_cast<NativeEventKind>(event.kind))
    {
    case NativeEventKind::MainViewBegin:
        classifier_.begin_main(event.native_frame_id);
        stages_.clear_semantic(frame_id_, "Firestorm main-view begin marker");
        return true;

    case NativeEventKind::MainGBufferBound:
        classifier_.confirm_main(event.native_frame_id);
        resources_.confirm_current_as_main();
        if (resources_.confirmed_main_gbuffer().empty())
        {
            stages_.clear_semantic(frame_id_, "main marker did not coincide with a deferred-like ReShade target");
            return false;
        }
        ++main_view_publication_count_;
        stages_.set_semantic(RenderStage::MainGBufferBuilding, frame_id_, "Firestorm main deferredScreen bound marker");
        return true;

    case NativeEventKind::MainGBufferComplete:
        if (resources_.confirmed_main_gbuffer().empty())
            return false;
        stages_.set_semantic(RenderStage::MainGBufferComplete, frame_id_, "Firestorm main deferredScreen flush marker");
        return true;

    case NativeEventKind::MainDeferredLightingBegin:
        stages_.set_semantic(RenderStage::MainDeferredLighting, frame_id_, "Firestorm deferred-lighting marker");
        return true;

    case NativeEventKind::MainPostDeferredBegin:
        stages_.set_semantic(RenderStage::MainPostDeferred, frame_id_, "Firestorm post-deferred marker");
        return true;

    case NativeEventKind::MainSceneComplete:
        stages_.set_semantic(RenderStage::MainSceneComplete, frame_id_, "Firestorm completed-world-scene marker");
        return true;

    case NativeEventKind::MainPostProcessBegin:
        stages_.set_semantic(RenderStage::MainPostProcess, frame_id_, "Firestorm renderFinalize marker");
        return true;

    case NativeEventKind::MainFrameComplete:
        classifier_.complete_main_frame();
        stages_.clear_semantic(frame_id_, "Firestorm main frame complete marker");
        return true;

    case NativeEventKind::StandardProbeBegin:
        ++auxiliary_render_count_;
        classifier_.begin_auxiliary(NativeContext::StandardProbe, event.native_frame_id);
        stages_.set_semantic(RenderStage::AuxiliaryRender, frame_id_, "Firestorm standard-probe marker");
        return true;

    case NativeEventKind::HeroProbeBegin:
        ++auxiliary_render_count_;
        classifier_.begin_auxiliary(NativeContext::HeroProbe, event.native_frame_id);
        stages_.set_semantic(RenderStage::AuxiliaryRender, frame_id_, "Firestorm hero/mirror-probe marker");
        return true;

    case NativeEventKind::ImpostorBegin:
        ++auxiliary_render_count_;
        classifier_.begin_auxiliary(NativeContext::Impostor, event.native_frame_id);
        stages_.set_semantic(RenderStage::AuxiliaryRender, frame_id_, "Firestorm impostor marker");
        return true;

    case NativeEventKind::OtherAuxiliaryBegin:
        ++auxiliary_render_count_;
        classifier_.begin_auxiliary(NativeContext::OtherAuxiliary, event.native_frame_id);
        stages_.set_semantic(RenderStage::AuxiliaryRender, frame_id_, "Firestorm auxiliary marker");
        return true;

    case NativeEventKind::AuxiliaryEnd:
        classifier_.end_auxiliary();
        stages_.clear_semantic(frame_id_, "Firestorm auxiliary end marker");
        return true;

    case NativeEventKind::Matrices:
        handle_matrices(event);
        return matrices_.available;

    case NativeEventKind::RendererResourcesInvalidated:
        on_renderer_reset("Firestorm renderer-resources-invalidated marker");
        return true;
    }

    return false;
}

void BridgeCore::handle_matrices(const SLRB_NativeEventV1 &event)
{
    const auto copy = [](std::array<float, 16> &dst, const float src[16]) {
        std::copy(src, src + 16, dst.begin());
    };

    if ((event.matrix_mask & SLRB_MATRIX_MODELVIEW) != 0) copy(matrices_.modelview, event.modelview);
    if ((event.matrix_mask & SLRB_MATRIX_PROJECTION) != 0) copy(matrices_.projection, event.projection);
    if ((event.matrix_mask & SLRB_MATRIX_INV_MODELVIEW) != 0) copy(matrices_.inv_modelview, event.inv_modelview);
    if ((event.matrix_mask & SLRB_MATRIX_INV_PROJECTION) != 0) copy(matrices_.inv_projection, event.inv_projection);
    if ((event.matrix_mask & SLRB_MATRIX_MODELVIEW_DELTA) != 0) copy(matrices_.modelview_delta, event.modelview_delta);
    if ((event.matrix_mask & SLRB_MATRIX_INV_MODELVIEW_DELTA) != 0) copy(matrices_.inv_modelview_delta, event.inv_modelview_delta);

    matrices_.available = (event.matrix_mask & SLRB_MATRIX_ALL) == SLRB_MATRIX_ALL;
}

BridgeSnapshot BridgeCore::snapshot() const
{
    BridgeSnapshot result;
    result.classification = classifier_.state();
    result.confidence = classifier_.confidence();
    result.stage = stages_.stage();
    result.candidate_stage = stages_.candidate_stage();
    result.native_context = classifier_.native_context();
    result.frame_id = frame_id_;
    result.resource_generation = resources_.resource_generation();
    result.candidate_epoch = resources_.candidate_epoch();
    result.native_frame_id = classifier_.native_frame_id();
    result.current_target = resources_.current_target();
    result.candidate_gbuffer = resources_.candidate_gbuffer();
    result.confirmed_main_gbuffer = resources_.confirmed_main_gbuffer();
    result.matrices = matrices_;
    result.auxiliary_render_count = auxiliary_render_count_;
    result.main_view_publication_count = main_view_publication_count_;
    result.rejected_auxiliary_candidate_count = rejected_auxiliary_candidate_count_;
    result.ambiguous_candidate_count = ambiguous_candidate_count_;
    result.image_write_count = image_write_count_;
    result.last_invalidation_reason = resources_.last_invalidation_reason();
    result.stage_history = stages_.history();
    return result;
}
} // namespace slrb
