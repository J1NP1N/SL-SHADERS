# SLRB Alpha Semantic Depth-State Audit

## Scope

Audit of depth behavior required for production nearest-layer semantic capture.

## Known runtime facts

- `ALPHA_DEPTH` works in ReShade.
- Semantic color remained sentinel under normal replay.
- Disabling depth test still produced zero raster samples in the failing main-view replay.
- Therefore zero raster samples are not explained by depth rejection.
- Original-draw MRT is diagnostic-only because native depth writes do not guarantee an independent coherent nearest alpha tuple.

## Invariants

### Private semantic depth lifetime

Status: FAIL / requires runtime proof.

Production requires a dedicated private semantic depth lifetime:

1. Allocate or acquire private semantic depth.
2. Clear it at the semantic capture boundary.
3. Render semantic candidates using the same depth authority that selects the winning fragment.
4. Preserve depth until alpha, normal, and flags consumers complete.

A bound depth resource alone is not proof of correct lifetime.

### Refresh points

Status: FAIL / requires runtime proof.

Required refresh points:

- render-target recreation,
- resize,
- renderer reset,
- semantic frame start,
- before dependent semantic consumers.

Resource identity must not be assumed stable across viewer lifecycle events.

### Water ordering

Status: FAIL / policy not yet runtime-proven.

Production nearest-layer semantic capture should be pre-water unless water is explicitly part of the semantic contract.

Post-water capture risks selecting water/reflection/distortion layers instead of world geometry.

### Private depth ownership

Status: PASS as architecture requirement.

Production requires:

```
private semantic depth
        +
same raster pass
        +
alpha/normal/flags writes
```

The selected fragment must be identical for all tuple components.

### Diagnostic vs production depth

Original MRT depth is diagnostic only.

It may demonstrate availability of depth-related data but cannot guarantee nearest-layer semantic coherence.

## Coverage limitations

Depth-related limitations that remain valid:

- alpha-tested discard can create holes;
- blended transparency requires an explicit semantic policy;
- MSAA/sample behavior can affect edge coverage;
- water inclusion changes the semantic layer definition;
- LOD/culling mismatch can alter coverage.

These must not be confused with the known zero-raster transform failure.

## Production invariant

For every semantic pixel P:

```
winning depth(P)
normal(P)
flags(P)
alpha(P)
```

must originate from the same rasterized fragment and the same depth comparison.

Required production model:

```
private depth attachment
        |
semantic draw
        |
nearest fragment selection
        |
coherent alpha + normal + flags tuple
```

## Result

The production requirement is not "have a depth texture".

The requirement is a private nearest-layer depth authority shared with all semantic outputs.
