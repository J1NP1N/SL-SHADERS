# SLRB Alpha Depth State Audit

## Scope

Determine the depth behavior required for production nearest-layer semantic capture and separate it from diagnostic-only behavior.

## Proven state

- `ALPHA_DEPTH` publication works in ReShade.
- Sentinel initialization works.
- Semantic resource publication/readback is not the primary blocker.
- Disabling depth test does not restore samples in the failing normal replay path.
- Therefore the zero-raster failure is not classified as depth rejection.

## Depth conclusions

### Production requirement

The production semantic tuple requires one winning fragment authority:

```
depth + alpha + normal + flags
```

must describe the same nearest semantic fragment.

The production invariant is:

> For every semantic pixel, the stored alpha, normal, flags, and depth values originate from the same rasterized fragment selected by the same depth test.

## Private semantic depth lifetime

Required model:

1. Bind private semantic depth.
2. Clear/refresh at the semantic capture boundary.
3. Render semantic candidates using that depth authority.
4. Publish alpha/normal/flags from the same pass or equivalent coherent fragment selection.
5. Keep the depth resource alive until semantic consumers complete.

Current lifetime and refresh points remain runtime/source investigation items.

## Water ordering

Production policy should define whether semantic capture is pre-water or post-water.

Nearest world-layer semantics require:

```
opaque/alpha semantic capture
        -> private semantic depth
        -> water/post effects
```

Water should only participate if explicitly included in the semantic contract.

Current ordering is not yet runtime proven.

## Private depth versus diagnostic depth

Original-draw MRT depth is diagnostic only.

It cannot guarantee an independent nearest coherent alpha tuple because native depth writes belong to the original renderer path.

Production capture requires a private semantic depth authority.

## Coverage limitations

Depth-related limitations that remain valid:

- alpha-tested/discarded surfaces can reduce coverage;
- transparent blended surfaces need an explicit nearest-layer policy;
- MSAA/sample rules can affect edge coverage;
- water/transparency ordering can change semantic ownership;
- geometry replay coverage may differ from native rendering.

These are separate from the known zero-raster transform failure.

## Current investigation boundary

The current primary unknowns are:

1. replay transform/model matrix synchronization;
2. missing alpha/transparency render path coverage;
3. shader family coverage gaps.

Depth correctness is required for final tuple coherence but is not the current explanation for zero raster samples.
