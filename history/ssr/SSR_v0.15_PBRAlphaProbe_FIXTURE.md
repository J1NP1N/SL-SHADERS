# SSR v0.15 PBRAlphaProbe test fixture

Runtime test fixture supplied 2026-08-19.

Known PBR glass material editor state:

- Alpha mode: `Blend`
- Base color alpha: `0.500`
- Metallic factor: `1.000`
- Roughness factor: `1.000`
- ORM texture appearance: magenta, so the sampled ORM is expected to be approximately AO=1, roughness=0, metallic=1 before factors.
- Double sided: off in the supplied editor screenshot.

Known texture asset UUIDs:

- Base color: `2fe6eb37-163d-7bea-7163-a2c5e805e8ac`
- Metallic/Roughness ORM: `ae33719a-14d1-d228-2ad1-70adddebe890`
- Normal: `4ed76883-9057-3be5-c18e-1b878bf9dd88`

These UUIDs are validation fingerprints for this fixture, not the production runtime classifier. The ReShade/OpenGL add-on does not currently receive the Second Life asset UUID or inventory material name when a GL texture is bound.

v0.15 therefore detects the renderer path from Firestorm state instead: standard alpha blending plus the PBR alpha shader sampler/uniform signature, then snapshots the scene target before/after the first contiguous PBR-alpha segment and publishes a difference mask as `SL_PBR_ALPHA_MASK`.
