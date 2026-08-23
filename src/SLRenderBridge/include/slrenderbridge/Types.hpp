#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace slrb
{
constexpr std::size_t kMaxColorAttachments = 8;
constexpr std::size_t kStageHistoryCapacity = 24;

enum class ClassificationState : std::uint32_t
{
    Uninitialized = 0,
    Observing,
    MainCandidate,
    MainConfirmed,
    AuxiliaryConfirmed,
    Ambiguous,
};

enum class Confidence : std::uint32_t
{
    None = 0,
    StructuralCandidate,
    SourceBackedNativeMarker,
};

enum class RenderStage : std::uint32_t
{
    Unknown = 0,
    MainGBufferBuilding = 10,
    MainGBufferComplete = 20,
    MainDeferredLighting = 30,
    MainPostDeferred = 40,
    MainSceneComplete = 50,
    MainPostProcess = 60,
    AuxiliaryRender = 100,
};

enum class CandidateStage : std::uint32_t
{
    None = 0,
    DeferredLikeBuilding,
    DeferredLikeComplete,
};

enum class NativeContext : std::uint32_t
{
    None = 0,
    Main,
    StandardProbe,
    HeroProbe,
    Impostor,
    OtherAuxiliary,
};

enum class NativeEventKind : std::uint32_t
{
    MainViewBegin = 1,
    MainGBufferBound = 2,
    MainGBufferComplete = 3,
    MainDeferredLightingBegin = 4,
    MainPostDeferredBegin = 5,
    MainSceneComplete = 6,
    MainPostProcessBegin = 7,
    MainFrameComplete = 8,
    StandardProbeBegin = 20,
    HeroProbeBegin = 21,
    ImpostorBegin = 22,
    OtherAuxiliaryBegin = 23,
    AuxiliaryEnd = 24,
    Matrices = 40,
    RendererResourcesInvalidated = 50,
};

struct ResourceRef
{
    std::uint64_t view = 0;
    std::uint64_t resource = 0;
    std::uint32_t width = 0;
    std::uint32_t height = 0;
    std::uint32_t format = 0;
    std::uint32_t usage = 0;

    bool valid() const noexcept { return resource != 0; }
};

struct TargetSet
{
    std::array<ResourceRef, kMaxColorAttachments> colors{};
    std::uint32_t color_count = 0;
    bool color_count_overflow = false;
    ResourceRef depth{};

    bool empty() const noexcept;
    bool deferred_like_candidate() const noexcept;
    bool contains_resource(std::uint64_t resource) const noexcept;
    std::uint64_t identity_hash() const noexcept;
    bool same_resources(const TargetSet &other) const noexcept;
};

struct MatrixSet
{
    bool available = false;
    std::array<float, 16> modelview{};
    std::array<float, 16> projection{};
    std::array<float, 16> inv_modelview{};
    std::array<float, 16> inv_projection{};
    std::array<float, 16> modelview_delta{};
    std::array<float, 16> inv_modelview_delta{};
};

struct StageHistoryEntry
{
    RenderStage stage = RenderStage::Unknown;
    std::uint64_t frame_id = 0;
    std::string reason;
};

struct BridgeSnapshot
{
    ClassificationState classification = ClassificationState::Uninitialized;
    Confidence confidence = Confidence::None;
    RenderStage stage = RenderStage::Unknown;
    CandidateStage candidate_stage = CandidateStage::None;
    NativeContext native_context = NativeContext::None;

    std::uint64_t frame_id = 0;
    std::uint64_t resource_generation = 0;
    std::uint64_t candidate_epoch = 0;
    std::uint64_t native_frame_id = 0;

    TargetSet current_target{};
    TargetSet candidate_gbuffer{};
    TargetSet confirmed_main_gbuffer{};
    MatrixSet matrices{};

    std::uint64_t auxiliary_render_count = 0;
    std::uint64_t main_view_publication_count = 0;
    std::uint64_t rejected_auxiliary_candidate_count = 0;
    std::uint64_t ambiguous_candidate_count = 0;
    std::uint64_t image_write_count = 0;

    std::string last_invalidation_reason;
    std::vector<StageHistoryEntry> stage_history;
};

const char *to_string(ClassificationState value) noexcept;
const char *to_string(Confidence value) noexcept;
const char *to_string(RenderStage value) noexcept;
const char *to_string(CandidateStage value) noexcept;
const char *to_string(NativeContext value) noexcept;

} // namespace slrb
