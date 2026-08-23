#include "slrenderbridge/ResourceTracker.hpp"

#include <algorithm>

namespace slrb
{
namespace
{
constexpr std::uint64_t kFnvOffset = 1469598103934665603ull;
constexpr std::uint64_t kFnvPrime = 1099511628211ull;

void hash_value(std::uint64_t &hash, std::uint64_t value) noexcept
{
    for (unsigned int i = 0; i < 8; ++i)
    {
        hash ^= (value >> (i * 8)) & 0xffu;
        hash *= kFnvPrime;
    }
}
} // namespace

bool TargetSet::empty() const noexcept
{
    return color_count == 0 && !depth.valid();
}

bool TargetSet::deferred_like_candidate() const noexcept
{
    if (color_count_overflow || color_count < 3 || !depth.valid())
        return false;

    const std::uint32_t width = colors[0].width;
    const std::uint32_t height = colors[0].height;
    if (width == 0 || height == 0)
        return false;

    for (std::uint32_t i = 0; i < 3; ++i)
    {
        if (!colors[i].valid() || colors[i].width != width || colors[i].height != height)
            return false;
    }

    return depth.width == width && depth.height == height;
}

bool TargetSet::contains_resource(std::uint64_t resource_id) const noexcept
{
    if (resource_id == 0)
        return false;
    if (depth.resource == resource_id)
        return true;

    const std::size_t count = std::min<std::size_t>(color_count, colors.size());
    for (std::size_t i = 0; i < count; ++i)
        if (colors[i].resource == resource_id)
            return true;
    return false;
}

std::uint64_t TargetSet::identity_hash() const noexcept
{
    std::uint64_t hash = kFnvOffset;
    hash_value(hash, color_count);
    hash_value(hash, color_count_overflow ? 1u : 0u);
    const std::size_t count = std::min<std::size_t>(color_count, colors.size());
    for (std::size_t i = 0; i < count; ++i)
        hash_value(hash, colors[i].resource);
    hash_value(hash, depth.resource);
    return hash;
}

bool TargetSet::same_resources(const TargetSet &other) const noexcept
{
    if (color_count != other.color_count || color_count_overflow != other.color_count_overflow || depth.resource != other.depth.resource)
        return false;
    const std::size_t count = std::min<std::size_t>(color_count, colors.size());
    for (std::size_t i = 0; i < count; ++i)
        if (colors[i].resource != other.colors[i].resource)
            return false;
    return true;
}

void ResourceTracker::observe_target(const TargetSet &target)
{
    current_target_ = target;
    if (!target.deferred_like_candidate())
        return;

    if (!candidate_gbuffer_.same_resources(target))
    {
        candidate_gbuffer_ = target;
        ++candidate_epoch_;
    }
}

bool ResourceTracker::confirm_current_as_main()
{
    if (!current_target_.deferred_like_candidate())
        return false;

    if (!confirmed_main_gbuffer_.same_resources(current_target_))
    {
        confirmed_main_gbuffer_ = current_target_;
        ++resource_generation_;
        return true;
    }
    return false;
}

bool ResourceTracker::invalidate_resource(std::uint64_t resource_id, const char *reason)
{
    bool changed = false;
    if (candidate_gbuffer_.contains_resource(resource_id))
    {
        candidate_gbuffer_ = {};
        ++candidate_epoch_;
    }
    if (current_target_.contains_resource(resource_id))
        current_target_ = {};
    if (confirmed_main_gbuffer_.contains_resource(resource_id))
    {
        confirmed_main_gbuffer_ = {};
        ++resource_generation_;
        changed = true;
    }
    if (changed)
        last_invalidation_reason_ = reason != nullptr ? reason : "resource destroyed";
    return changed;
}

bool ResourceTracker::reset(const char *reason)
{
    const bool had_confirmed = !confirmed_main_gbuffer_.empty();
    current_target_ = {};
    candidate_gbuffer_ = {};
    confirmed_main_gbuffer_ = {};
    ++candidate_epoch_;
    ++resource_generation_;
    last_invalidation_reason_ = reason != nullptr ? reason : "renderer reset";
    return had_confirmed;
}

const char *to_string(ClassificationState value) noexcept
{
    switch (value)
    {
    case ClassificationState::Uninitialized: return "UNINITIALIZED";
    case ClassificationState::Observing: return "OBSERVING";
    case ClassificationState::MainCandidate: return "MAIN_CANDIDATE";
    case ClassificationState::MainConfirmed: return "MAIN_CONFIRMED";
    case ClassificationState::AuxiliaryConfirmed: return "AUXILIARY_CONFIRMED";
    case ClassificationState::Ambiguous: return "AMBIGUOUS";
    }
    return "UNKNOWN";
}

const char *to_string(Confidence value) noexcept
{
    switch (value)
    {
    case Confidence::None: return "NONE";
    case Confidence::StructuralCandidate: return "STRUCTURAL_CANDIDATE";
    case Confidence::SourceBackedNativeMarker: return "SOURCE_BACKED_NATIVE_MARKER";
    }
    return "UNKNOWN";
}

const char *to_string(RenderStage value) noexcept
{
    switch (value)
    {
    case RenderStage::Unknown: return "UNKNOWN";
    case RenderStage::MainGBufferBuilding: return "MAIN_GBUFFER_BUILDING";
    case RenderStage::MainGBufferComplete: return "MAIN_GBUFFER_COMPLETE";
    case RenderStage::MainDeferredLighting: return "MAIN_DEFERRED_LIGHTING";
    case RenderStage::MainPostDeferred: return "MAIN_POST_DEFERRED";
    case RenderStage::MainSceneComplete: return "MAIN_SCENE_COMPLETE";
    case RenderStage::MainPostProcess: return "MAIN_POST_PROCESS";
    case RenderStage::AuxiliaryRender: return "AUXILIARY_RENDER";
    }
    return "UNKNOWN";
}

const char *to_string(CandidateStage value) noexcept
{
    switch (value)
    {
    case CandidateStage::None: return "NONE";
    case CandidateStage::DeferredLikeBuilding: return "DEFERRED_LIKE_BUILDING";
    case CandidateStage::DeferredLikeComplete: return "DEFERRED_LIKE_COMPLETE";
    }
    return "UNKNOWN";
}

const char *to_string(NativeContext value) noexcept
{
    switch (value)
    {
    case NativeContext::None: return "NONE";
    case NativeContext::Main: return "MAIN";
    case NativeContext::StandardProbe: return "STANDARD_PROBE";
    case NativeContext::HeroProbe: return "HERO_PROBE";
    case NativeContext::Impostor: return "IMPOSTOR";
    case NativeContext::OtherAuxiliary: return "OTHER_AUXILIARY";
    }
    return "UNKNOWN";
}

} // namespace slrb
