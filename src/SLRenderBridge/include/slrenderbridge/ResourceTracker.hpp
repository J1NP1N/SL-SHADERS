#pragma once

#include "Types.hpp"

#include <string>

namespace slrb
{
class ResourceTracker
{
public:
    void observe_target(const TargetSet &target);
    bool confirm_current_as_main();
    bool invalidate_resource(std::uint64_t resource, const char *reason);
    bool reset(const char *reason);

    const TargetSet &current_target() const noexcept { return current_target_; }
    const TargetSet &candidate_gbuffer() const noexcept { return candidate_gbuffer_; }
    const TargetSet &confirmed_main_gbuffer() const noexcept { return confirmed_main_gbuffer_; }

    std::uint64_t resource_generation() const noexcept { return resource_generation_; }
    std::uint64_t candidate_epoch() const noexcept { return candidate_epoch_; }
    const std::string &last_invalidation_reason() const noexcept { return last_invalidation_reason_; }

private:
    TargetSet current_target_{};
    TargetSet candidate_gbuffer_{};
    TargetSet confirmed_main_gbuffer_{};
    std::uint64_t resource_generation_ = 0;
    std::uint64_t candidate_epoch_ = 0;
    std::string last_invalidation_reason_;
};
} // namespace slrb
