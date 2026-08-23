#pragma once

#include "MainViewClassifier.hpp"
#include "NativeSemanticInterface.hpp"
#include "ResourceTracker.hpp"
#include "StageTracker.hpp"

namespace slrb
{
class BridgeCore
{
public:
    BridgeCore();

    void on_bind_target(const TargetSet &target);
    void on_resource_destroyed(std::uint64_t resource);
    void on_renderer_reset(const char *reason);
    void on_present();
    bool on_native_event(const SLRB_NativeEventV1 &event);

    BridgeSnapshot snapshot() const;

private:
    void handle_matrices(const SLRB_NativeEventV1 &event);

    MainViewClassifier classifier_;
    ResourceTracker resources_;
    StageTracker stages_;
    MatrixSet matrices_{};

    std::uint64_t frame_id_ = 0;
    std::uint64_t auxiliary_render_count_ = 0;
    std::uint64_t main_view_publication_count_ = 0;
    std::uint64_t rejected_auxiliary_candidate_count_ = 0;
    std::uint64_t ambiguous_candidate_count_ = 0;
    std::uint64_t image_write_count_ = 0; // Intentionally remains zero in observation-only Phase 1.
};
} // namespace slrb
