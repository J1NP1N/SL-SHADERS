# Avatar SSR Receiver Workstream

Base/integration branch: `agent/ssr-background-depth`
Base commit: `44c41bc07c632cca11b4b289743f2cdcd5d9512b`
Feature branch: `agent/ssr-avatar-receiver`

Goal: restore SSR **on avatar materials as receivers** without changing the proven v0.49 avatar-as-hit/source thickness architecture.

Immutable backbone:
- WORLD hit/source path: `Dstatic + Cstatic`
- AVATAR hit/source path: `[D0,DavatarBack]`
- DDA remains off
- do not alter native plumbing unless a missing receiver material input is proven necessary

Receiver task:
- identify avatar receiver pixels and usable avatar normals/material response;
- trace reflected rays primarily against static-world `Dstatic`;
- sample static-world hit color from `Cstatic`;
- apply reflection only according to avatar material/specular/roughness response;
- preserve world-receiver SSR behavior;
- keep avatar receiver path independently switchable and diagnosable;
- do not reintroduce the old secondary-avatar ghost.

Required technique label prefix: `AVATAR RECEIVER — ...`

Required first milestone diagnostics:
1. avatar receiver eligibility mask;
2. avatar receiver normal/reflection-direction view;
3. avatar-to-static-world accepted-hit mask;
4. avatar receiver SSR contribution only;
5. final composite with avatar receiver path on/off comparison.

Stop at the first runtime-testable milestone and report exact commit SHA, FX path, technique order, controls/defaults, and confirmation that `[D0,DavatarBack]` avatar-hit logic is unchanged.
