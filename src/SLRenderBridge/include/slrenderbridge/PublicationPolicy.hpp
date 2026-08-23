#pragma once

#include "Types.hpp"

#include <array>
#include <cstdint>

namespace slrb
{
struct PublicationKey
{
    std::uint64_t generation = 0;
    std::array<std::uint64_t, 4> resources{};

    bool valid() const noexcept
    {
        return generation != 0 && resources[0] != 0 && resources[1] != 0 && resources[2] != 0 && resources[3] != 0;
    }

    bool operator==(const PublicationKey &other) const noexcept
    {
        return generation == other.generation && resources == other.resources;
    }

    bool operator!=(const PublicationKey &other) const noexcept
    {
        return !(*this == other);
    }
};

inline PublicationKey make_publication_key(const BridgeSnapshot &snapshot) noexcept
{
    PublicationKey key;
    key.generation = snapshot.resource_generation;
    key.resources[0] = snapshot.confirmed_main_gbuffer.colors[0].resource;
    key.resources[1] = snapshot.confirmed_main_gbuffer.colors[1].resource;
    key.resources[2] = snapshot.confirmed_main_gbuffer.colors[2].resource;
    key.resources[3] = snapshot.confirmed_main_gbuffer.depth.resource;
    return key;
}

inline bool publication_requires_rebuild(const PublicationKey &current, const BridgeSnapshot &snapshot) noexcept
{
    const PublicationKey next = make_publication_key(snapshot);
    return !next.valid() || current != next;
}
} // namespace slrb
