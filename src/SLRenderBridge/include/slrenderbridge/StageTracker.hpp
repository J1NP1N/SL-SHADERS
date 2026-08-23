#pragma once

#include "Types.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace slrb
{
class StageTracker
{
public:
    void candidate_bound();
    void candidate_unbound();
    void set_semantic(RenderStage stage, std::uint64_t frame_id, const char *reason);
    void clear_semantic(std::uint64_t frame_id, const char *reason);
    void on_present(std::uint64_t frame_id);

    RenderStage stage() const noexcept { return stage_; }
    CandidateStage candidate_stage() const noexcept { return candidate_stage_; }
    const std::vector<StageHistoryEntry> &history() const noexcept { return history_; }

private:
    void push_history(RenderStage stage, std::uint64_t frame_id, const char *reason);

    RenderStage stage_ = RenderStage::Unknown;
    CandidateStage candidate_stage_ = CandidateStage::None;
    std::vector<StageHistoryEntry> history_;
};
} // namespace slrb
