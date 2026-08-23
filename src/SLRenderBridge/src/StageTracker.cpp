#include "slrenderbridge/StageTracker.hpp"

namespace slrb
{
void StageTracker::candidate_bound()
{
    candidate_stage_ = CandidateStage::DeferredLikeBuilding;
}

void StageTracker::candidate_unbound()
{
    if (candidate_stage_ == CandidateStage::DeferredLikeBuilding)
        candidate_stage_ = CandidateStage::DeferredLikeComplete;
}

void StageTracker::set_semantic(RenderStage new_stage, std::uint64_t frame_id, const char *reason)
{
    if (stage_ == new_stage)
        return;
    stage_ = new_stage;
    push_history(new_stage, frame_id, reason);
}

void StageTracker::clear_semantic(std::uint64_t frame_id, const char *reason)
{
    set_semantic(RenderStage::Unknown, frame_id, reason);
}

void StageTracker::on_present(std::uint64_t frame_id)
{
    candidate_stage_ = CandidateStage::None;
    clear_semantic(frame_id, "present boundary");
}

void StageTracker::push_history(RenderStage stage, std::uint64_t frame_id, const char *reason)
{
    if (history_.size() == kStageHistoryCapacity)
        history_.erase(history_.begin());
    history_.push_back({stage, frame_id, reason != nullptr ? reason : ""});
}
} // namespace slrb
