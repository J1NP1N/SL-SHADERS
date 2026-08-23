#include "slrenderbridge/MainViewClassifier.hpp"

namespace slrb
{
void MainViewClassifier::start_observing()
{
    state_ = ClassificationState::Observing;
    confidence_ = Confidence::None;
    native_context_ = NativeContext::None;
    first_candidate_hash_ = 0;
}

void MainViewClassifier::observe_candidate(std::uint64_t target_hash)
{
    if (native_context_ != NativeContext::None)
        return;

    if (state_ == ClassificationState::Uninitialized)
        start_observing();

    if (state_ == ClassificationState::Observing)
    {
        state_ = ClassificationState::MainCandidate;
        confidence_ = Confidence::StructuralCandidate;
        first_candidate_hash_ = target_hash;
        return;
    }

    if (state_ == ClassificationState::MainCandidate && first_candidate_hash_ != 0 && first_candidate_hash_ != target_hash)
    {
        state_ = ClassificationState::Ambiguous;
        confidence_ = Confidence::StructuralCandidate;
    }
}

void MainViewClassifier::begin_main(std::uint64_t native_frame_id)
{
    native_context_ = NativeContext::Main;
    native_frame_id_ = native_frame_id;
    state_ = ClassificationState::MainConfirmed;
    confidence_ = Confidence::SourceBackedNativeMarker;
}

void MainViewClassifier::confirm_main(std::uint64_t native_frame_id)
{
    begin_main(native_frame_id);
}

void MainViewClassifier::begin_auxiliary(NativeContext context, std::uint64_t native_frame_id)
{
    native_context_ = context;
    native_frame_id_ = native_frame_id;
    state_ = ClassificationState::AuxiliaryConfirmed;
    confidence_ = Confidence::SourceBackedNativeMarker;
}

void MainViewClassifier::end_auxiliary()
{
    native_context_ = NativeContext::None;
    state_ = ClassificationState::Observing;
    confidence_ = Confidence::None;
    first_candidate_hash_ = 0;
}

void MainViewClassifier::complete_main_frame()
{
    native_context_ = NativeContext::None;
    state_ = ClassificationState::Observing;
    confidence_ = Confidence::None;
    first_candidate_hash_ = 0;
}

void MainViewClassifier::on_present()
{
    if (native_context_ == NativeContext::None)
    {
        state_ = ClassificationState::Observing;
        confidence_ = Confidence::None;
        first_candidate_hash_ = 0;
    }
}

void MainViewClassifier::force_ambiguous()
{
    if (native_context_ == NativeContext::None)
    {
        state_ = ClassificationState::Ambiguous;
        confidence_ = Confidence::None;
    }
}
} // namespace slrb
