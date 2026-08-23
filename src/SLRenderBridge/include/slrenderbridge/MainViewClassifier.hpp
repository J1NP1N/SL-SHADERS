#pragma once

#include "Types.hpp"

#include <cstdint>

namespace slrb
{
class MainViewClassifier
{
public:
    void start_observing();
    void observe_candidate(std::uint64_t target_hash);
    void begin_main(std::uint64_t native_frame_id);
    void confirm_main(std::uint64_t native_frame_id);
    void begin_auxiliary(NativeContext context, std::uint64_t native_frame_id);
    void end_auxiliary();
    void complete_main_frame();
    void on_present();
    void force_ambiguous();

    ClassificationState state() const noexcept { return state_; }
    Confidence confidence() const noexcept { return confidence_; }
    NativeContext native_context() const noexcept { return native_context_; }
    std::uint64_t native_frame_id() const noexcept { return native_frame_id_; }

private:
    ClassificationState state_ = ClassificationState::Uninitialized;
    Confidence confidence_ = Confidence::None;
    NativeContext native_context_ = NativeContext::None;
    std::uint64_t first_candidate_hash_ = 0;
    std::uint64_t native_frame_id_ = 0;
};
} // namespace slrb
